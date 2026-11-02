#!/usr/bin/env python3
"""Spotify Ads API OpenAPI helper: describe, search, and validate operations.

Standard library only, so the plugin keeps its zero-dependency footprint. It
reads the document that fetch-openapi-schema.sh downloaded for the current
workflow; it never downloads anything itself.

    openapi_tool.py describe [--spec FILE] <METHOD> <path> [--full]
    openapi_tool.py search   [--spec FILE] [query words...] [--limit N]
    openapi_tool.py validate [--spec FILE] <METHOD> <path>   (JSON body on stdin)
    openapi_tool.py locate                                   (print the spec path)
    openapi_tool.py to-json  [--spec FILE]                   (debug: parsed spec)

Without --spec, the document is $OPENAPI_FILE, else the file recorded by the
last fetch-openapi-schema.sh run (see current_spec_pointer), if it is still
there and less than POINTER_MAX_AGE seconds old.

<path> may be a template (ad_accounts/{ad_account_id}/campaigns) or a concrete
request path with a query string, with or without a leading slash or /ads/v3.

validate exit codes: 0 valid, 3 the request violates the spec (it must not be
sent), 4 the operation is not in the spec, 2 the spec could not be read.
"""

import difflib
import json
import math
import os
import re
import sys
from urllib.parse import parse_qsl

METHODS = ("get", "put", "post", "delete", "options", "head", "patch", "trace")
POINTER_MAX_AGE = 6 * 3600


def current_spec_pointer():
    """Must match the pointer path written by fetch-openapi-schema.sh."""
    tmp = os.environ.get("TMPDIR") or "/tmp"
    uid = os.getuid() if hasattr(os, "getuid") else 0
    return os.path.join(tmp, "spotify-ads-api-openapi-%d.current" % uid)


def locate_spec():
    explicit = os.environ.get("OPENAPI_FILE")
    if explicit:
        return explicit if os.path.isfile(explicit) else None
    try:
        with open(current_spec_pointer(), encoding="utf-8") as fh:
            path = fh.read().strip()
        import time
        if path and os.path.isfile(path) and time.time() - os.stat(path).st_mtime < POINTER_MAX_AGE:
            return path
    except OSError:
        pass
    return None

# ---------------------------------------------------------------------------
# Minimal YAML loader
#
# Covers the block-style subset the published spec uses: nested mappings and
# sequences, compact "- key: value" items, plain, single-, and double-quoted
# scalars (including multi-line ones), literal and folded block scalars, and
# flow collections. Anchors, aliases, tags, and multi-document streams are
# rejected rather than misread.
# ---------------------------------------------------------------------------


class YamlError(ValueError):
    pass


_INT = re.compile(r"^[-+]?(0|[1-9][0-9]*)$")
_FLOAT = re.compile(r"^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$")


def _plain(text):
    if text in ("", "~", "null", "Null", "NULL"):
        return None
    if text in ("true", "True", "TRUE"):
        return True
    if text in ("false", "False", "FALSE"):
        return False
    if _INT.match(text):
        return int(text)
    if _FLOAT.match(text) and any(c.isdigit() for c in text):
        return float(text)
    if text[0] in "&*!%@`":
        raise YamlError("unsupported YAML construct: %r" % text[:40])
    return text


def _fold(lines):
    """Join the physical lines of a multi-line flow scalar (YAML line folding)."""
    out, pending_breaks = "", 0
    for idx, line in enumerate(lines):
        piece = line if idx == 0 else line.strip()
        if idx == len(lines) - 1 and idx:
            piece = line.strip()
        if idx and piece == "":
            pending_breaks += 1
            continue
        if idx:
            out += "\n" * pending_breaks if pending_breaks else " "
            pending_breaks = 0
        out += piece
    return out


def _decode_double(body):
    escapes = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "/": "/",
               "0": "\0", " ": " ", "b": "\b", "f": "\f", "e": "\x1b", "a": "\a",
               "v": "\v", "N": "\x85", "_": "\xa0", "L": "\u2028", "P": "\u2029"}
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = body[i + 1]
        if nxt in escapes:
            out.append(escapes[nxt])
            i += 2
        elif nxt in "xuU":
            width = {"x": 2, "u": 4, "U": 8}[nxt]
            out.append(chr(int(body[i + 2:i + 2 + width], 16)))
            i += 2 + width
        elif nxt == "\n":  # escaped line break: join without a space
            i += 2
            while i < len(body) and body[i] in " \t":
                i += 1
        else:
            raise YamlError("bad escape \\%s" % nxt)
    return "".join(out)


