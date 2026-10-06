#!/usr/bin/env python3
"""Turn a recorded Claude Code session into an eval history_file.

Usage: trim-transcript.py <session.jsonl> <out.jsonl> [--stop-after-line N]

The Skill call and the skill text it loaded are always removed: a history that
carried them would keep testing the skill as it was when recorded. Start the
case prompt with the skill's slash command instead, so each run loads the
current SKILL.md.

Keeps only user and assistant messages (drops attachments, environment
snapshots, and other session bookkeeping), stops after line N of the source
if given, relinks each message to the one before it, and replaces local paths
so nothing machine-specific is checked in.
"""
import json
import re
import sys

KEEP_KEYS = {"type", "uuid", "parentUuid", "message", "isMeta", "isSidechain",
             "timestamp", "toolUseResult", "sourceToolAssistantUUID", "userType"}


def scrub(text, plugin_root, workspace):
    text = text.replace(plugin_root, "/plugin")
    text = text.replace(workspace, "/workspace")
    text = re.sub(r"/var/folders/[^\s\"'\\]+/T/+", "/tmp/", text)
    return re.sub(r"/Users/[^/\s\"'\\]+", "/Users/user", text)


def main():
    src, out = sys.argv[1], sys.argv[2]
    stop = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[3] == "--stop-after-line" else None
    lines = [json.loads(l) for l in open(src)]
    plugin_root = workspace = None
    for m in lines:
        workspace = workspace or m.get("cwd")
        text = json.dumps(m)
        found = re.search(r"Base directory for this skill: (\S+?)/skills/", text)
        if found:
            plugin_root = found.group(1)
    skill_calls = set()
    for m in lines:
        content = (m.get("message") or {}).get("content")
        if m.get("type") == "assistant" and isinstance(content, list):
            skill_calls |= {b["id"] for b in content if b.get("type") == "tool_use" and b.get("name") == "Skill"}
    kept, parent = [], None
    for i, m in enumerate(lines):
        if stop is not None and i > stop:
            break
        if m.get("type") not in ("user", "assistant"):
            continue
        content = (m.get("message") or {}).get("content")
        if isinstance(content, list):
            content = [b for b in content
                       if not (b.get("type") == "tool_use" and b.get("id") in skill_calls)
                       and not (b.get("type") == "tool_result" and b.get("tool_use_id") in skill_calls)]
            if not content:
                continue
            m["message"]["content"] = content
        if m.get("isMeta") and "Base directory for this skill:" in json.dumps(m):
            continue
        m = {k: v for k, v in m.items() if k in KEEP_KEYS}
        m["parentUuid"] = parent
        parent = m["uuid"]
        kept.append(m)
    with open(out, "w") as f:
        for m in kept:
            f.write(scrub(json.dumps(m), plugin_root or "\0", workspace or "\0") + "\n")
    print(f"wrote {len(kept)} messages to {out}")


if __name__ == "__main__":
    main()
