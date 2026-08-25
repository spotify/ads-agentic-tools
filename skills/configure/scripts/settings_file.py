#!/usr/bin/env python3
"""Secure read/write helpers for local Spotify Ads API settings."""

import argparse
import datetime
import json
import os
import pathlib
import stat
import sys
import tempfile

DEFAULTS = {
    "access_token": "",
    "refresh_token": "",
    "token_expires_at": "",
    "client_id": "",
    "auth_flow": "",
    "ad_account_id": "",
    "environment": "production",
    "auto_execute": "false",
}
FIELD_ORDER = tuple(DEFAULTS)


def read_settings(path):
    values = dict(DEFAULTS)
    settings_path = pathlib.Path(path)
    if not settings_path.is_file():
        return values

    in_frontmatter = False
    for line in settings_path.read_text(encoding="utf-8").splitlines():
        if line == "---":
            if in_frontmatter:
                break
            in_frontmatter = True
            continue
        if not in_frontmatter or ":" not in line:
            continue
        key, raw_value = line.split(":", 1)
        if key not in values:
            continue
        value = raw_value.strip()
        if len(value) >= 2 and value[0] == value[-1] == '"':
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                value = value[1:-1]
        elif len(value) >= 2 and value[0] == value[-1] == "'":
            value = value[1:-1]
        values[key] = value
    return values


def _render_settings(values):
    lines = ["---"]
    for key in FIELD_ORDER:
        value = values[key]
        if key == "auto_execute":
            lines.append(f"{key}: {'true' if str(value).lower() == 'true' else 'false'}")
        else:
            lines.append(f"{key}: {json.dumps(str(value))}")
    lines.extend([
        "---",
        "",
        "# Spotify Ads API Settings",
        "",
        "Local configuration for the spotify-ads-api plugin.",
        "Do not commit this file to version control.",
        "",
    ])
    return "\n".join(lines)


def write_settings(path, updates):
    """Atomically replace settings with a file created as mode 0600."""
    settings_path = pathlib.Path(path)
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    values = read_settings(settings_path)
    values.update({key: value for key, value in updates.items() if key in values})

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{settings_path.name}.",
        dir=str(settings_path.parent),
        text=True,
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            temporary_file.write(_render_settings(values))
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_name, settings_path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
    return settings_path


def write_oauth_settings(path, tokens, client_id, auto_execute=None, now=None):
    expires_in = int(tokens.get("expires_in", 3600))
    current_time = now or datetime.datetime.now(datetime.timezone.utc)
    expires_at = current_time + datetime.timedelta(seconds=expires_in)
    updates = {
        "access_token": tokens["access_token"],
        "refresh_token": tokens.get("refresh_token", ""),
        "token_expires_at": expires_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "client_id": client_id,
        "auth_flow": "authorization_code_pkce",
    }
    if auto_execute is not None:
        updates["auto_execute"] = auto_execute
    write_settings(path, updates)
    return expires_in


def create_pending_oauth_file(tokens, client_id, auto_execute=None):
    payload = {
        "access_token": tokens["access_token"],
        "refresh_token": tokens.get("refresh_token", ""),
        "expires_in": tokens.get("expires_in", 3600),
        "client_id": client_id,
        "auto_execute": auto_execute,
    }
    descriptor, pending_name = tempfile.mkstemp(prefix="spotify-ads-oauth-", suffix=".json", text=True)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as pending_file:
            json.dump(payload, pending_file)
            pending_file.flush()
            os.fsync(pending_file.fileno())
    except Exception:
        try:
            os.unlink(pending_name)
        except FileNotFoundError:
            pass
        raise
    return pathlib.Path(pending_name)


def finalize_pending_oauth_file(pending_path, settings_path, now=None):
    token_path = pathlib.Path(pending_path)
    token_stat = os.lstat(token_path)
    if not stat.S_ISREG(token_stat.st_mode) or stat.S_IMODE(token_stat.st_mode) != 0o600:
        raise ValueError("pending OAuth result must be a regular mode-0600 file")
    if hasattr(os, "getuid") and token_stat.st_uid != os.getuid():
        raise ValueError("pending OAuth result is owned by another user")
    payload = json.loads(token_path.read_text(encoding="utf-8"))
    access_token = payload.get("access_token")
    if not isinstance(access_token, str) or not access_token:
        raise ValueError("pending OAuth result contains no access token")
    expires_in = write_oauth_settings(
        settings_path,
        payload,
        payload["client_id"],
        payload.get("auto_execute"),
        now=now,
    )
    token_path.unlink()
    return expires_in


def write_direct_token_settings(path, access_token, auto_execute=None):
    updates = {
        "access_token": access_token,
        "refresh_token": "",
        "token_expires_at": "",
        "client_id": "",
        "auth_flow": "direct_token",
    }
    if auto_execute is not None:
        updates["auto_execute"] = auto_execute
    write_settings(path, updates)


def _safe_receipt(path):
    return json.dumps({"settings_file": str(pathlib.Path(path))})


def main():
    parser = argparse.ArgumentParser(description="Write Spotify Ads API settings securely")
    subparsers = parser.add_subparsers(dest="command", required=True)

    direct = subparsers.add_parser("direct-token")
    direct.add_argument("--settings-file", required=True)
    direct.add_argument("--auto-execute", choices=("true", "false"))
    direct.add_argument("--access-token-stdin", action="store_true", required=True)

    oauth_result = subparsers.add_parser("oauth-result")
    oauth_result.add_argument("--settings-file", required=True)
    oauth_result.add_argument("--pending-token-file", required=True)

    account = subparsers.add_parser("update-account")
    account.add_argument("--settings-file", required=True)
    account.add_argument("--ad-account-id", required=True)

    args = parser.parse_args()
    try:
        if args.command == "direct-token":
            access_token = sys.stdin.read().strip()
            if not access_token:
                parser.error("an access token must be provided on stdin")
            write_direct_token_settings(args.settings_file, access_token, args.auto_execute)
        elif args.command == "oauth-result":
            finalize_pending_oauth_file(args.pending_token_file, args.settings_file)
        else:
            write_settings(args.settings_file, {"ad_account_id": args.ad_account_id})
    except (OSError, TypeError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"Could not write settings securely: {error}", file=sys.stderr)
        return 1

    print(_safe_receipt(args.settings_file))
    return 0


if __name__ == "__main__":
    sys.exit(main())
