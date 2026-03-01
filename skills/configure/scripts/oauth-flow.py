#!/usr/bin/env python3
# /// script
# requires-python = ">=3.8"
# ///
"""Spotify Ads API OAuth 2.0 authorization flow.

Starts a local callback server, opens the browser to Spotify's authorization
page, catches the redirect, and exchanges the authorization code for tokens.

Usage:
    python3 oauth-flow.py --client-id ID --client-secret SECRET
    python3 oauth-flow.py --client-id ID --client-secret SECRET --redirect-uri http://127.0.0.1:8080/callback
    uv run oauth-flow.py --client-id ID --client-secret SECRET

Output (stdout):
    {"access_token": "...", "refresh_token": "...", "expires_in": 3600}

Diagnostics go to stderr. Exit codes:
    0  Success
    1  User denied authorization
    2  Token exchange failed
    3  Timeout waiting for callback (120s)
"""

import argparse
import base64
import json
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler

AUTHORIZE_URL = "https://accounts.spotify.com/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"
DEFAULT_REDIRECT_URI = "http://127.0.0.1:8080/callback"
TIMEOUT_SECONDS = 120

# Shared state between server and main thread
result = {"code": None, "error": None}
server_ready = threading.Event()
callback_received = threading.Event()


class CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        if "error" in params:
            result["error"] = params["error"][0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<html><body><h2>Authorization denied.</h2>"
                             b"<p>You can close this tab.</p></body></html>")
        elif "code" in params:
            result["code"] = params["code"][0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<html><body><h2>Authorization successful!</h2>"
                             b"<p>You can close this tab and return to Claude Code.</p></body></html>")
        else:
            self.send_response(400)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<html><body><h2>Unexpected request.</h2></body></html>")

        callback_received.set()

    def log_message(self, format, *args):
        # Suppress default request logging; use stderr for diagnostics
        pass


def run_server(port):
    server = HTTPServer(("127.0.0.1", port), CallbackHandler)
    server.timeout = TIMEOUT_SECONDS
    server_ready.set()
    server.handle_request()
    server.server_close()


def exchange_code(code, client_id, client_secret, redirect_uri):
    credentials = base64.b64encode(
        f"{client_id}:{client_secret}".encode()
    ).decode()

    data = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
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
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        print(f"Token exchange HTTP {e.code}: {body}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Token exchange error: {e}", file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Spotify OAuth 2.0 authorization flow"
    )
    parser.add_argument("--client-id", required=True, help="Spotify app client ID")
    parser.add_argument("--client-secret", required=True, help="Spotify app client secret")
    parser.add_argument(
        "--redirect-uri",
        default=DEFAULT_REDIRECT_URI,
        help=f"OAuth redirect URI (default: {DEFAULT_REDIRECT_URI})",
    )
    args = parser.parse_args()

    # Parse port from redirect URI
    parsed_uri = urllib.parse.urlparse(args.redirect_uri)
    port = parsed_uri.port or 8080

    # Start callback server in background thread
    server_thread = threading.Thread(target=run_server, args=(port,), daemon=True)
    server_thread.start()
    server_ready.wait(timeout=5)

    # Build authorization URL
    auth_params = urllib.parse.urlencode({
        "client_id": args.client_id,
        "response_type": "code",
        "redirect_uri": args.redirect_uri,
    })
    auth_url = f"{AUTHORIZE_URL}?{auth_params}"

    print(f"Opening browser for authorization...", file=sys.stderr)
    print(f"URL: {auth_url}", file=sys.stderr)
    webbrowser.open(auth_url)

    # Wait for callback
    print(f"Waiting for callback (timeout: {TIMEOUT_SECONDS}s)...", file=sys.stderr)
    callback_received.wait(timeout=TIMEOUT_SECONDS)

    if not callback_received.is_set():
        print("Timeout waiting for authorization callback.", file=sys.stderr)
        sys.exit(3)

    if result["error"]:
        print(f"Authorization denied: {result['error']}", file=sys.stderr)
        sys.exit(1)

    if not result["code"]:
        print("No authorization code received.", file=sys.stderr)
        sys.exit(2)

    # Exchange code for tokens
    print("Exchanging authorization code for tokens...", file=sys.stderr)
    tokens = exchange_code(
        result["code"], args.client_id, args.client_secret, args.redirect_uri
    )

    if not tokens or "access_token" not in tokens:
        print("Failed to exchange authorization code for tokens.", file=sys.stderr)
        sys.exit(2)

    # Output structured JSON to stdout
    output = {
        "access_token": tokens["access_token"],
        "refresh_token": tokens.get("refresh_token", ""),
        "expires_in": tokens.get("expires_in", 3600),
    }
    print(json.dumps(output))
    sys.exit(0)


if __name__ == "__main__":
    main()