def _quoted_end(text, start):
    """Index just past the quoted scalar starting at text[start], or -1."""
    quote, i = text[start], start + 1
    while i < len(text):
        c = text[i]
        if quote == "'" and c == "'":
            if i + 1 < len(text) and text[i + 1] == "'":
                i += 2
                continue
            return i + 1
        if quote == '"' and c == "\\":
            i += 2
            continue
        if quote == '"' and c == '"':
            return i + 1
        i += 1
    return -1


def _decode_quoted(raw):
    quote, body = raw[0], raw[1:-1]
    if quote == "'":
        # Fold first: '' is an escaped quote and never spans lines.
        return _fold(body.split("\n")).replace("''", "'")
    # Double-quoted: protect escaped newlines before folding.
    parts = re.split(r"(?<!\\)\n", body)
    return _decode_double(_fold(parts))


class _FlowParser:
    def __init__(self, text):
        self.s, self.i = text, 0

    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t\n\r":
            self.i += 1

    def value(self):
        self.ws()
        c = self.s[self.i]
        if c == "[":
            self.i += 1
            out = []
            while True:
                self.ws()
                if self.s[self.i] == "]":
                    self.i += 1
                    return out
                out.append(self.value())
                self.ws()
                if self.s[self.i] == ",":
                    self.i += 1
        if c == "{":
            self.i += 1
            out = {}
            while True:
                self.ws()
                if self.s[self.i] == "}":
                    self.i += 1
                    return out
                key = self.value()
                self.ws()
                val = None
                if self.s[self.i] == ":":
                    self.i += 1
                    self.ws()
                    if self.s[self.i] not in ",}":
                        val = self.value()
                out[str(key)] = val
                self.ws()
                if self.s[self.i] == ",":
                    self.i += 1
        if c in "'\"":
            end = _quoted_end(self.s, self.i)
            raw = self.s[self.i:end]
            self.i = end
            return _decode_quoted(raw)
        start = self.i
        while self.i < len(self.s) and self.s[self.i] not in ",]}":
            if self.s[self.i] == ":" and (self.i + 1 == len(self.s) or self.s[self.i + 1] in " ,]}"):
                break
            self.i += 1
        return _plain(" ".join(self.s[start:self.i].split()))


def _flow_balanced(text):
    depth, i = 0, 0
    while i < len(text):
        c = text[i]
        if c in "'\"":
            end = _quoted_end(text, i)
            if end < 0:
                return False
            i = end
            continue
        if c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
        i += 1
    return depth == 0


def _strip_comment(text):
    """Drop a trailing ' # comment' from a plain scalar."""
    m = re.search(r"(^|\s)#", text)
    return text[:m.start()].rstrip() if m else text.rstrip()


