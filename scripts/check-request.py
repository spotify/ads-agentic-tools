#!/usr/bin/env python3
"""Check a planned Ads API v3 request against the OpenAPI document.

Usage: check-request.py <openapi.yaml> <METHOD> <path[?query]> [json_body]

Prints "OK" or one line per problem (unknown path, method, query parameter,
enum value, or body field) and exits 0 when OK, 1 on problems, 2 on usage or
parse errors. Uses only the standard library: the YAML reader below handles
the block/flow subset that the published document uses.
"""
import json
import re
import sys
from urllib.parse import parse_qsl, urlsplit


# --- minimal YAML reader -----------------------------------------------------

def _scalar(text):
    text = text.strip()
    if text == "" or text in ("~", "null"):
        return None
    if text[0] in "\"'":
        if text[0] == '"':
            return json.loads(text)
        return text[1:-1].replace("''", "'")
    if text in ("true", "false"):
        return text == "true"
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d+\.\d*(e[-+]?\d+)?", text, re.I):
        return float(text)
    return text


def _flow(text):
    """Parse a one-line flow collection such as [A, B] or {a: 1}."""
    pos = 0

    def skip():
        nonlocal pos
        while pos < len(text) and text[pos] == " ":
            pos += 1

    def value():
        nonlocal pos
        skip()
        ch = text[pos]
        if ch == "[":
            pos += 1
            out = []
            skip()
            if text[pos] == "]":
                pos += 1
                return out
            while True:
                out.append(value())
                skip()
                ch = text[pos]
                pos += 1
                if ch == "]":
                    return out
        if ch == "{":
            pos += 1
            out = {}
            skip()
            if text[pos] == "}":
                pos += 1
                return out
            while True:
                key = token(":")
                pos += 1
                out[key] = value()
                skip()
                ch = text[pos]
                pos += 1
                if ch == "}":
                    return out
        return _scalar(token(",]}"))

    def token(stops):
        nonlocal pos
        skip()
        if text[pos] in "\"'":
            quote = text[pos]
            end = pos + 1
            while text[end] != quote or (quote == '"' and text[end - 1] == "\\"):
                end += 1
            raw = text[pos:end + 1]
            pos = end + 1
            return _scalar(raw)
        start = pos
        while pos < len(text) and text[pos] not in stops:
            pos += 1
        return text[start:pos].strip()

    return value()


def _strip_comment(line):
    if "#" not in line:
        return line
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] == " "):
            return line[:i].rstrip()
    return line


def load_yaml(text):
    lines = []
    for raw in text.splitlines():
        lines.append(raw)
    index = 0

    def indent_of(line):
        return len(line) - len(line.lstrip(" "))

    def next_content():
        nonlocal index
        while index < len(lines):
            stripped = _strip_comment(lines[index]).strip()
            if stripped and stripped != "---":
                return index
            index += 1
        return None

    def block_scalar(parent_indent):
        nonlocal index
        body = []
        while index < len(lines):
            line = lines[index]
            if line.strip() and indent_of(line) <= parent_indent:
                break
            body.append(line)
            index += 1
        return "\n".join(l.strip() for l in body)

    def inline_value(rest, parent_indent):
        rest = rest.strip()
        if rest.startswith(("|", ">")):
            return block_scalar(parent_indent)
        if rest.startswith(("[", "{")):
            return _flow(rest)
        if rest == "":
            nxt = next_content()
            if nxt is None:
                return None
            child = indent_of(lines[nxt])
            stripped = lines[nxt].strip()
            if child > parent_indent or (child == parent_indent and stripped.startswith("- ")):
                return node(child)
            return None
        return _scalar(rest)

    def split_key(content):
        if content[0] in "\"'":
            quote = content[0]
            end = content.index(quote, 1)
            return _scalar(content[:end + 1]), content[end + 1:].lstrip()[1:]
        key, _, rest = content.partition(":")
        return key.strip(), rest

    def node(indent):
        nonlocal index
        first = lines[next_content()].strip()
        if first.startswith("- ") or first == "-":
            out = []
            while next_content() is not None:
                line = _strip_comment(lines[index])
                if indent_of(line) != indent or not line.strip().startswith("-"):
                    break
                content = line.strip()[1:].strip()
                index += 1
                if content == "":
                    out.append(inline_value("", indent))
                elif re.match(r"^(\"[^\"]*\"|'[^']*'|[^\s\"'\[{][^:]*):(\s|$)", content):
                    # A mapping that starts on the dash line.
                    lines.insert(index, " " * (indent + 2) + content)
                    out.append(node(indent + 2))
                else:
                    out.append(inline_value(content, indent))
            return out
        out = {}
        while next_content() is not None:
            line = _strip_comment(lines[index])
            if indent_of(line) != indent or line.strip().startswith("- "):
                break
            key, rest = split_key(line.strip())
            index += 1
            out[key] = inline_value(rest, indent)
        return out

    if next_content() is None:
        return None
    return node(indent_of(lines[index]))


