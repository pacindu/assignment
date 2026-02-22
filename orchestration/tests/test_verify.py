"""
Unit tests for the Post-Deploy Verification Lambda.

HTTP calls and AWS boto3 calls are mocked using unittest.mock.
"""

import importlib.util
import json
import os
import sys
import urllib.error
import urllib.request
from unittest.mock import MagicMock, patch

import pytest

_LAMBDA_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "lambda"))

def _load_lambda(unique_name, rel_path):
    abs_path = os.path.join(_LAMBDA_ROOT, rel_path)
    if unique_name not in sys.modules:
        spec = importlib.util.spec_from_file_location(unique_name, abs_path)
        mod = importlib.util.module_from_spec(spec)
        sys.modules[unique_name] = mod
        spec.loader.exec_module(mod)
    return sys.modules[unique_name]

verify_handler = _load_lambda("verify_handler", "verify/handler.py")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _mock_http_response(status: int = 200, headers: dict = None):
    """Build a mock urllib response object."""
    if headers is None:
        headers = {
            "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "Content-Security-Policy": "default-src 'none'",
            "Content-Type": "application/json",
        }
    mock_resp = MagicMock()
    mock_resp.status = status
    mock_resp.headers = headers
    mock_resp.read.return_value = b'{"status":"healthy"}'
    mock_resp.__enter__ = lambda s: s
    mock_resp.__exit__ = MagicMock(return_value=False)
    return mock_resp


def _mock_logs_client(events=None):
    """Build a mock CloudWatch Logs client."""
    mock = MagicMock()
    mock.filter_log_events.return_value = {"events": events or []}
    return mock


# ---------------------------------------------------------------------------
# 1. Happy path
# ---------------------------------------------------------------------------

class TestVerifyPasses:

    def test_returns_passed_true_on_healthy_endpoint(self, valid_event, lambda_context):
        with (
            patch("verify_handler.urllib.request.urlopen", return_value=_mock_http_response()),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client()
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is True

    def test_all_checks_pass_with_healthy_endpoint(self, valid_event, lambda_context):
        with (
            patch("verify_handler.urllib.request.urlopen", return_value=_mock_http_response()),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client()
            result = verify_handler.handler(valid_event, lambda_context)

        checks = {c["check"]: c for c in result["checks"]}
        assert checks["http_health"]["passed"] is True
        assert checks["security_headers"]["passed"] is True
        assert checks["cloudwatch_errors"]["passed"] is True


# ---------------------------------------------------------------------------
# 2. HTTP health check failures
# ---------------------------------------------------------------------------

class TestHttpHealthCheck:

    def test_fails_on_non_200_response(self, valid_event, lambda_context):
        with (
            patch("verify_handler.urllib.request.urlopen",
                  return_value=_mock_http_response(status=503)),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client()
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["http_health"]["passed"] is False
        assert "503" in checks["http_health"]["detail"]

    def test_fails_on_connection_error(self, valid_event, lambda_context):
        with (
            patch(
                "verify_handler.urllib.request.urlopen",
                side_effect=urllib.error.URLError("Connection refused"),
            ),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client()
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["http_health"]["passed"] is False
        assert "Connection refused" in checks["http_health"]["detail"]

    def test_fails_on_timeout(self, valid_event, lambda_context):
        import socket
        with (
            patch(
                "verify_handler.urllib.request.urlopen",
                side_effect=urllib.error.URLError(socket.timeout("timed out")),
            ),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client()
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["http_health"]["passed"] is False


# ---------------------------------------------------------------------------
# 3. Security headers checks
# ---------------------------------------------------------------------------

class TestSecurityHeaders:

    def test_fails_when_hsts_header_missing(self, valid_event, lambda_context):
        headers_without_hsts = {
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "Content-Security-Policy": "default-src 'none'",
        }
        with (
            patch("verify_handler.urllib.request.urlopen",
                  return_value=_mock_http_response(headers=headers_without_hsts)),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client()
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["security_headers"]["passed"] is False
        assert "Strict-Transport-Security" in checks["security_headers"]["detail"]

    def test_fails_when_csp_header_missing(self, valid_event, lambda_context):
        headers_without_csp = {
            "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
        }
        with (
            patch("verify_handler.urllib.request.urlopen",
                  return_value=_mock_http_response(headers=headers_without_csp)),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client()
            result = verify_handler.handler(valid_event, lambda_context)

        checks = {c["check"]: c for c in result["checks"]}
        assert checks["security_headers"]["passed"] is False

    def test_fails_when_no_headers_returned(self, valid_event, lambda_context):
        with (
            patch(
                "verify_handler.urllib.request.urlopen",
                side_effect=urllib.error.URLError("Connection refused"),
            ),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client()
            result = verify_handler.handler(valid_event, lambda_context)

        checks = {c["check"]: c for c in result["checks"]}
        # When HTTP fails, security_headers check also fails (no headers to inspect)
        assert checks["security_headers"]["passed"] is False


# ---------------------------------------------------------------------------
# 4. CloudWatch Logs error check
# ---------------------------------------------------------------------------

class TestCloudWatchLogsCheck:

    def test_fails_when_error_events_found(self, valid_event, lambda_context):
        error_events = [
            {
                "timestamp": 1700000000000,
                "message": "ERROR: database connection refused",
                "logStreamName": "app/main/task-id-1",
            },
            {
                "timestamp": 1700000001000,
                "message": "ERROR: health check timeout",
                "logStreamName": "app/main/task-id-1",
            },
        ]
        with (
            patch("verify_handler.urllib.request.urlopen", return_value=_mock_http_response()),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client(events=error_events)
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["cloudwatch_errors"]["passed"] is False
        assert "2" in checks["cloudwatch_errors"]["detail"]

    def test_passes_when_no_error_events(self, valid_event, lambda_context):
        with (
            patch("verify_handler.urllib.request.urlopen", return_value=_mock_http_response()),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = _mock_logs_client(events=[])
            result = verify_handler.handler(valid_event, lambda_context)

        checks = {c["check"]: c for c in result["checks"]}
        assert checks["cloudwatch_errors"]["passed"] is True

    def test_passes_when_log_group_not_found(self, valid_event, lambda_context):
        from botocore.exceptions import ClientError
        error_response = {
            "Error": {"Code": "ResourceNotFoundException", "Message": "Log group not found"}
        }
        with (
            patch("verify_handler.urllib.request.urlopen", return_value=_mock_http_response()),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_logs = MagicMock()
            mock_logs.filter_log_events.side_effect = ClientError(
                error_response, "FilterLogEvents"
            )
            mock_boto3.client.return_value = mock_logs
            result = verify_handler.handler(valid_event, lambda_context)

        checks = {c["check"]: c for c in result["checks"]}
        # New log group with no traffic yet should not fail verification
        assert checks["cloudwatch_errors"]["passed"] is True