class _Yaml:
    def __init__(self, text):
        self.lines = text.replace("\r\n", "\n").split("\n")
        self.i = 0

    @staticmethod
    def indent(line):
        return len(line) - len(line.lstrip(" "))

    def skip_blank(self):
        while self.i < len(self.lines):
            stripped = self.lines[self.i].strip()
            if stripped == "" or stripped.startswith("#") or stripped == "---":
                self.i += 1
            else:
                return

    def peek(self):
        self.skip_blank()
        if self.i >= len(self.lines):
            return None, None
        line = self.lines[self.i]
        if "\t" in line[:self.indent(line) + 1]:
            raise YamlError("tab indentation on line %d" % (self.i + 1))
        n = self.indent(line)
        return n, line[n:]

    def node(self, min_indent):
        n, body = self.peek()
        if n is None or n < min_indent:
            return None
        if body == "-" or body.startswith("- "):
            return self.seq(n)
        return self.mapping(n)

    def split_key(self, body):
        if body[0] in "'\"":
            end = _quoted_end(body, 0)
            if end > 0 and body[end:end + 1] == ":" and body[end + 1:end + 2] in ("", " "):
                return _decode_quoted(body[:end]), body[end + 1:].strip()
            return None
        m = re.match(r"^([^#'\"\[\]{},][^:]*?|[^#'\"\[\]{},]):( |$)", body)
        if not m:
            return None
        return m.group(1).strip(), body[m.end():].strip()

    def mapping(self, n):
        out = {}
        while True:
            k, body = self.peek()
            if k is None or k < n:
                return out
            if k > n:
                raise YamlError("unexpected indentation on line %d" % (self.i + 1))
            if body == "-" or body.startswith("- "):
                return out
            parts = self.split_key(body)
            if parts is None:
                raise YamlError("expected 'key: value' on line %d: %r" % (self.i + 1, body[:60]))
            key, rest = parts
            if key == "<<":
                raise YamlError("merge keys are not supported (line %d)" % (self.i + 1))
            self.i += 1
            out[key] = self.value(rest, n, in_mapping=True)

    def seq(self, n):
        out = []
        while True:
            k, body = self.peek()
            if k is None or k != n or not (body == "-" or body.startswith("- ")):
                return out
            rest = body[1:]
            content = rest.lstrip(" ")
            if content == "" or content.startswith("#"):
                self.i += 1
                out.append(self.value("", n, in_mapping=False))
                continue
            offset = n + 1 + (len(rest) - len(content))
            if content == "-" or content.startswith("- ") or self.split_key(content) is not None:
                # Re-read this line as the first line of a nested block.
                self.lines[self.i] = " " * offset + content
                out.append(self.node(offset))
                continue
            self.i += 1
            out.append(self.value(content, n, in_mapping=False))

    def continuation(self, parent):
        """Following lines that belong to a multi-line flow or plain scalar."""
        lines = []
        while self.i < len(self.lines):
            line = self.lines[self.i]
            if line.strip() == "":
                lines.append("")
                self.i += 1
                continue
            if self.indent(line) <= parent:
                break
            lines.append(line)
            self.i += 1
        while lines and lines[-1] == "":
            lines.pop()
            self.i -= 1
        return lines

    def block_scalar(self, header, parent):
        m = re.match(r"^([|>])([-+]?)([1-9]?)([-+]?)\s*(#.*)?$", header)
        if not m:
            raise YamlError("bad block scalar header %r" % header)
        style, chomp = m.group(1), m.group(2) or m.group(4)
        explicit = m.group(3)
        raw = []
        while self.i < len(self.lines):
            line = self.lines[self.i]
            if line.strip() and self.indent(line) <= parent:
                break
            raw.append(line)
            self.i += 1
        trailing = 0
        while raw and raw[-1].strip() == "":
            raw.pop()
            trailing += 1
        self.i -= 0  # trailing blank lines were consumed; harmless for parsing
        if explicit:
            width = parent + int(explicit)
        else:
            width = min((self.indent(l) for l in raw if l.strip()), default=parent + 1)
        body = [l[width:] if l.strip() else "" for l in raw]
        if style == "|":
            text = "\n".join(body)
        else:
            text, prev_more = "", False
            for idx, line in enumerate(body):
                more = line.startswith(" ") or line == ""
                if idx == 0:
                    text = line
                elif line == "":
                    text += "\n"
                elif text.endswith("\n") or more or prev_more:
                    text += ("" if text.endswith("\n") else "\n") + line
                else:
                    text += " " + line
                prev_more = line.startswith(" ")
        if not body:
            return ""
        if chomp == "-":
            return text
        if chomp == "+":
            return text + "\n" * (trailing + 1)
        return text + "\n"

    def value(self, rest, parent, in_mapping):
        if rest == "" or rest.startswith("#"):
            k, body = self.peek()
            if k is None:
                return None
            if k > parent:
                return self.node(parent + 1)
            if in_mapping and k == parent and (body == "-" or body.startswith("- ")):
                return self.seq(parent)
            return None
        if rest[0] in "|>":
            return self.block_scalar(rest, parent)
        if rest[0] in "'\"":
            text = rest
            while _quoted_end(text, 0) < 0:
                if self.i >= len(self.lines):
                    raise YamlError("unterminated quoted scalar")
                text += "\n" + self.lines[self.i]
                self.i += 1
            end = _quoted_end(text, 0)
            tail = text[end:].strip()
            if tail and not tail.startswith("#"):
                raise YamlError("text after quoted scalar on line %d" % self.i)
            return _decode_quoted(text[:end])
        if rest[0] in "[{":
            text = rest
            while not _flow_balanced(text):
                if self.i >= len(self.lines):
                    raise YamlError("unterminated flow collection")
                text += "\n" + self.lines[self.i]
                self.i += 1
            return _FlowParser(text).value()
        first = _strip_comment(rest)
        more = self.continuation(parent)
        if not more:
            return _plain(first)
        return _fold([first] + [_strip_comment(l) for l in more])


def load_yaml(text):
    stripped = text.lstrip()
    if stripped.startswith("{"):
        return json.loads(text)
    parser = _Yaml(text)
    doc = parser.node(0)
    if parser.peek()[0] is not None:
        raise YamlError("could not parse line %d" % (parser.i + 1))
    return doc


