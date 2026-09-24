#!/usr/bin/env python3
"""Unit tests for the Device Authorization Grant (RFC 8628) OAuth helpers."""

import contextlib
import datetime
import importlib.util
import io
import json
import pathlib
import stat
import sys
import tempfile
import unittest
import urllib.error
import urllib.parse
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
device = load_module("device_flow", SCRIPTS / "device-flow.py")


class FakeResponse:
    def __init__(self, payload):
        self.payload = json.dumps(payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self):
        return self.payload


class DeviceCodeRequestTests(unittest.TestCase):
    def test_request_sends_client_id_only(self):
        captured = {}

        def capture_opener(request, **kwargs):
            captured["data"] = urllib.parse.parse_qs(request.data.decode())
            captured["url"] = request.full_url
            return FakeResponse({
                "device_code": "dev-code",
                "user_code": "ABCD-1234",
                "verification_uri": "https://accounts.spotify.com/device",
                "expires_in": 600,
                "interval": 5,
            })

        result, error = device.request_device_code("team-client", opener=capture_opener)
        self.assertIsNone(error)
        self.assertEqual(captured["data"]["client_id"], ["team-client"])
        self.assertEqual(captured["url"], device.DEVICE_AUTHORIZE_URL)
        self.assertEqual(result["user_code"], "ABCD-1234")

    def test_http_error_returns_detail(self):
        body = json.dumps({"error": "unauthorized_client"}).encode()

        def failing_opener(*args, **kwargs):
            raise urllib.error.HTTPError(device.DEVICE_AUTHORIZE_URL, 401, "bad", {}, io.BytesIO(body))

        result, error = device.request_device_code("bad-client", opener=failing_opener)
        self.assertIsNone(result)
        self.assertIn("unauthorized_client", error)

    def test_network_error_returns_message(self):
        def failing_opener(*args, **kwargs):
            raise OSError("Network unreachable")

        result, error = device.request_device_code("client", opener=failing_opener)
        self.assertIsNone(result)
        self.assertIn("Network unreachable", error)


class TokenRequestTests(unittest.TestCase):
    def test_token_request_uses_device_code_grant(self):
        request = device.build_token_request("team-client", "dev-code")
        body = urllib.parse.parse_qs(request.data.decode())
        self.assertEqual(body["grant_type"], [device.DEVICE_CODE_GRANT_TYPE])
        self.assertEqual(body["device_code"], ["dev-code"])
        self.assertEqual(body["client_id"], ["team-client"])
        self.assertIsNone(request.get_header("Authorization"))


