#!/bin/bash
# Regression checks for the platform-specific marketplace manifests.
# Run: bash tests/test-marketplace-metadata.sh

set -uo pipefail

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

python3 - "$REPO_ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

def load(relative_path):
    with (root / relative_path).open(encoding="utf-8") as handle:
        return json.load(handle)

codex_marketplace = load(".agents/plugins/marketplace.json")
claude_marketplace = load(".claude-plugin/marketplace.json")
codex_manifest = load(".codex-plugin/plugin.json")
claude_manifest = load(".claude-plugin/plugin.json")
antigravity_manifest = load("plugin.json")

manifests = [codex_manifest, claude_manifest, antigravity_manifest]
marketplaces = [codex_marketplace, claude_marketplace]

expected_name = "spotify-ads-api"
expected_repository = "https://github.com/spotify/ads-agentic-tools.git"

assert all(manifest["name"] == expected_name for manifest in manifests)
assert all(marketplace["name"] == expected_name for marketplace in marketplaces)
assert all(marketplace["plugins"][0]["name"] == expected_name for marketplace in marketplaces)
assert len({manifest["version"] for manifest in manifests}) == 1

codex_source = codex_marketplace["plugins"][0]["source"]
assert codex_source == {"source": "url", "url": expected_repository}

claude_source = claude_marketplace["plugins"][0]["source"]
assert claude_source == "./"

assert codex_marketplace["plugins"][0]["policy"] == {
    "installation": "AVAILABLE",
    "authentication": "ON_INSTALL",
}
assert "interface" not in claude_marketplace
assert "policy" not in claude_marketplace["plugins"][0]

# Claude's UI treats a root settings.json as upload metadata and requires
# settings.json.agent to be a string. Platform tool permissions belong in the
# skill and agent frontmatter, so the legacy object-valued file must stay absent.
assert not (root / "settings.json").exists()

print("Marketplace metadata checks passed")
PY