def load_spec(path):
    """Parse the spec, reusing a JSON cache keyed by the file's size and mtime."""
    st = os.stat(path)
    stamp = "%d:%d" % (st.st_size, st.st_mtime_ns)
    cache = path + ".parsed.json"
    try:
        with open(cache, encoding="utf-8") as fh:
            cached = json.load(fh)
        if cached.get("stamp") == stamp:
            return cached["spec"]
    except (OSError, ValueError, KeyError):
        pass
    with open(path, encoding="utf-8") as fh:
        spec = load_yaml(fh.read())
    if not isinstance(spec, dict) or "paths" not in spec:
        raise YamlError("not an OpenAPI document")
    try:
        tmp = "%s.%d" % (cache, os.getpid())
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump({"stamp": stamp, "spec": spec}, fh)
        os.replace(tmp, cache)
    except OSError:
        pass
    return spec


# ---------------------------------------------------------------------------
# Schema resolution
# ---------------------------------------------------------------------------


class Spec:
    def __init__(self, doc):
        self.doc = doc

    def deref(self, node, seen=None):
        seen = seen or set()
        while isinstance(node, dict) and "$ref" in node:
            ref = node["$ref"]
            if ref in seen or not ref.startswith("#/"):
                return {}
            seen.add(ref)
            target = self.doc
            for part in ref[2:].split("/"):
                target = target.get(part.replace("~1", "/").replace("~0", "~"), {})
            # Sibling keys next to $ref (description, readOnly) are kept on top.
            extra = {k: v for k, v in node.items() if k != "$ref"}
            node = dict(target, **extra) if extra else target
        return node

    def flatten(self, schema, depth=0):
        """Resolve $ref and merge allOf. oneOf/anyOf are left for the caller."""
        schema = self.deref(schema)
        if not isinstance(schema, dict) or depth > 20:
            return {}
        if "allOf" not in schema:
            return schema
        merged = {k: v for k, v in schema.items() if k != "allOf"}
        props = dict(merged.get("properties", {}))
        required = list(merged.get("required", []))
        mistakes = list(merged.get("x-spotify-common-mistakes", []))
        for part in schema["allOf"]:
            sub = self.flatten(part, depth + 1)
            for key, val in sub.items():
                if key == "properties":
                    for name, prop in val.items():
                        props.setdefault(name, prop)
                elif key == "required":
                    required += [r for r in val if r not in required]
                elif key == "x-spotify-common-mistakes":
                    mistakes += val
                elif key == "additionalProperties":
                    if val is False or "additionalProperties" not in merged:
                        merged[key] = val
                elif key not in merged:
                    merged[key] = val
        if props:
            merged["properties"] = props
        if required:
            merged["required"] = required
        if mistakes:
            merged["x-spotify-common-mistakes"] = mistakes
        return merged

    # -- operations ---------------------------------------------------------

    def operations(self):
        for path, item in self.doc.get("paths", {}).items():
            for method in METHODS:
                if isinstance(item, dict) and method in item:
                    yield method.upper(), path, item[method], item

    def find_operation(self, method, raw_path):
        """Match a request path against the spec's templates."""
        path = raw_path.split("?", 1)[0].split("#", 1)[0]
        path = "/" + path.strip("/")
        for prefix in self.server_prefixes():
            if prefix and (path == prefix or path.startswith(prefix + "/")):
                path = path[len(prefix):] or "/"
                break
        segs = path.strip("/").split("/") if path.strip("/") else []
        best, best_score = None, -1
        path_known = False
        for op_method, template, op, item in self.operations():
            tsegs = template.strip("/").split("/") if template.strip("/") else []
            if len(tsegs) != len(segs):
                continue
            params, score = {}, 0
            for t, s in zip(tsegs, segs):
                m = re.fullmatch(r"\{([^}]+)\}", t)
                if m:
                    params[m.group(1)] = s
                elif t == s:
                    score += 1
                else:
                    break
            else:
                path_known = True
                if op_method == method.upper() and score > best_score:
                    best, best_score = (template, op, item, params), score
        return best, path_known

    def server_prefixes(self):
        out = []
        for server in self.doc.get("servers", []):
            url = server.get("url", "")
            m = re.match(r"^[a-z]+://[^/]+(/.*)?$", url)
            out.append((m.group(1) if m else url).rstrip("/"))
        return out

    def parameters(self, op, item):
        params = {}
        for raw in (item.get("parameters") or []) + (op.get("parameters") or []):
            param = self.deref(raw)
            params[(param.get("in"), param.get("name"))] = param
        return list(params.values())

    def json_body(self, op):
        body = self.deref(op.get("requestBody") or {})
        content = body.get("content") or {}
        for ctype, media in content.items():
            if ctype.split(";")[0].strip().endswith("json"):
                return body, ctype, media.get("schema") or {}
        if content:
            return body, next(iter(content)), None
        return body, None, None


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

