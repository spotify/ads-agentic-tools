#!/usr/bin/env python3
# /// script
# dependencies = ["canonicaljson"]
# ///
"""Generate a deterministic dedup key from a request fingerprint."""
import hashlib
import json
import sys

try:
    import canonicaljson

    HAS_CANONICAL = True
except ImportError:
    HAS_CANONICAL = False

body = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else ""
base_url = sys.argv[2]
path = sys.argv[3]
method = sys.argv[4].upper()
client_id = sys.argv[5] if len(sys.argv) > 5 else ""

try:
    parsed = json.loads(body)
    if HAS_CANONICAL:
        canonical = canonicaljson.encode_canonical_json(parsed).decode("utf-8")
    else:
        canonical = json.dumps(parsed, sort_keys=True, separators=(",", ":"))
except (json.JSONDecodeError, ValueError):
    canonical = body

fingerprint = base_url + "|" + method + "|" + path + "|" + client_id + "|" + canonical
print(hashlib.sha256(fingerprint.encode()).hexdigest())
