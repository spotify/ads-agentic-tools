#!/usr/bin/env python3
"""Unit tests for the standard-library PKCE OAuth helpers."""

import contextlib
import datetime
import importlib.util
import io
import json
import pathlib
import stat
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from http.server import HTTPServer
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "skills/configure/scripts"
sys_path_entry = str(SCRIPTS)
if sys_path_entry not in sys.path:
    sys.path.insert(0, sys_path_entry)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


settings = load_module("settings_file", SCRIPTS / "settings_file.py")
oauth = load_module("oauth_flow", SCRIPTS / "oauth-flow.py")
refresh = load_module("refresh_token", SCRIPTS / "refresh-token.py")


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

    def test_success_writes_tokens_without_emitting_them(self):
        captured = {}

        class FakeServer:
            def __init__(self, *args, **kwargs):
                pass

            def server_close(self):
                pass

        def fake_handler(path, state, result, received):
            captured["result"] = result
            return object

        def fake_wait(server, received, timeout):
            captured["result"]["code"] = "authorization-code"
            received.set()
            return True

        with tempfile.TemporaryDirectory() as directory:
            settings_path = pathlib.Path(directory) / "spotify-ads-api.local.md"
            stdout = io.StringIO()
            stderr = io.StringIO()
            argv = [
                "oauth-flow.py",
                "--client-id",
                "team-client",
                "--settings-file",
                str(settings_path),
            ]
            tokens = {
                "access_token": "access-sensitive-value",
                "refresh_token": "refresh-sensitive-value",
                "expires_in": 3600,
            }
            with mock.patch.object(oauth, "HTTPServer", FakeServer), \
                    mock.patch.object(oauth, "make_callback_handler", fake_handler), \
                    mock.patch.object(oauth, "wait_for_callback", fake_wait), \
                    mock.patch.object(oauth, "exchange_code", return_value=tokens), \
                    mock.patch.object(oauth.webbrowser, "open", return_value=False), \
                    mock.patch.object(sys, "argv", argv), \
                    contextlib.redirect_stdout(stdout), \
                    contextlib.redirect_stderr(stderr):
                self.assertEqual(oauth.main(), 0)

            self.assertNotIn(tokens["access_token"], stdout.getvalue())
            self.assertNotIn(tokens["refresh_token"], stdout.getvalue())
            self.assertNotIn(tokens["access_token"], stderr.getvalue())
            self.assertNotIn(tokens["refresh_token"], stderr.getvalue())
            self.assertEqual(settings.read_settings(settings_path)["access_token"], tokens["access_token"])
            self.assertEqual(stat.S_IMODE(settings_path.stat().st_mode), 0o600)


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


class SettingsTests(unittest.TestCase):
    def test_oauth_settings_replace_insecure_file_with_mode_0600(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "spotify-ads-api.local.md"
            path.write_text(
                '---\nad_account_id: "existing-account"\nauto_execute: true\n---\n',
                encoding="utf-8",
            )
            path.chmod(0o644)
            now = datetime.datetime(2026, 8, 25, tzinfo=datetime.timezone.utc)
            settings.write_oauth_settings(
                path,
                {"access_token": 'access\\sensitive"value', "refresh_token": "refresh-sensitive", "expires_in": 3600},
                "team-client",
                now=now,
            )

            values = settings.read_settings(path)
            self.assertEqual(values["access_token"], 'access\\sensitive"value')
            self.assertEqual(values["refresh_token"], "refresh-sensitive")
            self.assertEqual(values["token_expires_at"], "2026-08-25T01:00:00Z")
            self.assertEqual(values["client_id"], "team-client")
            self.assertEqual(values["auth_flow"], "authorization_code_pkce")
            self.assertEqual(values["ad_account_id"], "existing-account")
            self.assertEqual(values["auto_execute"], "true")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_pending_oauth_file_is_private_and_deleted_after_finalize(self):
        pending = settings.create_pending_oauth_file(
            {"access_token": "access-sensitive", "refresh_token": "refresh-sensitive", "expires_in": 3600},
            "team-client",
            "false",
        )
        self.addCleanup(lambda: pending.unlink() if pending.exists() else None)
        self.assertEqual(stat.S_IMODE(pending.stat().st_mode), 0o600)

        with tempfile.TemporaryDirectory() as directory:
            settings_path = pathlib.Path(directory) / "spotify-ads-api.local.md"
            now = datetime.datetime(2026, 8, 25, tzinfo=datetime.timezone.utc)
            settings.finalize_pending_oauth_file(pending, settings_path, now=now)
            self.assertFalse(pending.exists())
            values = settings.read_settings(settings_path)
            self.assertEqual(values["access_token"], "access-sensitive")
            self.assertEqual(values["auth_flow"], "authorization_code_pkce")

    def test_failed_finalize_retains_private_pending_file(self):
        pending = settings.create_pending_oauth_file(
            {"access_token": "access-sensitive", "refresh_token": "refresh-sensitive", "expires_in": 3600},
            "team-client",
        )
        self.addCleanup(lambda: pending.unlink() if pending.exists() else None)
        with mock.patch.object(settings, "write_oauth_settings", side_effect=PermissionError("managed write denied")):
            with self.assertRaises(PermissionError):
                settings.finalize_pending_oauth_file(pending, "/managed/settings.md")
        self.assertTrue(pending.exists())
        self.assertEqual(stat.S_IMODE(pending.stat().st_mode), 0o600)

    def test_finalize_rejects_insecure_pending_file(self):
        pending = settings.create_pending_oauth_file(
            {"access_token": "access-sensitive", "refresh_token": "refresh-sensitive"},
            "team-client",
        )
        self.addCleanup(lambda: pending.unlink() if pending.exists() else None)
        pending.chmod(0o644)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "mode-0600"):
                settings.finalize_pending_oauth_file(pending, pathlib.Path(directory) / "settings.md")

    def test_safe_receipt_contains_no_tokens(self):
        receipt = settings._safe_receipt(".codex/spotify-ads-api.local.md")
        self.assertNotIn("access-sensitive", receipt)
        self.assertNotIn("refresh-sensitive", receipt)
        self.assertEqual(json.loads(receipt)["settings_file"], ".codex/spotify-ads-api.local.md")


if __name__ == "__main__":
    unittest.main()
