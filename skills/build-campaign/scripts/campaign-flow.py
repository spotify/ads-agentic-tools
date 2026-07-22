#!/usr/bin/env python3
"""Deterministic runner for the Spotify Ads draft campaign workflow.

The agent supplies a reviewed JSON plan on stdin. This script owns API I/O,
dependent ID propagation, audience estimates, hierarchy validation, and publish
version checks so the model does not have to orchestrate each request.
"""

import argparse
import concurrent.futures
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


BASE_URL = "https://api-partner.spotify.com/ads/v3"
HTTP_TIMEOUT_SECONDS = 30
VALID_OBJECTIVES = {
    "REACH", "CLICKS", "VIDEO_VIEWS", "CONVERSIONS", "LEAD_GEN",
    "EVEN_IMPRESSION_DELIVERY", "PODCAST_STREAMS", "APP_INSTALLS",
    "WEBSITE_VISITS",
}
VALID_FORMATS = {"AUDIO", "VIDEO", "IMAGE", "CATALOG"}
VALID_BID_STRATEGIES = {"MAX_BID", "COST_PER_RESULT", "AUTOBID", "UNSET"}
VALID_PLATFORMS = {"ANDROID", "DESKTOP", "IOS"}


class FlowError(Exception):
    def __init__(self, message, *, status=None, body=None, partial=None):
        super().__init__(message)
        self.status = status
        self.body = body
        self.partial = partial


def emit(payload, exit_code=0):
    print(json.dumps(payload, indent=2, sort_keys=True))
    raise SystemExit(exit_code)


def read_stdin_json(default=None):
    raw = sys.stdin.read()
    if not raw.strip():
        if default is not None:
            return default
        raise FlowError("Expected a JSON object on stdin")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise FlowError(f"Invalid JSON on stdin: {exc}") from exc
    if not isinstance(value, dict):
        raise FlowError("The stdin JSON value must be an object")
    return value


def repo_root():
    return Path(__file__).resolve().parents[3]


def platform_config(root):
    if os.environ.get("CODEX_PROJECT_DIR") or os.environ.get("CODEX_PLUGIN_ROOT"):
        return "codex", [".codex", ".claude", ".agents"], ".codex-plugin/plugin.json", "codex-plugin"
    if os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("CLAUDE_PLUGIN_ROOT"):
        return "claude", [".claude", ".codex", ".agents"], ".claude-plugin/plugin.json", "claude-code-plugin"
    return "antigravity", [".agents", ".claude", ".codex"], "plugin.json", "antigravity-cli-plugin"


def parse_frontmatter(path):
    settings = {}
    in_frontmatter = False
    for line in path.read_text().splitlines():
        if line.strip() == "---":
            if in_frontmatter:
                break
            in_frontmatter = True
            continue
        if in_frontmatter and ":" in line:
            key, value = line.split(":", 1)
            settings[key.strip()] = value.strip().strip('"').strip("'")
    return settings


def load_context():
    root = repo_root()
    platform, settings_order, manifest_path, sdk_product = platform_config(root)
    project_dir = Path(
        os.environ.get("CODEX_PROJECT_DIR")
        or os.environ.get("CLAUDE_PROJECT_DIR")
        or os.getcwd()
    )
    settings_path = next(
        (project_dir / directory / "spotify-ads-api.local.md" for directory in settings_order
         if (project_dir / directory / "spotify-ads-api.local.md").is_file()),
        None,
    )
    if settings_path is None:
        raise FlowError("No Spotify Ads API settings file found; run configure first")
    settings = parse_frontmatter(settings_path)
    token = settings.get("access_token", "")
    account_id = settings.get("ad_account_id", "")
    if not token or not account_id:
        raise FlowError("Settings are missing access_token or ad_account_id; run configure again")
    try:
        manifest = json.loads((root / manifest_path).read_text())
        version = manifest["version"]
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        raise FlowError(f"Could not read plugin version from {manifest_path}: {exc}") from exc
    return {
        "platform": platform,
        "account_id": account_id,
        "headers": {
            "Authorization": f"Bearer {token}",
            "X-Spotify-Ads-Sdk": f"{sdk_product}/{version}",
            "X-Spotify-Ads-Skill": "build-campaign",
        },
    }


def request(context, method, path, body=None):
    headers = dict(context["headers"])
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body, separators=(",", ":")).encode()
    req = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_SECONDS) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode() if exc.fp else ""
        try:
            parsed = json.loads(raw) if raw.strip() else None
        except json.JSONDecodeError:
            parsed = raw
        raise FlowError(f"{method} {path} returned HTTP {exc.code}", status=exc.code, body=parsed) from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise FlowError(f"{method} {path} failed: {exc}") from exc


def require_text(value, path):
    if not isinstance(value, str) or not value.strip():
        raise FlowError(f"{path} must be a non-empty string")