# --- spec helpers ------------------------------------------------------------

def resolve(spec, obj, seen=None):
    seen = seen or set()
    while isinstance(obj, dict) and "$ref" in obj:
        ref = obj["$ref"]
        if ref in seen:
            return {}
        seen.add(ref)
        obj = spec
        for part in ref[2:].split("/"):
            obj = obj[part]
    return obj


def schema_props(spec, schema, depth=0):
    """Return (properties, open) for a schema, merging allOf/oneOf/anyOf."""
    schema = resolve(spec, schema)
    if not isinstance(schema, dict) or depth > 12:
        return {}, True
    props = dict(schema.get("properties") or {})
    open_schema = not props and not any(k in schema for k in ("allOf", "oneOf", "anyOf"))
    if schema.get("additionalProperties") not in (None, False):
        open_schema = True
    for key in ("allOf", "oneOf", "anyOf"):
        for part in schema.get(key) or []:
            sub, sub_open = schema_props(spec, part, depth + 1)
            props.update(sub)
            open_schema = open_schema or sub_open
    return props, open_schema


def required_of(spec, schema, depth=0):
    schema = resolve(spec, schema)
    if not isinstance(schema, dict) or depth > 12:
        return set()
    required = set(schema.get("required") or [])
    for part in schema.get("allOf") or []:
        required |= required_of(spec, part, depth + 1)
    return required


def type_of(spec, schema, depth=0):
    schema = resolve(spec, schema)
    if not isinstance(schema, dict) or depth > 12:
        return None
    if schema.get("type"):
        return schema["type"]
    for part in schema.get("allOf") or []:
        found = type_of(spec, part, depth + 1)
        if found:
            return found
    if schema.get("properties"):
        return "object"
    return None


JSON_TYPES = {
    "object": dict, "array": list, "string": str, "boolean": bool,
    "integer": int, "number": (int, float),
}


def enum_of(spec, schema):
    schema = resolve(spec, schema)
    if not isinstance(schema, dict):
        return None
    if schema.get("type") == "array":
        return enum_of(spec, schema.get("items") or {})
    return schema.get("enum")


def check_body(spec, schema, body, where, problems, depth=0, partial=False):
    if depth > 12:
        return
    resolved = resolve(spec, schema)
    expected = type_of(spec, schema)
    python_type = JSON_TYPES.get(expected)
    if python_type and body is not None and (
            not isinstance(body, python_type) or (isinstance(body, bool) and expected in ("integer", "number"))):
        label = where.rstrip(".") or "body"
        problems.append(f"{label} must be {expected}, got {type(body).__name__}")
        return
    if isinstance(body, list):
        items = (resolved or {}).get("items") if isinstance(resolved, dict) else None
        for i, item in enumerate(body):
            if items is not None:
                check_body(spec, items, item, f"{where}[{i}]", problems, depth + 1)
        return
    if isinstance(body, dict):
        props, open_schema = schema_props(spec, schema)
        if open_schema:
            return
        if not partial:
            for key in sorted(required_of(spec, schema) - set(body)):
                problems.append(f"required body field '{where}{key}' is missing")
        for key, value in body.items():
            if key not in props:
                close = ", ".join(sorted(props)[:40])
                problems.append(f"body field '{where}{key}' is not defined. Defined: {close}")
            else:
                check_body(spec, props[key], value, f"{where}{key}.", problems, depth + 1)
        return
    allowed = enum_of(spec, schema)
    if allowed and body is not None and body not in allowed:
        problems.append(f"body value {where.rstrip('.')}={body!r} is not one of {allowed}")


def match_path(spec, path):
    path = "/" + path.strip("/")
    # Prefer literal segments over {placeholders}, e.g. /audiences/datasets over /audiences/{audience_id}.
    templates = sorted(spec.get("paths", {}), key=lambda t: [seg.startswith("{") for seg in t.split("/")])
    for template in templates:
        pattern = "^" + re.sub(r"\\\{[^}]+\\\}", r"[^/]+", re.escape(template)) + "$"
        if re.match(pattern, path):
            return template
    return None


