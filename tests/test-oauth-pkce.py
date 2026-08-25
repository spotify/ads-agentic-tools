#!/usr/bin/env python3
"""Unit tests for the standard-library PKCE OAuth helpers."""

import contextlib
import importlib.util
import io
import json
import pathlib
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from http.server import HTTPServer

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


oauth = load_module("oauth_flow", ROOT / "skills/configure/scripts/oauth-flow.py")
refresh = load_module("refresh_token", ROOT / "skills/configure/scripts/refresh-token.py")


class FakeResponse:
    def __init__(self, payload):
        self.payload = json.dumps(payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self):
        return self.payload


class PkceTests(unittest.TestCase):
    def test_rfc_7636_challenge_vector(self):
        verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        self.assertEqual(
            oauth.derive_code_challenge(verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        )

    def test_verifier_properties_and_uniqueness(self):
        verifiers = {oauth.generate_code_verifier() for _ in range(20)}
        self.assertEqual(len(verifiers), 20)
        for verifier in verifiers:
            self.assertTrue(43 <= len(verifier) <= 128)
            self.assertTrue(set(verifier) <= set(oauth.VERIFIER_ALPHABET))

    def test_authorization_url_contract(self):
        url = oauth.build_authorization_url("team-client", oauth.DEFAULT_REDIRECT_URI, "challenge", "state-value")
        parsed = urllib.parse.urlparse(url)
        query = urllib.parse.parse_qs(parsed.query)
        self.assertEqual(query["client_id"], ["team-client"])
        self.assertEqual(query["redirect_uri"], [oauth.DEFAULT_REDIRECT_URI])
        self.assertEqual(query["code_challenge_method"], ["S256"])
        self.assertEqual(query["code_challenge"], ["challenge"])
        self.assertEqual(query["state"], ["state-value"])
        self.assertNotIn("scope", query)

    def test_redirect_uri_must_match_registered_loopback_exactly(self):
        self.assertEqual(oauth.parse_redirect_uri(oauth.DEFAULT_REDIRECT_URI), (8080, "/callback"))
        for redirect_uri in (
            "http://localhost:8080/callback",
            "http://127.0.0.1:8080/callback/",
            "http://127.0.0.1:9090/callback",
        ):
            with self.subTest(redirect_uri=redirect_uri):
                with self.assertRaises(ValueError):
                    oauth.parse_redirect_uri(redirect_uri)

    def test_code_exchange_request_uses_pkce_body_only(self):
        request = oauth.build_token_request("code", "team-client", oauth.DEFAULT_REDIRECT_URI, "verifier")
        body = urllib.parse.parse_qs(request.data.decode())
        self.assertEqual(body["client_id"], ["team-client"])
        self.assertEqual(body["code_verifier"], ["verifier"])
        self.assertIsNone(request.get_header("Authorization"))
        self.assertNotIn("secret", request.data.decode().lower())

    def _callback_server(self, expected_state="expected"):
        result = {"code": None, "error": None}
        received = threading.Event()
        handler = oauth.make_callback_handler("/callback", expected_state, result, received)
        server = HTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1)
        self.addCleanup(server.shutdown)
        return server, result, received

    def test_correct_state_callback_succeeds(self):
        server, result, received = self._callback_server()
        urllib.request.urlopen(f"http://127.0.0.1:{server.server_port}/callback?code=ok&state=expected")
        self.assertTrue(received.wait(1))
        self.assertEqual(result["code"], "ok")
        self.assertIsNone(result["error"])

    def test_mismatched_and_missing_state_fail(self):
        for query in ("code=ok&state=wrong", "code=ok"):
            with self.subTest(query=query):
                server, result, received = self._callback_server()
                with self.assertRaises(urllib.error.HTTPError):
                    urllib.request.urlopen(f"http://127.0.0.1:{server.server_port}/callback?{query}")
                self.assertTrue(received.wait(1))
                self.assertEqual(result["error"], "state_mismatch")
                server.shutdown()

    def test_unrelated_path_does_not_finish_listener(self):
        server, result, received = self._callback_server()
        with self.assertRaises(urllib.error.HTTPError):
            urllib.request.urlopen(f"http://127.0.0.1:{server.server_port}/favicon.ico")
        self.assertFalse(received.is_set())
        urllib.request.urlopen(f"http://127.0.0.1:{server.server_port}/callback?code=ok&state=expected")
        self.assertTrue(received.wait(1))
        self.assertEqual(result["code"], "ok")

    def test_oauth_error_redacts_sensitive_values(self):
        verifier = "verifier-sensitive-value"
        code = "code-sensitive-value"
        body = json.dumps({"error": "invalid_grant", "error_description": f"{verifier} {code} access refresh"}).encode()

        def failing_opener(*args, **kwargs):
            raise urllib.error.HTTPError(oauth.TOKEN_URL, 400, "bad", {}, io.BytesIO(body))

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertIsNone(oauth.exchange_code(code, "client", oauth.DEFAULT_REDIRECT_URI, verifier, failing_opener))
        output = stderr.getvalue()
        self.assertNotIn(verifier, output)
        self.assertNotIn(code, output)
        self.assertNotIn("access refresh", output)


class RefreshTests(unittest.TestCase):
    def test_refresh_request_uses_client_id_without_basic_auth(self):
        request = refresh.build_refresh_request("team-client", "refresh-value")
        body = urllib.parse.parse_qs(request.data.decode())
        self.assertEqual(body["client_id"], ["team-client"])
        self.assertEqual(body["refresh_token"], ["refresh-value"])
        self.assertIsNone(request.get_header("Authorization"))

    def test_refresh_rotation_and_omission(self):
        for payload, expected in (
            ({"access_token": "new", "expires_in": 3600}, None),
            ({"access_token": "new", "expires_in": 3600, "refresh_token": "rotated"}, "rotated"),
        ):
            with self.subTest(payload=payload):
                tokens, error = refresh.refresh("client", "existing", lambda *args, **kwargs: FakeResponse(payload))
                self.assertIsNone(error)
                self.assertEqual(tokens.get("refresh_token"), expected)

    def test_invalid_grant_is_distinct_and_redacted(self):
        token = "refresh-sensitive-value"
        body = json.dumps({"error": "invalid_grant", "error_description": token}).encode()

        def failing_opener(*args, **kwargs):
            raise urllib.error.HTTPError(refresh.TOKEN_URL, 400, "bad", {}, io.BytesIO(body))

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            tokens, error = refresh.refresh("client", token, failing_opener)
        self.assertIsNone(tokens)
        self.assertEqual(error, 1)
        self.assertNotIn(token, stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