_JSON_TYPE = {dict: "object", list: "array", str: "string", bool: "boolean",
              int: "integer", float: "number", type(None): "null"}


def _type_name(value):
    return _JSON_TYPE.get(type(value), type(value).__name__)


def _type_ok(expected, value):
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool) or (
            isinstance(value, float) and value.is_integer())
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return expected == _type_name(value)


class Validator:
    def __init__(self, spec):
        self.spec = spec
        self.errors = []

    def error(self, where, message, schema=None, field=None):
        hint = self.mistake_hint(schema, field)
        self.errors.append("%s: %s%s" % (where, message, (" Hint: " + hint) if hint else ""))

    @staticmethod
    def mistake_hint(schema, field):
        if not schema or not field:
            return ""
        for item in schema.get("x-spotify-common-mistakes") or []:
            if isinstance(item, dict) and item.get("field") == field and item.get("correct"):
                return item["correct"]
        return ""

    def check(self, schema, value, where, parent=None, field=None, depth=0):
        if depth > 40:
            return
        schema = self.spec.flatten(schema)
        if not schema:
            return
        if value is None:
            if not schema.get("nullable"):
                self.error(where, "null is not allowed here.", parent, field)
            return
        if "oneOf" in schema or "anyOf" in schema:
            self.check_union(schema, value, where, depth)
            return
        expected = schema.get("type")
        if expected is None and "properties" in schema:
            expected = "object"
        if expected and not _type_ok(expected, value):
            self.error(where, "expected %s, got %s." % (expected, _type_name(value)), parent, field)
            return
        if "enum" in schema and value not in schema["enum"]:
            self.error(where, "%s is not one of: %s." % (
                json.dumps(value), ", ".join(json.dumps(v) for v in schema["enum"])), parent, field)
            return
        if isinstance(value, str):
            self.check_bounds(where, len(value), schema, "minLength", "maxLength", "characters")
        elif isinstance(value, (int, float)) and not isinstance(value, bool):
            if "minimum" in schema and value < schema["minimum"]:
                self.error(where, "%s is below the minimum %s." % (value, schema["minimum"]))
            if "maximum" in schema and value > schema["maximum"]:
                self.error(where, "%s is above the maximum %s." % (value, schema["maximum"]))
        elif isinstance(value, list):
            self.check_bounds(where, len(value), schema, "minItems", "maxItems", "items")
            for idx, item in enumerate(value):
                self.check(schema.get("items") or {}, item, "%s[%d]" % (where, idx), schema, field, depth + 1)
        elif isinstance(value, dict):
            self.check_object(schema, value, where, depth)

    def check_bounds(self, where, size, schema, low, high, unit):
        if low in schema and size < schema[low]:
            self.error(where, "has %d %s; at least %d required." % (size, unit, schema[low]))
        if high in schema and size > schema[high]:
            self.error(where, "has %d %s; at most %d allowed." % (size, unit, schema[high]))

    def check_object(self, schema, value, where, depth):
        props = schema.get("properties") or {}
        for name in schema.get("required") or []:
            prop = self.spec.flatten(props.get(name, {}))
            if name not in value and not prop.get("readOnly"):
                self.error("%s.%s" % (where, name), "required field is missing.", schema, name)
        extra = schema.get("additionalProperties")
        for name, item in value.items():
            if name in props:
                prop = self.spec.flatten(props[name])
                if prop.get("readOnly"):
                    self.error("%s.%s" % (where, name), "is read-only and must not be sent.", schema, name)
                    continue
                self.check(props[name], item, "%s.%s" % (where, name), schema, name, depth + 1)
            elif isinstance(extra, dict):
                self.check(extra, item, "%s.%s" % (where, name), schema, name, depth + 1)
            elif props and extra is not True:
                close = difflib.get_close_matches(name, list(props), n=1, cutoff=0.6)
                suggestion = " Did you mean %r?" % close[0] if close else ""
                self.error("%s.%s" % (where, name),
                           "is not a field the spec defines here.%s Allowed: %s." % (
                               suggestion, ", ".join(sorted(props))), schema, name)

    def check_union(self, schema, value, where, depth):
        branches = schema.get("oneOf") or schema.get("anyOf")
        disc = schema.get("discriminator") or {}
        prop = disc.get("propertyName")
        if prop and isinstance(value, dict):
            mapping = disc.get("mapping") or {}
            if prop not in value:
                self.error("%s.%s" % (where, prop), "required discriminator is missing (one of: %s)." % (
                    ", ".join(mapping)))
                return
            ref = mapping.get(value[prop])
            if ref is None and mapping:
                self.error("%s.%s" % (where, prop), "%s is not one of: %s." % (
                    json.dumps(value[prop]), ", ".join(mapping)))
                return
            if ref:
                self.check({"$ref": ref}, value, where, depth=depth + 1)
                return
        best = None
        for branch in branches:
            trial = Validator(self.spec)
            trial.check(branch, value, where, depth=depth + 1)
            if not trial.errors:
                return
            if best is None or len(trial.errors) < len(best):
                best = trial.errors
        self.errors.append("%s: matches none of the allowed shapes. Closest match failed with:" % where)
        self.errors += ["  " + e for e in best or []]


