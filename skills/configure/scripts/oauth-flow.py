#!/usr/bin/env python3
# /// script
# requires-python = ">=3.8"
# ///
"""Spotify Ads API OAuth 2.0 Authorization Code with PKCE flow.

Starts a loopback callback server, opens Spotify authorization, validates the
callback, and exchanges the code without a client secret.

Usage:
    python3 oauth-flow.py --client-id ID
    uv run oauth-flow.py --client-id ID

Structured token JSON is written to stdout. Diagnostics are written to stderr.
"""

import argparse
import binascii
import hashlib
import hmac
import json
import secrets
import string
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

AUTHORIZE_URL = "https://accounts.spotify.com/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"
DEFAULT_REDIRECT_URI = "http://127.0.0.1:8080/callback"
TIMEOUT_SECONDS = 120
VERIFIER_ALPHABET = string.ascii_letters + string.digits + "-._~"


def generate_code_verifier(length=64):
    """Return an RFC 7636 verifier using a cryptographically secure source."""
    if not 43 <= length <= 128:
        raise ValueError("PKCE verifier length must be between 43 and 128")
    return "".join(secrets.choice(VERIFIER_ALPHABET) for _ in range(length))


def derive_code_challenge(verifier):
    """Return BASE64URL(SHA256(verifier)) without padding."""
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return binascii.b2a_base64(digest, newline=False).decode("ascii").replace("+", "-").replace("/", "_").rstrip("=")


def generate_state():
    """Return a high-entropy OAuth state value."""
    return secrets.token_urlsafe(32)


def build_authorization_url(client_id, redirect_uri, challenge, state):
    params = urllib.parse.urlencode({
        "client_id": client_id,
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "code_challenge_method": "S256",
        "code_challenge": challenge,
        "state": state,
    })
    return f"{AUTHORIZE_URL}?{params}"


def build_token_request(code, client_id, redirect_uri, verifier):
    data = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "client_id": client_id,
        "code_verifier": verifier,
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


def _oauth_error(error, sensitive_values):
    body = error.read().decode("utf-8", errors="replace") if error.fp else ""
    try:
        payload = json.loads(body)
        error_code = payload.get("error", "")
        if isinstance(error_code, str) and error_code and len(error_code) <= 64 and all(
            character.isalnum() or character in "_-" for character in error_code
        ):
            detail = error_code
        else:
            detail = "OAuth request rejected"
    except (json.JSONDecodeError, AttributeError):
        detail = "OAuth request rejected"
    return _redact(str(detail), sensitive_values)


