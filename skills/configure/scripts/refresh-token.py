#!/usr/bin/env python3
# /// script
# requires-python = ">=3.8"
# ///
"""Spotify Ads API token refresh.

Exchanges a refresh token for a new access token.

Usage:
    python3 refresh-token.py --client-id ID --client-secret SECRET --refresh-token TOKEN
    uv run refresh-token.py --client-id ID --client-secret SECRET --refresh-token TOKEN

Output (stdout):
    {"access_token": "...", "expires_in": 3600}

Diagnostics go to stderr. Exit codes:
    0  Success
    1  Invalid refresh token (401/400 from Spotify)
    2  Network or unexpected error
"""

import argparse
import base64
import json
import sys
import urllib.parse
import urllib.request

TOKEN_URL = "https://accounts.spotify.com/api/token"


def refresh(client_id, client_secret, refresh_token):
    credentials = base64.b64encode(
        f"{client_id}:{client_secret}".encode()
    ).decode()

    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
    }).encode()

    req = urllib.request.Request(
        TOKEN_URL,
        data=data,
        headers={
            "Authorization": f"Basic {credentials}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode()), None
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        if e.code in (400, 401):
            print(f"Invalid refresh token (HTTP {e.code}): {body}", file=sys.stderr)
            return None, 1
        print(f"Token refresh HTTP {e.code}: {body}", file=sys.stderr)
        return None, 2
    except Exception as e:
        print(f"Token refresh error: {e}", file=sys.stderr)
        return None, 2


def main():
    parser = argparse.ArgumentParser(
        description="Refresh a Spotify OAuth 2.0 access token"
    )
    parser.add_argument("--client-id", required=True, help="Spotify app client ID")
    parser.add_argument("--client-secret", required=True, help="Spotify app client secret")
    parser.add_argument("--refresh-token", required=True, help="Refresh token from initial OAuth flow")
    args = parser.parse_args()

    tokens, error_code = refresh(args.client_id, args.client_secret, args.refresh_token)

    if error_code is not None:
        sys.exit(error_code)

    if not tokens or "access_token" not in tokens:
        print("No access token in response.", file=sys.stderr)
        sys.exit(2)

    output = {
        "access_token": tokens["access_token"],
        "expires_in": tokens.get("expires_in", 3600),
    }
    print(json.dumps(output))
    sys.exit(0)


if __name__ == "__main__":
    main()