def _coerce_query(value, schema):
    kind = schema.get("type")
    try:
        if kind == "integer":
            return int(value)
        if kind == "number":
            return float(value)
    except ValueError:
        return value
    if kind == "boolean" and value in ("true", "false"):
        return value == "true"
    return value


def validate_request(spec, method, raw_path, body_text):
    """Return (status, messages). status: ok, invalid, unknown."""
    found, path_known = spec.find_operation(method, raw_path)
    if not found:
        if path_known:
            allowed = sorted({m for m, t, _o, _i in spec.operations()
                              if spec.find_operation(m, raw_path)[0]})
            return "unknown", ["%s is not defined for this path. Defined methods: %s." % (
                method.upper(), ", ".join(allowed) or "none")]
        return "unknown", ["No operation in the spec matches %s %s." % (method.upper(), raw_path)]
    template, op, item, _path_params = found
    v = Validator(spec)

    # Query parameters
    query = raw_path.split("?", 1)[1] if "?" in raw_path else ""
    pairs = parse_qsl(query, keep_blank_values=True)
    declared = {p["name"]: p for p in spec.parameters(op, item) if p.get("in") == "query"}
    seen = {}
    for name, val in pairs:
        seen.setdefault(name, []).append(val)
    for name, values in seen.items():
        param = declared.get(name)
        if param is None:
            close = difflib.get_close_matches(name, list(declared), n=1, cutoff=0.6)
            v.errors.append("query.%s: is not a query parameter of %s %s.%s Allowed: %s." % (
                name, method.upper(), template,
                (" Did you mean %r?" % close[0]) if close else "",
                ", ".join(sorted(declared)) or "none"))
            continue
        schema = spec.flatten(param.get("schema") or {})
        if schema.get("type") == "array":
            items = spec.flatten(schema.get("items") or {})
            parts = []
            for val in values:
                # Repeated names are the convention; a comma joins values only if the spec says so.
                parts += val.split(",") if param.get("explode") is False else [val]
            v.check(schema, [_coerce_query(p, items) for p in parts], "query.%s" % name)
        else:
            if len(values) > 1:
                v.errors.append("query.%s: given %d times but is not an array." % (name, len(values)))
            v.check(schema, _coerce_query(values[-1], schema), "query.%s" % name)
    for name, param in declared.items():
        if param.get("required") and name not in seen:
            v.errors.append("query.%s: required query parameter is missing." % name)

    # JSON body
    body_def, ctype, schema = spec.json_body(op)
    body_text = body_text.strip()
    if body_text:
        if ctype is None:
            v.errors.append("body: %s %s does not accept a request body." % (method.upper(), template))
        elif schema is not None:
            try:
                body = json.loads(body_text)
            except ValueError as exc:
                v.errors.append("body: is not valid JSON (%s)." % exc)
            else:
                v.check(schema, body, "body")
    elif body_def.get("required"):
        v.errors.append("body: %s %s requires a request body." % (method.upper(), template))

    return ("invalid" if v.errors else "ok"), v.errors


# ---------------------------------------------------------------------------
# Describe
# ---------------------------------------------------------------------------


def _short(text, full):
    text = " ".join(str(text or "").split())
    if full or len(text) <= 140:
        return text
    cut = text[:140]
    stop = cut.rfind(". ")
    return (cut[:stop + 1] if stop > 60 else cut.rstrip()) + " …"


def _type_label(spec, schema):
    schema = spec.flatten(schema)
    if "oneOf" in schema or "anyOf" in schema:
        names = []
        for branch in schema.get("oneOf") or schema.get("anyOf"):
            ref = branch.get("$ref", "") if isinstance(branch, dict) else ""
            names.append(ref.rsplit("/", 1)[-1] or _type_label(spec, branch))
        return "one of: " + " | ".join(names)
    kind = schema.get("type") or ("object" if "properties" in schema else "any")
    if kind == "array":
        return "array of " + _type_label(spec, schema.get("items") or {})
    label = kind
    if schema.get("format"):
        label += " " + str(schema["format"]).split()[0]
    return label