class PollingTests(unittest.TestCase):
    def test_success_after_pending(self):
        call_count = [0]

        def mock_opener(request, **kwargs):
            call_count[0] += 1
            if call_count[0] < 3:
                body = json.dumps({"error": "authorization_pending"}).encode()
                raise urllib.error.HTTPError(device.TOKEN_URL, 400, "bad", {}, io.BytesIO(body))
            return FakeResponse({"access_token": "new-token", "expires_in": 3600})

        clock_time = [0.0]

        def fake_clock():
            return clock_time[0]

        def fake_sleep(seconds):
            clock_time[0] += seconds

        tokens, error = device.poll_for_token(
            "client", "dev-code", interval=1, expires_in=30,
            opener=mock_opener, clock=fake_clock, sleep=fake_sleep)
        self.assertIsNone(error)
        self.assertEqual(tokens["access_token"], "new-token")
        self.assertEqual(call_count[0], 3)

    def test_slow_down_increases_interval(self):
        intervals = []

        def mock_opener(request, **kwargs):
            body = json.dumps({"error": "slow_down"}).encode()
            raise urllib.error.HTTPError(device.TOKEN_URL, 400, "bad", {}, io.BytesIO(body))

        clock_time = [0.0]

        def fake_clock():
            return clock_time[0]

        def fake_sleep(seconds):
            intervals.append(seconds)
            clock_time[0] += seconds

        device.poll_for_token(
            "client", "dev-code", interval=5, expires_in=25,
            opener=mock_opener, clock=fake_clock, sleep=fake_sleep)
        self.assertEqual(intervals[0], 5)
        self.assertEqual(intervals[1], 10)

    def test_expired_token_stops_polling(self):
        def mock_opener(request, **kwargs):
            body = json.dumps({"error": "expired_token"}).encode()
            raise urllib.error.HTTPError(device.TOKEN_URL, 400, "bad", {}, io.BytesIO(body))

        tokens, error = device.poll_for_token(
            "client", "dev-code", interval=0, expires_in=600,
            opener=mock_opener, clock=lambda: 0, sleep=lambda s: None)
        self.assertIsNone(tokens)
        self.assertIn("expired", error)

    def test_access_denied_stops_polling(self):
        def mock_opener(request, **kwargs):
            body = json.dumps({"error": "access_denied"}).encode()
            raise urllib.error.HTTPError(device.TOKEN_URL, 400, "bad", {}, io.BytesIO(body))

        tokens, error = device.poll_for_token(
            "client", "dev-code", interval=0, expires_in=600,
            opener=mock_opener, clock=lambda: 0, sleep=lambda s: None)
        self.assertIsNone(tokens)
        self.assertIn("denied", error)

    def test_timeout_when_always_pending(self):
        def mock_opener(request, **kwargs):
            body = json.dumps({"error": "authorization_pending"}).encode()
            raise urllib.error.HTTPError(device.TOKEN_URL, 400, "bad", {}, io.BytesIO(body))

        clock_time = [0.0]

        def fake_clock():
            return clock_time[0]

        def fake_sleep(seconds):
            clock_time[0] += seconds

        tokens, error = device.poll_for_token(
            "client", "dev-code", interval=5, expires_in=12,
            opener=mock_opener, clock=fake_clock, sleep=fake_sleep)
        self.assertIsNone(tokens)
        self.assertIn("timeout", error.lower())

    def test_device_code_redacted_from_errors(self):
        device_code = "sensitive-device-code-value"

        def mock_opener(request, **kwargs):
            raise OSError(f"Connection to {device_code} failed")

        tokens, error = device.poll_for_token(
            "client", device_code, interval=0, expires_in=600,
            opener=mock_opener, clock=lambda: 0, sleep=lambda s: None)
        self.assertIsNone(tokens)
        self.assertNotIn(device_code, error)