def validate_plan(plan):
    campaign = plan.get("campaign")
    ad_sets = plan.get("ad_sets")
    if not isinstance(campaign, dict):
        raise FlowError("campaign must be an object")
    require_text(campaign.get("name"), "campaign.name")
    if campaign.get("objective") not in VALID_OBJECTIVES:
        raise FlowError("campaign.objective is missing or invalid")
    if not isinstance(ad_sets, list) or not ad_sets:
        raise FlowError("ad_sets must be a non-empty array")
    for index, ad_set in enumerate(ad_sets):
        prefix = f"ad_sets[{index}]"
        if not isinstance(ad_set, dict):
            raise FlowError(f"{prefix} must be an object")
        for field in ("name", "start_time", "category"):
            require_text(ad_set.get(field), f"{prefix}.{field}")
        if ad_set.get("asset_format") not in VALID_FORMATS:
            raise FlowError(f"{prefix}.asset_format is missing or invalid")
        if ad_set.get("bid_strategy") not in VALID_BID_STRATEGIES:
            raise FlowError(f"{prefix}.bid_strategy is missing or invalid")
        if ad_set["bid_strategy"] in {"MAX_BID", "COST_PER_RESULT"} and not isinstance(ad_set.get("bid_micro_amount"), int):
            raise FlowError(f"{prefix}.bid_micro_amount is required for {ad_set['bid_strategy']}")
        budget = ad_set.get("budget")
        if not isinstance(budget, dict) or not isinstance(budget.get("micro_amount"), int) or budget["micro_amount"] <= 0:
            raise FlowError(f"{prefix}.budget.micro_amount must be a positive integer")
        if budget.get("type") not in {"DAILY", "LIFETIME"}:
            raise FlowError(f"{prefix}.budget.type must be DAILY or LIFETIME")
        if budget["type"] == "LIFETIME" and not ad_set.get("end_time"):
            raise FlowError(f"{prefix}.end_time is required for LIFETIME budgets")
        targets = ad_set.get("targets")
        if not isinstance(targets, dict) or not isinstance(targets.get("geo_targets"), dict):
            raise FlowError(f"{prefix}.targets.geo_targets must be an object")
        require_text(targets["geo_targets"].get("country_code"), f"{prefix}.targets.geo_targets.country_code")
        invalid_platforms = set(targets.get("platforms", [])) - VALID_PLATFORMS
        if invalid_platforms:
            raise FlowError(f"{prefix}.targets.platforms contains invalid values: {sorted(invalid_platforms)}")
        ads = ad_set.get("ads")
        if not isinstance(ads, list) or not ads:
            raise FlowError(f"{prefix}.ads must be a non-empty array")
        for ad_index, ad in enumerate(ads):
            ad_prefix = f"{prefix}.ads[{ad_index}]"
            if not isinstance(ad, dict):
                raise FlowError(f"{ad_prefix} must be an object")
            for field in ("name", "tagline", "advertiser_name"):
                require_text(ad.get(field), f"{ad_prefix}.{field}")
            assets = ad.get("assets")
            if not isinstance(assets, dict):
                raise FlowError(f"{ad_prefix}.assets must be an object")
            for field in ("asset_id", "logo_asset_id"):
                require_text(assets.get(field), f"{ad_prefix}.assets.{field}")
            if ad_set["asset_format"] == "AUDIO":
                require_text(assets.get("companion_asset_id"), f"{ad_prefix}.assets.companion_asset_id")
            cta = ad.get("call_to_action")
            if not isinstance(cta, dict):
                raise FlowError(f"{ad_prefix}.call_to_action must be an object")
            require_text(cta.get("key"), f"{ad_prefix}.call_to_action.key")
            require_text(cta.get("clickthrough_url"), f"{ad_prefix}.call_to_action.clickthrough_url")


def prepare(args):
    spec = read_stdin_json(default={})
    context = load_context()
    jobs = {
        "categories": ("GET", "/ad_categories"),
        "assets": ("GET", f"/ad_accounts/{context['account_id']}/assets?limit=50&sort_direction=DESC"),
    }
    for index, query in enumerate(spec.get("geo_queries", [])):
        country = urllib.parse.quote(str(query.get("country_code", "")))
        term = urllib.parse.quote(str(query.get("q", "")))
        jobs[f"geo_{index}"] = ("GET", f"/targets/geos?country_code={country}&q={term}&limit=20")
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(jobs))) as executor:
        futures = {executor.submit(request, context, method, path): name for name, (method, path) in jobs.items()}
        for future in concurrent.futures.as_completed(futures):
            name = futures[future]
            _, results[name] = future.result()
    emit({"ok": True, "operation": "prepare", "results": results})


def estimate_body(context, objective, ad_set):
    body = {
        "ad_account_id": context["account_id"],
        "start_date": ad_set["start_time"],
        "asset_format": ad_set["asset_format"],
        "objective": objective,
        "bid_strategy": ad_set["bid_strategy"],
        "budget": {**ad_set["budget"], "currency": "USD"},
        "targets": ad_set["targets"],
        "category": ad_set["category"],
    }
    for field in ("end_time", "bid_micro_amount", "frequency_caps", "video_delivery_formats"):
        if field in ad_set:
            body["end_date" if field == "end_time" else field] = ad_set[field]
    return body