def _constraints(schema):
    bits = []
    if "enum" in schema:
        bits.append("enum: " + ", ".join(str(v) for v in schema["enum"]))
    for key in ("minLength", "maxLength", "minimum", "maximum", "minItems", "maxItems", "pattern"):
        if key in schema:
            bits.append("%s=%s" % (key, schema[key]))
    if "default" in schema:
        bits.append("default=%s" % json.dumps(schema["default"]))
    if schema.get("nullable"):
        bits.append("nullable")
    if schema.get("deprecated"):
        bits.append("DEPRECATED")
    return bits


def _describe_schema(spec, schema, indent, full, lines, stack):
    schema = spec.flatten(schema)
    if "oneOf" in schema or "anyOf" in schema:
        disc = (schema.get("discriminator") or {})
        mapping = disc.get("mapping") or {}
        branches = schema.get("oneOf") or schema.get("anyOf")
        for idx, branch in enumerate(branches):
            ref = branch.get("$ref", "") if isinstance(branch, dict) else ""
            name = ref.rsplit("/", 1)[-1] or "variant %d" % (idx + 1)
            when = [k for k, v in mapping.items() if v == ref]
            head = "when %s=%s" % (disc.get("propertyName"), "/".join(when)) if when else "variant"
            lines.append("%s[%s → %s]" % (" " * indent, head, name))
            _describe_schema(spec, branch, indent + 2, full, lines, stack)
        return
    if schema.get("type") == "array":
        schema = spec.flatten(schema.get("items") or {})
    props = schema.get("properties") or {}
    required = set(schema.get("required") or [])
    for name, raw in props.items():
        prop = spec.flatten(raw)
        if prop.get("readOnly"):
            continue
        mark = "*" if name in required else ""
        bits = [_type_label(spec, prop)] + _constraints(prop)
        desc = _short(prop.get("description"), full)
        lines.append("%s%s%s: %s%s" % (" " * indent, name, mark, "; ".join(bits),
                                      (" — " + desc) if desc else ""))
        hint = Validator.mistake_hint(schema, name)
        if hint:
            lines.append("%s  ! %s" % (" " * indent, hint))
        target = prop
        if target.get("type") == "array":
            target = spec.flatten(target.get("items") or {})
        key = id(target)
        expandable = (target.get("properties") or "oneOf" in target or "anyOf" in target
                      or isinstance(target.get("additionalProperties"), dict))
        if expandable and key not in stack:
            _describe_schema(spec, target, indent + 2, full, lines, stack | {key})
    extra = schema.get("additionalProperties")
    if isinstance(extra, dict):
        lines.append("%s<any key>: %s" % (" " * indent, _type_label(spec, extra)))


def describe(spec, method, raw_path, full=False):
    found, path_known = spec.find_operation(method, raw_path)
    if not found:
        raise LookupError(validate_request(spec, method, raw_path, "")[1][0])
    template, op, item, _params = found
    lines = ["%s %s%s" % (method.upper(), template,
                          ("  (%s)" % op["operationId"]) if op.get("operationId") else "")]
    if op.get("deprecated"):
        lines.append("DEPRECATED")
    for text in (op.get("summary"), op.get("description")):
        if text:
            lines.append(_short(text, full))
    params = spec.parameters(op, item)
    for where in ("path", "query", "header"):
        group = [p for p in params if p.get("in") == where]
        if not group:
            continue
        lines.append("%s parameters (* = required):" % where.capitalize())
        for p in group:
            schema = spec.flatten(p.get("schema") or {})
            bits = [_type_label(spec, p.get("schema") or {})] + _constraints(schema)
            items = spec.flatten(schema.get("items") or {}) if schema.get("type") == "array" else {}
            bits += ["items " + c for c in _constraints(items)]
            if schema.get("type") == "array":
                bits.append("repeat the name for each value")
            desc = _short(p.get("description"), full)
            lines.append("  %s%s: %s%s" % (p["name"], "*" if p.get("required") else "",
                                          "; ".join(bits), (" — " + desc) if desc else ""))
    body_def, ctype, schema = spec.json_body(op)
    if ctype:
        lines.append("Request body (%s)%s (* = required; read-only fields omitted):" % (
            ctype, ", required" if body_def.get("required") else ""))
        if schema is None:
            lines.append("  (non-JSON body; see the skill for the upload procedure)")
        else:
            ref = schema.get("$ref", "") if isinstance(schema, dict) else ""
            if ref:
                lines[-1] += "  [%s]" % ref.rsplit("/", 1)[-1]
            _describe_schema(spec, schema, 2, full, lines, frozenset())
    codes = ", ".join(str(c) for c in (op.get("responses") or {}))
    if codes:
        lines.append("Responses: " + codes)
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Search (BM25 over operations)
# ---------------------------------------------------------------------------