def closest_paths(spec, path, limit=5):
    words = set(re.findall(r"[a-z_]+", path.lower())) - {"ad_accounts"}
    scored = []
    for template in spec.get("paths", {}):
        overlap = len(words & set(re.findall(r"[a-z_]+", template.lower())))
        if overlap:
            scored.append((-overlap, len(template), template))
    found = [t for _, _, t in sorted(scored)[:limit]]
    if found:
        return found
    import difflib
    normalised = re.sub(r"/[0-9a-fA-F-]{36}|/\d+", "/{id}", "/" + path.strip("/"))
    return difflib.get_close_matches(normalised, list(spec.get("paths", {})), n=limit, cutoff=0.4)


# Operations the plugin uses that the public document does not describe.
# They are passed through unchecked rather than blocked.
UNDOCUMENTED_OPERATIONS = {
    ("get", "/ad_product_catalog"),
}


def undocumented(method, path):
    path = "/" + path.strip("/")
    for op_method, template in UNDOCUMENTED_OPERATIONS:
        pattern = "^" + re.sub(r"\\\{[^}]+\\\}", r"[^/]+", re.escape(template)) + "$"
        if op_method == method and re.match(pattern, path):
            return True
    return False


def check(spec, method, target, body_text):
    problems = []
    method = method.lower()
    parts = urlsplit(target)
    if undocumented(method, parts.path):
        return []
    template = match_path(spec, parts.path)
    if template is None:
        suggestions = "; ".join(closest_paths(spec, parts.path))
        return [f"path '/{parts.path.strip('/')}' is not defined. Closest: {suggestions}"]
    item = spec["paths"][template]
    if method not in item:
        allowed = sorted(k.upper() for k in item if k in ("get", "post", "put", "patch", "delete"))
        return [f"{method.upper()} is not defined for {template}. Allowed: {', '.join(allowed)}"]
    operation = item[method]
    params = {}
    for param in (item.get("parameters") or []) + (operation.get("parameters") or []):
        param = resolve(spec, param)
        params[(param.get("in"), param.get("name"))] = param
    query_names = sorted(name for where, name in params if where == "query")
    for name, value in parse_qsl(parts.query, keep_blank_values=True):
        param = params.get(("query", name))
        if param is None:
            problems.append(f"query parameter '{name}' is not defined for {method.upper()} {template}. "
                            f"Defined: {', '.join(query_names) or 'none'}")
            continue
        schema = resolve(spec, param.get("schema") or {})
        if schema.get("type") == "array" and param.get("explode", True) and "," in value:
            problems.append(f"query {name}={value} joins values with commas. Repeat the parameter instead: "
                            + "&".join(f"{name}={v}" for v in value.split(",")))
            continue
        allowed = enum_of(spec, schema)
        if allowed and value not in allowed:
            others = ", ".join(n for n in query_names if n != name) or "none"
            problems.append(f"query {name}={value} is not one of {allowed}. "
                            f"Other query parameters for {method.upper()} {template}: {others}")
    if body_text:
        try:
            body = json.loads(body_text)
        except ValueError as err:
            return problems + [f"body is not valid JSON: {err}"]
        content = ((operation.get("requestBody") and resolve(spec, operation["requestBody"]))
                   or {}).get("content") or {}
        schema = (content.get("application/json") or next(iter(content.values()), {})).get("schema")
        if schema is None:
            problems.append(f"{method.upper()} {template} takes no request body")
        else:
            # PATCH bodies are partial updates: nested objects are still checked in full.
            check_body(spec, schema, body, "", problems, partial=(method == "patch"))
    return problems


def main(argv):
    if len(argv) not in (4, 5):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            spec = load_yaml(handle.read())
    except (OSError, ValueError, IndexError, KeyError) as err:
        print(f"ERROR: could not read OpenAPI document: {err}", file=sys.stderr)
        return 2
    if not isinstance(spec, dict) or not isinstance(spec.get("paths"), dict) or not spec["paths"]:
        print("ERROR: OpenAPI document parsed without any paths", file=sys.stderr)
        return 2
    target = argv[3].replace("{ad_account_id}", "00000000-0000-0000-0000-000000000000")
    problems = check(spec, argv[2], target, argv[4] if len(argv) == 5 else "")
    if not problems:
        print("OK")
        return 0
    for problem in problems:
        print(problem)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
