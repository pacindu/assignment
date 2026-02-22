"""
Post-Deploy Verification Lambda — NTT GCC Self-Healing Deployment Workflow

Checks performed:
  1. HTTP health check — GET /health returns HTTP 200
  2. Security headers — GCC-required headers are present in the response
  3. CloudWatch Logs — no ERROR-level messages in the last N minutes

Returns:
  {
    "passed": bool,
    "checks": [{ "check": str, "passed": bool, "detail": str, ... }],
  }
"""

import json
import logging
import time
import urllib.error
import urllib.request

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Security headers required by GCC baseline
REQUIRED_SECURITY_HEADERS = [
    "Strict-Transport-Security",
    "X-Content-Type-Options",
    "X-Frame-Options",
    "Content-Security-Policy",
]

DEFAULT_CHECK_WINDOW_MINUTES = 5
HTTP_TIMEOUT_SECONDS = 15


# ---------------------------------------------------------------------------
# Check helpers
# ---------------------------------------------------------------------------

def check_http_health(endpoint_url: str) -> tuple[dict, dict]:
    """
    Perform an HTTP GET to /health.

    Returns a tuple (http_result, headers_result) so we can re-use
    the response headers for the security-headers check without a second request.
    """
    health_url = endpoint_url.rstrip("/") + "/health"
    logger.info("HTTP health check: GET %s", health_url)

    try:
        req = urllib.request.Request(
            health_url,
            headers={"User-Agent": "NTT-GCC-Verify/1.0"},
        )
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_SECONDS) as resp:
            status = resp.status
            response_headers = dict(resp.headers)

        if status == 200:
            http_result = {
                "check": "http_health",
                "passed": True,
                "detail": f"GET {health_url} → HTTP {status}",
            }
        else:
            http_result = {
                "check": "http_health",
                "passed": False,
                "detail": f"GET {health_url} → unexpected HTTP {status} (expected 200)",
            }
        return http_result, response_headers

    except urllib.error.URLError as exc:
        http_result = {
            "check": "http_health",
            "passed": False,
            "detail": f"GET {health_url} failed: {exc.reason}",
        }
        return http_result, {}
    except Exception as exc:  # noqa: BLE001
        http_result = {
            "check": "http_health",
            "passed": False,
            "detail": f"GET {health_url} raised an unexpected error: {exc}",
        }
        return http_result, {}


def check_security_headers(response_headers: dict) -> dict:
    """Verify that required GCC security headers are present."""
    if not response_headers:
        return {
            "check": "security_headers",
            "passed": False,
            "detail": "No response headers available (HTTP check failed)",
        }

    lower_headers = {k.lower() for k in response_headers}
    missing = [h for h in REQUIRED_SECURITY_HEADERS if h.lower() not in lower_headers]

    if missing:
        return {
            "check": "security_headers",
            "passed": False,
            "detail": f"Missing GCC-required security headers: {missing}",
        }
    return {
        "check": "security_headers",
        "passed": True,
        "detail": f"All required security headers present: {REQUIRED_SECURITY_HEADERS}",
    }


def check_cloudwatch_errors(
    log_group_name: str,
    region: str,
    check_window_minutes: int = DEFAULT_CHECK_WINDOW_MINUTES,
) -> dict:
    """Scan CloudWatch Logs for ERROR-level events in the recent window."""
    logger.info(
        "CloudWatch Logs check: group='%s' window=%dm",
        log_group_name, check_window_minutes,
    )
    end_ms = int(time.time() * 1000)
    start_ms = end_ms - (check_window_minutes * 60 * 1000)

    try:
        logs = boto3.client("logs", region_name=region)
        response = logs.filter_log_events(
            logGroupName=log_group_name,
            startTime=start_ms,
            endTime=end_ms,
            filterPattern="ERROR",
            limit=10,
        )
        error_events = response.get("events", [])

        if error_events:
            samples = [e["message"][:200] for e in error_events[:3]]
            return {
                "check": "cloudwatch_errors",
                "passed": False,
                "detail": (
                    f"Found {len(error_events)} ERROR event(s) in log group "
                    f"'{log_group_name}' over the last {check_window_minutes} minutes"
                ),
                "samples": samples,
            }
        return {
            "check": "cloudwatch_errors",
            "passed": True,
            "detail": (
                f"No ERROR events in log group '{log_group_name}' "
                f"over the last {check_window_minutes} minutes"
            ),
        }

    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        if code == "ResourceNotFoundException":
            # Log group may not have received traffic yet — treat as passing
            return {
                "check": "cloudwatch_errors",
                "passed": True,
                "detail": (
                    f"Log group '{log_group_name}' not found or has no events yet "
                    "(treated as pass for initial deployments)"
                ),
            }
        return {
            "check": "cloudwatch_errors",
            "passed": False,
            "detail": f"CloudWatch FilterLogEvents failed ({code}): {exc}",
        }


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------

def handler(event: dict, context) -> dict:
    logger.info(
        "Post-deploy verification started. environment=%s endpoint=%s",
        event.get("environment"),
        event.get("endpoint_url"),
    )

    endpoint_url = event["endpoint_url"]
    log_group_name = event["log_group_name"]
    region = event.get("region", "ap-southeast-1")
    check_window = event.get("check_window_minutes", DEFAULT_CHECK_WINDOW_MINUTES)

    checks = []

    # 1. HTTP health check (also retrieves headers for check 2)
    http_result, response_headers = check_http_health(endpoint_url)
    checks.append(http_result)

    # 2. Security headers
    checks.append(check_security_headers(response_headers))

    # 3. CloudWatch Logs error scan
    checks.append(
        check_cloudwatch_errors(log_group_name, region, check_window)
    )

    passed = all(c["passed"] for c in checks)
    output = {"passed": passed, "checks": checks}

    if passed:
        logger.info("Verification PASSED. All %d checks succeeded.", len(checks))
    else:
        failed = [c["check"] for c in checks if not c["passed"]]
        logger.warning("Verification FAILED. Failed checks: %s", failed)

    logger.info("Verification result: %s", json.dumps(output))
    return output
