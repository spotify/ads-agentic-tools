#!/usr/bin/env python3
# /// script
# requires-python = ">=3.8"
# ///
"""Spotify Ads API OAuth 2.0 Device Authorization Grant flow (RFC 8628).

Requests a device code, displays the verification URL and user code, and polls
the token endpoint until the user authorizes or the code expires. Designed for
headless and sandboxed environments where a loopback redirect is unavailable.

Usage:
    python3 device-flow.py --client-id ID --settings-file PATH
    uv run device-flow.py --client-id ID --settings-file PATH

Tokens are written directly to a mode-0600 settings file and are never emitted
to stdout. A non-sensitive settings receipt is written to stdout. Diagnostics
are written to stderr.
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from settings_file import create_pending_oauth_file, finalize_pending_oauth_file

DEVICE_AUTHORIZE_URL = "https://accounts.spotify.com/oauth2/device/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"
DEVICE_CODE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"


def _redact(text, sensitive_values):
    redacted = text
    for value in sensitive_values:
        if value:
            redacted = redacted.replace(value, "[REDACTED]")
    return redacted


def request_device_code(client_id, opener=urllib.request.urlopen):
    """POST to the device authorization endpoint to obtain a device code."""
    data = urllib.parse.urlencode({"client_id": client_id}).encode("ascii")
    request = urllib.request.Request(
        DEVICE_AUTHORIZE_URL,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with opener(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8")), None
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace") if error.fp else ""
        try:
            payload = json.loads(body)
            detail = payload.get("error_description", payload.get("error", ""))
        except (json.JSONDecodeError, AttributeError):
            detail = ""
        if not detail or not isinstance(detail, str):
            detail = f"HTTP {error.code}"
        return None, detail
    except Exception as error:
        return None, str(error)


def build_token_request(client_id, device_code):
    data = urllib.parse.urlencode({
        "grant_type": DEVICE_CODE_GRANT_TYPE,
        "device_code": device_code,
        "client_id": client_id,
    }).encode("ascii")
    return urllib.request.Request(
        TOKEN_URL,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )


def poll_for_token(client_id, device_code, interval, expires_in,
                   opener=urllib.request.urlopen, clock=time.monotonic,
                   sleep=time.sleep):
    """Poll the token endpoint until authorization completes or expires."""
    deadline = clock() + expires_in
    current_interval = interval

    while clock() < deadline:
        sleep(current_interval)

        request = build_token_request(client_id, device_code)
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

            if oauth_error == "authorization_pending":
                continue
            elif oauth_error == "slow_down":
                current_interval += 5
                continue
            elif oauth_error == "expired_token":
                return None, "Device code expired before authorization was completed. Run configure again."
            elif oauth_error == "access_denied":
                return None, "Authorization was denied by the user."
            else:
                detail = _redact(str(oauth_error or f"HTTP {error.code}"), (device_code,))
                return None, f"Token request failed: {detail}"
        except Exception as error:
            detail = _redact(str(error), (device_code,))
            return None, f"Token request failed: {detail}"

    return None, "Device code expired (polling timeout). Run configure again."


def main():
    parser = argparse.ArgumentParser(
        description="Spotify OAuth 2.0 Device Authorization Grant flow (RFC 8628)")
    parser.add_argument("--client-id", required=True,
                        help="Team-owned Spotify app client ID")
    parser.add_argument("--settings-file", required=True,
                        help="Active platform settings path")
    parser.add_argument("--auto-execute", choices=("true", "false"),
                        help="Confirmation preference to store")
    parser.add_argument("--timeout", type=int, help=argparse.SUPPRESS)
    args = parser.parse_args()

    print("Requesting device authorization code...", file=sys.stderr)
    device_response, error = request_device_code(args.client_id)
    if error:
        print(f"Device authorization request failed: {error}", file=sys.stderr)
        return 4

    device_code = device_response.get("device_code", "")
    user_code = device_response.get("user_code", "")
    verification_uri = device_response.get("verification_uri", "")
    verification_uri_complete = device_response.get("verification_uri_complete", "")
    expires_in = int(device_response.get("expires_in", 600))
    interval = int(device_response.get("interval", 5))

    if args.timeout:
        expires_in = min(expires_in, args.timeout)

    if not device_code or not user_code or not verification_uri:
        print("Device authorization response missing required fields.", file=sys.stderr)
        return 4

    print(f"\n  Verification URL: {verification_uri}", file=sys.stderr)
    print(f"  User code:        {user_code}\n", file=sys.stderr)
    if verification_uri_complete:
        print(f"  Or open directly: {verification_uri_complete}\n", file=sys.stderr)
    print(f"Waiting for authorization (expires in {expires_in}s)...", file=sys.stderr)

    tokens, error = poll_for_token(args.client_id, device_code, interval,
                                   expires_in)
    if error:
        print(_redact(error, (device_code,)), file=sys.stderr)
        return 1
    if not tokens or not isinstance(tokens.get("access_token"), str) or not tokens["access_token"]:
        print("Authorization succeeded but no access token was returned.",
              file=sys.stderr)
        return 2

    try:
        pending_token_file = create_pending_oauth_file(
            tokens, args.client_id, args.auto_execute,
            auth_flow="device_authorization")
    except (OSError, TypeError, ValueError, KeyError) as error:
        print(f"Could not create a private OAuth result file: {error}",
              file=sys.stderr)
        return 5

    try:
        finalize_pending_oauth_file(pending_token_file, args.settings_file)
    except (OSError, TypeError, ValueError, KeyError,
            json.JSONDecodeError) as error:
        print(f"Could not write OAuth settings without additional workspace permission: {error}",
              file=sys.stderr)
        print(json.dumps({
            "settings_file": args.settings_file,
            "pending_token_file": str(pending_token_file),
            "requires_settings_write": True,
        }))
        return 5

    print(json.dumps({
        "settings_file": args.settings_file,
        "auth_flow": "device_authorization",
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