def _tokens(text):
    text = re.sub(r"([a-z])([A-Z])", r"\1 \2", str(text or ""))
    words = re.findall(r"[a-z0-9]+", text.lower())
    out = []
    for w in words:
        out.append(w)
        if len(w) > 3 and w.endswith("ies"):
            out.append(w[:-3] + "y")
        elif len(w) > 3 and w.endswith("s") and not w.endswith("ss"):
            out.append(w[:-1])
    return out


_STOP = {"a", "an", "the", "of", "to", "for", "in", "on", "by", "and", "or", "with", "my", "i", "me"}
_VERBS = {"create": "post", "add": "post", "make": "post", "new": "post", "list": "get", "get": "get",
          "show": "get", "find": "get", "fetch": "get", "read": "get", "update": "patch",
          "edit": "patch", "change": "patch", "modify": "patch", "pause": "patch", "delete": "delete",
          "remove": "delete"}


def search(spec, query, limit=10):
    docs = []
    for method, path, op, _item in spec.operations():
        weighted = (_tokens(path) * 2 + _tokens(op.get("operationId")) * 2 + _tokens(op.get("summary")) * 2
                    + _tokens(" ".join(op.get("tags") or [])) + _tokens(op.get("description"))
                    + [method.lower()])
        docs.append((method, path, op, weighted))
    terms = [t for t in _tokens(query) if t not in _STOP]
    terms += [_VERBS[t] for t in list(terms) if t in _VERBS]
    if not terms:
        ranked = [(0, d) for d in docs]
    else:
        n = len(docs)
        avg = sum(len(d[3]) for d in docs) / max(n, 1)
        df = {t: sum(1 for d in docs if t in d[3]) for t in set(terms)}
        ranked = []
        for d in docs:
            length, score = len(d[3]), 0.0
            for t in terms:
                tf = d[3].count(t)
                if tf:
                    idf = math.log(1 + (n - df[t] + 0.5) / (df[t] + 0.5))
                    score += idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * length / avg))
            if score > 0:
                ranked.append((score, d))
        ranked.sort(key=lambda x: -x[0])
        ranked = ranked[:limit]
    return "\n".join("%-6s %s — %s" % (m, p, _short(op.get("summary") or op.get("operationId"), False))
                     for _s, (m, p, op, _w) in ranked)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        sys.stderr.write(__doc__)
        return 1
    command, rest = argv[0], argv[1:]
    spec_path = None
    if "--spec" in rest:
        idx = rest.index("--spec")
        spec_path = rest[idx + 1] if idx + 1 < len(rest) else None
        rest = rest[:idx] + rest[idx + 2:]
    else:
        spec_path = locate_spec()
    if command == "locate":
        if not spec_path:
            return 2
        print(spec_path)
        return 0
    if not spec_path:
        sys.stderr.write("ERROR: No OpenAPI document for this workflow. Fetch it first: "
                         "skills/api-reference/references/live-openapi.md\n")
        return 2
    try:
        doc = load_spec(spec_path)
    except (OSError, ValueError) as exc:
        sys.stderr.write("ERROR: Could not read the OpenAPI document %s: %s\n" % (spec_path, exc))
        return 2
    spec = Spec(doc)

    if command == "to-json":
        json.dump(doc, sys.stdout, sort_keys=True)
        return 0
    if command == "search":
        limit = 10
        if "--limit" in rest:
            idx = rest.index("--limit")
            limit = int(rest[idx + 1])
            rest = rest[:idx] + rest[idx + 2:]
        print(search(spec, " ".join(rest), limit) or "No matching operations.")
        return 0
    if command in ("describe", "validate") and len(rest) >= 2:
        method, path = rest[0], rest[1]
        if command == "describe":
            try:
                print(describe(spec, method, path, full="--full" in rest))
            except LookupError as exc:
                sys.stderr.write("ERROR: %s\n" % exc)
                return 4
            return 0
        body = sys.stdin.read() if not sys.stdin.isatty() else ""
        status, messages = validate_request(spec, method, path, body)
        for line in messages:
            print(line)
        return {"ok": 0, "invalid": 3, "unknown": 4}[status]
    sys.stderr.write(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