class EndToEndTests(unittest.TestCase):
    def test_success_writes_tokens_without_emitting_them(self):
        device_response = {
            "device_code": "sensitive-device-code",
            "user_code": "ABCD-1234",
            "verification_uri": "https://accounts.spotify.com/device",
            "expires_in": 600,
            "interval": 5,
        }
        tokens = {
            "access_token": "access-sensitive-value",
            "refresh_token": "refresh-sensitive-value",
            "expires_in": 3600,
        }

        with tempfile.TemporaryDirectory() as directory:
            settings_path = pathlib.Path(directory) / "spotify-ads-api.local.md"
            stdout = io.StringIO()
            stderr = io.StringIO()
            argv = [
                "device-flow.py",
                "--client-id", "team-client",
                "--settings-file", str(settings_path),
            ]
            with mock.patch.object(device, "request_device_code", return_value=(device_response, None)), \
                    mock.patch.object(device, "poll_for_token", return_value=(tokens, None)), \
                    mock.patch.object(sys, "argv", argv), \
                    contextlib.redirect_stdout(stdout), \
                    contextlib.redirect_stderr(stderr):
                self.assertEqual(device.main(), 0)

            self.assertNotIn(tokens["access_token"], stdout.getvalue())
            self.assertNotIn(tokens["refresh_token"], stdout.getvalue())
            self.assertNotIn(tokens["access_token"], stderr.getvalue())
            self.assertNotIn(tokens["refresh_token"], stderr.getvalue())
            self.assertNotIn("sensitive-device-code", stdout.getvalue())

            values = settings.read_settings(settings_path)
            self.assertEqual(values["access_token"], tokens["access_token"])
            self.assertEqual(values["auth_flow"], "device_authorization")
            self.assertEqual(values["client_id"], "team-client")
            self.assertEqual(stat.S_IMODE(settings_path.stat().st_mode), 0o600)

    def test_receipt_contains_auth_flow(self):
        device_response = {
            "device_code": "dc",
            "user_code": "CODE",
            "verification_uri": "https://example.com/device",
            "expires_in": 60,
            "interval": 1,
        }
        tokens = {"access_token": "tok", "expires_in": 3600}

        with tempfile.TemporaryDirectory() as directory:
            settings_path = pathlib.Path(directory) / "settings.md"
            stdout = io.StringIO()
            argv = [
                "device-flow.py",
                "--client-id", "client",
                "--settings-file", str(settings_path),
            ]
            with mock.patch.object(device, "request_device_code", return_value=(device_response, None)), \
                    mock.patch.object(device, "poll_for_token", return_value=(tokens, None)), \
                    mock.patch.object(sys, "argv", argv), \
                    contextlib.redirect_stdout(stdout), \
                    contextlib.redirect_stderr(io.StringIO()):
                device.main()

            receipt = json.loads(stdout.getvalue())
            self.assertEqual(receipt["auth_flow"], "device_authorization")

    def test_device_code_not_leaked_on_failure(self):
        device_response = {
            "device_code": "sensitive-device-code",
            "user_code": "ABCD-1234",
            "verification_uri": "https://example.com/device",
            "expires_in": 60,
            "interval": 1,
        }

        with tempfile.TemporaryDirectory() as directory:
            settings_path = pathlib.Path(directory) / "settings.md"
            stdout = io.StringIO()
            stderr = io.StringIO()
            argv = [
                "device-flow.py",
                "--client-id", "client",
                "--settings-file", str(settings_path),
            ]
            with mock.patch.object(device, "request_device_code", return_value=(device_response, None)), \
                    mock.patch.object(device, "poll_for_token",
                                      return_value=(None, "sensitive-device-code leaked")), \
                    mock.patch.object(sys, "argv", argv), \
                    contextlib.redirect_stdout(stdout), \
                    contextlib.redirect_stderr(stderr):
                self.assertNotEqual(device.main(), 0)

            self.assertNotIn("sensitive-device-code", stderr.getvalue())


class SettingsAuthFlowTests(unittest.TestCase):
    def test_device_authorization_flows_through_pending_file(self):
        tokens = {"access_token": "token", "refresh_token": "refresh", "expires_in": 3600}
        pending = settings.create_pending_oauth_file(tokens, "client", auth_flow="device_authorization")
        self.addCleanup(lambda: pending.unlink() if pending.exists() else None)

        with tempfile.TemporaryDirectory() as directory:
            settings_path = pathlib.Path(directory) / "settings.md"
            now = datetime.datetime(2026, 9, 24, tzinfo=datetime.timezone.utc)
            settings.finalize_pending_oauth_file(pending, settings_path, now=now)
            values = settings.read_settings(settings_path)
            self.assertEqual(values["auth_flow"], "device_authorization")

    def test_default_auth_flow_is_pkce(self):
        tokens = {"access_token": "token", "refresh_token": "refresh", "expires_in": 3600}
        pending = settings.create_pending_oauth_file(tokens, "client")
        self.addCleanup(lambda: pending.unlink() if pending.exists() else None)

        with tempfile.TemporaryDirectory() as directory:
            settings_path = pathlib.Path(directory) / "settings.md"
            now = datetime.datetime(2026, 9, 24, tzinfo=datetime.timezone.utc)
            settings.finalize_pending_oauth_file(pending, settings_path, now=now)
            values = settings.read_settings(settings_path)
            self.assertEqual(values["auth_flow"], "authorization_code_pkce")


if __name__ == "__main__":
    unittest.main()