def exchange_code(code, client_id, redirect_uri, verifier, opener=urllib.request.urlopen):
    request = build_token_request(code, client_id, redirect_uri, verifier)
    try:
        with opener(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = _oauth_error(error, (code, verifier))
        print(f"Token exchange failed (HTTP {error.code}): {detail}", file=sys.stderr)
    except Exception as error:
        detail = _redact(str(error), (code, verifier))
        print(f"Token exchange failed: {detail}", file=sys.stderr)
    return None


def make_callback_handler(expected_path, expected_state, callback_result, callback_received):
    class CallbackHandler(BaseHTTPRequestHandler):
        def _reply(self, status, heading, message):
            body = (f"<html><body><h2>{heading}</h2><p>{message}</p></body></html>").encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path != expected_path:
                self._reply(404, "Not found", "Return to the authorization tab to continue.")
                return

            if callback_received.is_set():
                self._reply(409, "Authorization already handled", "You can close this tab.")
                return

            params = urllib.parse.parse_qs(parsed.query)
            supplied_state = params.get("state", [""])[0]
            if not supplied_state or not hmac.compare_digest(supplied_state, expected_state):
                callback_result["error"] = "state_mismatch"
                self._reply(400, "Authorization rejected", "The OAuth state did not match. Return to the CLI and try again.")
                callback_received.set()
                return

            if "error" in params:
                callback_result["error"] = params["error"][0]
                self._reply(200, "Authorization denied", "You can close this tab and return to the CLI.")
            elif "code" in params:
                callback_result["code"] = params["code"][0]
                self._reply(200, "Authorization successful!", "You can close this tab and return to the CLI.")
            else:
                callback_result["error"] = "missing_code"
                self._reply(400, "Authorization failed", "The callback did not contain an authorization code.")
            callback_received.set()

        def log_message(self, format, *args):
            pass

    return CallbackHandler


def parse_redirect_uri(redirect_uri):
    if redirect_uri != DEFAULT_REDIRECT_URI:
        raise ValueError(f"redirect URI must be exactly {DEFAULT_REDIRECT_URI}")
    parsed = urllib.parse.urlparse(redirect_uri)
    if parsed.scheme != "http" or parsed.hostname != "127.0.0.1" or not parsed.path:
        raise ValueError("Redirect URI must use http://127.0.0.1 with a callback path")
    return parsed.port or 80, parsed.path


def wait_for_callback(server, callback_received, timeout_seconds):
    deadline = time.monotonic() + timeout_seconds
    while not callback_received.is_set():
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        server.timeout = min(1.0, remaining)
        server.handle_request()
    return True


def main():
    parser = argparse.ArgumentParser(description="Spotify OAuth 2.0 Authorization Code with PKCE flow")
    parser.add_argument("--client-id", required=True, help="Team-owned Spotify app client ID")
    parser.add_argument("--redirect-uri", default=DEFAULT_REDIRECT_URI, help=f"OAuth redirect URI (default: {DEFAULT_REDIRECT_URI})")
    parser.add_argument("--timeout", type=int, default=TIMEOUT_SECONDS, help=argparse.SUPPRESS)
    args = parser.parse_args()

    try:
        port, callback_path = parse_redirect_uri(args.redirect_uri)
    except ValueError as error:
        print(f"Invalid redirect URI: {error}", file=sys.stderr)
        return 4

    verifier = generate_code_verifier()
    challenge = derive_code_challenge(verifier)
    state = generate_state()
    callback_result = {"code": None, "error": None}
    callback_received = threading.Event()
    handler = make_callback_handler(callback_path, state, callback_result, callback_received)

    try:
        server = HTTPServer(("127.0.0.1", port), handler)
    except OSError as error:
        print(f"Could not start OAuth callback server on 127.0.0.1:{port}: {error}", file=sys.stderr)
        print("Close the process using that port, then run configure again.", file=sys.stderr)
        return 4

    auth_url = build_authorization_url(args.client_id, args.redirect_uri, challenge, state)
    print(f"Authorization URL: {auth_url}", file=sys.stderr)
    try:
        opened = webbrowser.open(auth_url)
    except Exception as error:
        opened = False
        print(f"Could not open a browser automatically: {error}", file=sys.stderr)
    if not opened:
        print("Open the authorization URL above in a browser; the callback listener is still waiting.", file=sys.stderr)

    print(f"Waiting for callback (timeout: {args.timeout}s)...", file=sys.stderr)
    try:
        received = wait_for_callback(server, callback_received, args.timeout)
    finally:
        server.server_close()

    if not received:
        print("Timeout waiting for authorization callback. Run configure again and use the newly printed URL.", file=sys.stderr)
        return 3
    if callback_result["error"]:
        if callback_result["error"] == "state_mismatch":
            print("Authorization callback state mismatch. No token request was made; run configure again.", file=sys.stderr)
        else:
            print(f"Authorization failed: {callback_result['error']}", file=sys.stderr)
        return 1
    if not callback_result["code"]:
        print("No authorization code received.", file=sys.stderr)
        return 2

    print("Exchanging authorization code for tokens...", file=sys.stderr)
    tokens = exchange_code(callback_result["code"], args.client_id, args.redirect_uri, verifier)
    if not tokens or "access_token" not in tokens:
        print("Failed to exchange the authorization code for tokens.", file=sys.stderr)
        return 2

    print(json.dumps({
        "access_token": tokens["access_token"],
        "refresh_token": tokens.get("refresh_token", ""),
        "expires_in": tokens.get("expires_in", 3600),
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
