#!/usr/bin/env python3
# /// script
# requires-python = ">=3.8"
# ///
"""Refresh a Spotify Authorization Code with PKCE access token.

Usage:
    python3 refresh-token.py --client-id ID --refresh-token TOKEN
    uv run refresh-token.py --client-id ID --refresh-token TOKEN

Structured token JSON is written to stdout. Diagnostics are written to stderr.
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

TOKEN_URL = "https://accounts.spotify.com/api/token"


def build_refresh_request(client_id, refresh_token):
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": client_id,
    }).encode("ascii")
    return urllib.request.Request(
        TOKEN_URL,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )


def _redact(text, sensitive_values):
    redacted = text
    for value in sensitive_values:
        if value:
            redacted = redacted.replace(value, "[REDACTED]")
    return redacted


def refresh(client_id, refresh_token, opener=urllib.request.urlopen):
    request = build_refresh_request(client_id, refresh_token)
    try:
        with opener(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8")), None
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace") if error.fp else ""
        try:
            payload = json.loads(body)
            oauth_error = payload.get("error", "")
        except (json.JSONDecodeError, AttributeError):
            oauth_error = ""
        if oauth_error == "invalid_grant":
            print("Refresh token is no longer valid (invalid_grant). Run configure to authorize again.", file=sys.stderr)
            return None, 1
        if isinstance(oauth_error, str) and oauth_error and len(oauth_error) <= 64 and all(
            character.isalnum() or character in "_-" for character in oauth_error
        ):
            detail = oauth_error
        else:
            detail = "OAuth request rejected"
        print(f"Token refresh failed (HTTP {error.code}): {detail}", file=sys.stderr)
        return None, 2
    except Exception as error:
        detail = _redact(str(error), (refresh_token,))
        print(f"Token refresh failed: {detail}", file=sys.stderr)
        return None, 2


def main():
    parser = argparse.ArgumentParser(description="Refresh a Spotify OAuth 2.0 PKCE access token")
    parser.add_argument("--client-id", required=True, help="Team-owned Spotify app client ID")
    parser.add_argument("--refresh-token", required=True, help="Refresh token from the PKCE authorization flow")
    args = parser.parse_args()

    tokens, error_code = refresh(args.client_id, args.refresh_token)
    if error_code is not None:
        return error_code
    if not tokens or "access_token" not in tokens:
        print("No access token in refresh response.", file=sys.stderr)
        return 2

    output = {"access_token": tokens["access_token"], "expires_in": tokens.get("expires_in", 3600)}
    if tokens.get("refresh_token"):
        output["refresh_token"] = tokens["refresh_token"]
    print(json.dumps(output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
