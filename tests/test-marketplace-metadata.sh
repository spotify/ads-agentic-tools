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
copilot_manifest = load(".plugin/plugin.json")
cursor_manifest = load(".cursor-plugin/plugin.json")
cursor_marketplace = load(".cursor-plugin/marketplace.json")

manifests = [codex_manifest, claude_manifest, antigravity_manifest, copilot_manifest, cursor_manifest]
marketplaces = [codex_marketplace, claude_marketplace, cursor_marketplace]

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

assert cursor_marketplace["plugins"][0]["source"] == "./"
assert cursor_marketplace["owner"]["name"]

# Codex-only and Antigravity-only fields stay out of the other manifests.
for manifest in (copilot_manifest, cursor_manifest):
    assert "interface" not in manifest
    assert "contextFileName" not in manifest

# Copilot checks .plugin/plugin.json before the root plugin.json, and the root
# hooks.json is Antigravity's. Each manifest must name its own hooks file, whose
# command uses the plugin-root variable that platform sets for hooks.
def hook_commands(relative_path):
    hooks = load(relative_path)["hooks"]
    for event in hooks.values():
        for entry in event:
            if "hooks" in entry:
                for hook in entry["hooks"]:
                    yield entry.get("matcher"), hook["command"]
            else:
                yield entry.get("matcher"), entry["command"]

assert copilot_manifest["hooks"] == "./.plugin/hooks.json"
assert list(hook_commands(".plugin/hooks.json")) == [
    ("Bash", 'bash "${COPILOT_PLUGIN_ROOT}/hooks/check-token.sh"'),
]
assert cursor_manifest["hooks"] == "./.cursor-plugin/hooks.json"
assert load(".cursor-plugin/hooks.json")["version"] == 1
assert list(hook_commands(".cursor-plugin/hooks.json")) == [
    ("Shell", 'bash "${CURSOR_PLUGIN_ROOT}/hooks/check-token.sh"'),
]
for manifest in (copilot_manifest, cursor_manifest):
    for key in ("skills", "agents", "hooks"):
        assert (root / manifest[key]).exists(), key

# Claude's UI treats a root settings.json as upload metadata and requires
# settings.json.agent to be a string. Platform tool permissions belong in the
# skill and agent frontmatter, so the legacy object-valued file must stay absent.
assert not (root / "settings.json").exists()

print("Marketplace metadata checks passed")
PY