def build(args):
    plan = read_stdin_json()
    validate_plan(plan)
    context = load_context()
    objective = plan["campaign"]["objective"]
    estimates = [None] * len(plan["ad_sets"])
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(estimates))) as executor:
        futures = {
            executor.submit(request, context, "POST", "/estimates/audience", estimate_body(context, objective, ad_set)): index
            for index, ad_set in enumerate(plan["ad_sets"])
        }
        for future in concurrent.futures.as_completed(futures):
            index = futures[future]
            _, estimates[index] = future.result()

    created = {"campaign": None, "ad_sets": [], "ads": []}
    try:
        _, campaign = request(context, "POST", f"/ad_accounts/{context['account_id']}/drafts/campaigns", plan["campaign"])
        campaign_id = campaign["id"]
        created["campaign"] = {"id": campaign_id, "name": campaign.get("name", plan["campaign"]["name"])}
        for ad_set in plan["ad_sets"]:
            ad_set_payload = {key: value for key, value in ad_set.items() if key != "ads"}
            ad_set_payload["campaign_id"] = campaign_id
            _, created_ad_set = request(context, "POST", f"/ad_accounts/{context['account_id']}/drafts/ad_sets", ad_set_payload)
            ad_set_id = created_ad_set["id"]
            created["ad_sets"].append({"id": ad_set_id, "name": created_ad_set.get("name", ad_set["name"])})
            for ad in ad_set["ads"]:
                ad_payload = dict(ad)
                ad_payload["ad_set_id"] = ad_set_id
                _, created_ad = request(context, "POST", f"/ad_accounts/{context['account_id']}/drafts/ads", ad_payload)
                created["ads"].append({"id": created_ad["id"], "ad_set_id": ad_set_id, "name": created_ad.get("name", ad["name"])})
        _, current = request(context, "GET", f"/ad_accounts/{context['account_id']}/drafts/campaigns/{campaign_id}")
        version = current["draft_hierarchy_version"]
        _, validation = request(
            context, "POST", f"/ad_accounts/{context['account_id']}/drafts/campaigns/{campaign_id}",
            {"action": "VALIDATE", "draft_hierarchy_version": version},
        )
    except FlowError as exc:
        exc.partial = created
        raise
    emit({
        "ok": True,
        "operation": "build",
        "audience_estimates": estimates,
        "draft": created,
        "draft_hierarchy_version": version,
        "validation": validation,
    })


def publish(args):
    if args.confirm_publish != "PUBLISH":
        raise FlowError("Publishing requires --confirm-publish PUBLISH after explicit user confirmation")
    context = load_context()
    path = f"/ad_accounts/{context['account_id']}/drafts/campaigns/{args.draft_campaign_id}"
    _, current = request(context, "GET", path)
    validated_version = current["draft_hierarchy_version"]
    _, validation = request(context, "POST", path, {"action": "VALIDATE", "draft_hierarchy_version": validated_version})
    if validation and validation.get("validation_errors"):
        raise FlowError("Draft validation failed; publish was not attempted", body=validation)
    _, latest = request(context, "GET", path)
    latest_version = latest["draft_hierarchy_version"]
    if latest_version != validated_version:
        _, validation = request(context, "POST", path, {"action": "VALIDATE", "draft_hierarchy_version": latest_version})
        if validation and validation.get("validation_errors"):
            raise FlowError("Draft changed and revalidation failed; publish was not attempted", body=validation)
    _, result = request(context, "POST", path, {"action": "PUBLISH", "draft_hierarchy_version": latest_version})
    emit({"ok": True, "operation": "publish", "draft_hierarchy_version": latest_version, "result": result})


def main():
    parser = argparse.ArgumentParser(description="Build and publish Spotify Ads draft campaigns")
    subparsers = parser.add_subparsers(dest="operation", required=True)
    prepare_parser = subparsers.add_parser("prepare", help="Fetch categories, assets, and optional geo matches")
    prepare_parser.set_defaults(handler=prepare)
    build_parser = subparsers.add_parser("build", help="Estimate, create, and validate a reviewed JSON plan")
    build_parser.set_defaults(handler=build)
    publish_parser = subparsers.add_parser("publish", help="Validate and publish an existing draft hierarchy")
    publish_parser.add_argument("--draft-campaign-id", required=True)
    publish_parser.add_argument("--confirm-publish", required=True)
    publish_parser.set_defaults(handler=publish)
    args = parser.parse_args()
    try:
        args.handler(args)
    except FlowError as exc:
        emit({
            "ok": False,
            "error": str(exc),
            "http_status": exc.status,
            "response": exc.body,
            "partial_draft": exc.partial,
        }, exit_code=1)


if __name__ == "__main__":
    main()
