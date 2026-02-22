"""
Negative Test Suite — NTT GCC Self-Healing Deployment Workflow

These tests simulate failure conditions that would trigger the automated
rollback path in the Step Functions state machine. They demonstrate:

  - Pre-flight checks blocking deployment (wrong region, missing tags)
  - Post-deploy verification failures that would trigger rollback
  - Rollback handler correctly reverting to the previous task definition
  - Rollback handler raising when no previous task definition is available

All AWS calls are mocked — no real AWS credentials required.
"""

import importlib.util
import os
import sys
import urllib.error
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

# Each handler gets its own unique sys.modules name to avoid cache collisions
preflight_handler = _load_lambda("preflight_handler", "preflight/handler.py")
verify_handler    = _load_lambda("verify_handler",    "verify/handler.py")
rollback_handler  = _load_lambda("rollback_handler",  "rollback/handler.py")


# ---------------------------------------------------------------------------
# Negative tests — Pre-flight blocks deployment
# ---------------------------------------------------------------------------

class TestPreflightBlocksDeployment:
    """Verify that pre-flight failures prevent deployment from proceeding."""

    def test_wrong_region_blocks_deployment(self, valid_event, lambda_context):
        """
        Scenario: Operator accidentally sets region to us-east-1.
        Expected: Pre-flight returns passed=False; deployment never starts.
        """
        event = {**valid_event, "region": "us-east-1"}
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(os.environ, {"EXPECTED_ACCOUNT_ID": ""}, clear=False),
        ):
            mock_ecs = MagicMock()
            mock_ecs.describe_clusters.return_value = {
                "clusters": [{"clusterName": "test", "tags": [
                    {"key": "Owner", "value": "NTT"},
                    {"key": "DataClassification", "value": "Internal"},
                    {"key": "CostCenter", "value": "NTT"},
                ]}],
                "failures": [],
            }
            mock_boto3.client.side_effect = lambda svc, **kw: mock_ecs
            result = preflight_handler.handler(event, lambda_context)

        assert result["passed"] is False, (
            "Wrong region should cause pre-flight to fail, blocking deployment"
        )
        region_check = next(
            c for c in result["checks"] if c["check"] == "region_constraint"
        )
        assert region_check["passed"] is False
        assert "us-east-1" in region_check["detail"]

    def test_missing_mandatory_tags_blocks_deployment(self, valid_event, lambda_context):
        """
        Scenario: ECS cluster exists but is missing the DataClassification tag.
        Expected: Pre-flight fails on cluster_tags check.
        """
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(os.environ, {"EXPECTED_ACCOUNT_ID": ""}, clear=False),
        ):
            mock_ecs = MagicMock()
            mock_ecs.describe_clusters.return_value = {
                "clusters": [{
                    "clusterName": valid_event["cluster_name"],
                    "tags": [
                        # DataClassification intentionally missing
                        {"key": "Owner", "value": "NTT"},
                        {"key": "CostCenter", "value": "NTT"},
                    ],
                }],
                "failures": [],
            }
            mock_boto3.client.side_effect = lambda svc, **kw: mock_ecs
            result = preflight_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False, (
            "Missing mandatory tags should cause pre-flight to fail"
        )
        tag_check = next(c for c in result["checks"] if c["check"] == "cluster_tags")
        assert tag_check["passed"] is False
        assert "DataClassification" in tag_check["detail"]

    def test_missing_required_fields_blocks_deployment(self, lambda_context):
        """
        Scenario: Execution started without all required input fields.
        Expected: Pre-flight fails immediately on required_fields check.
        """
        incomplete_event = {
            "environment": "Production",
            "region": "ap-southeast-1",
            "image_tag": "sha-abc123",
            # Missing: image_uri, endpoint_url, cluster_name, service_name, etc.
        }
        with patch("preflight_handler.boto3"):
            result = preflight_handler.handler(incomplete_event, lambda_context)

        assert result["passed"] is False
        assert result["checks"][0]["check"] == "required_fields"
        assert result["checks"][0]["passed"] is False
        # Short-circuit: no cluster_tags check should have run
        assert not any(c["check"] == "cluster_tags" for c in result["checks"])


# ---------------------------------------------------------------------------
# Negative tests — Verification failures that route to Rollback state
# ---------------------------------------------------------------------------

class TestVerificationFailuresTriggersRollback:
    """
    Simulate conditions where post-deploy verification returns passed=False.
    In the state machine VerificationCheck routes directly to the Rollback state.
    """

    def _mock_http(self, status=200, headers=None):
        if headers is None:
            headers = {
                "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
                "X-Content-Type-Options": "nosniff",
                "X-Frame-Options": "DENY",
                "Content-Security-Policy": "default-src 'none'",
            }
        mock_resp = MagicMock()
        mock_resp.status = status
        mock_resp.headers = headers
        mock_resp.read.return_value = b'{"status":"ok"}'
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        return mock_resp

    def test_unhealthy_endpoint_fails_verification(self, valid_event, lambda_context):
        """
        Scenario: New ECS task started but the app returns HTTP 503.
        Expected: verification.passed=False → VerificationCheck routes to Rollback.
        """
        with (
            patch("verify_handler.urllib.request.urlopen",
                  return_value=self._mock_http(status=503)),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = MagicMock(
                filter_log_events=MagicMock(return_value={"events": []})
            )
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False, (
            "HTTP 503 should cause verification to fail, triggering rollback"
        )
        http_check = next(c for c in result["checks"] if c["check"] == "http_health")
        assert http_check["passed"] is False

    def test_error_logs_fail_verification(self, valid_event, lambda_context):
        """
        Scenario: App returns HTTP 200 but ERROR entries appear in CloudWatch.
        Expected: verification.passed=False → VerificationCheck routes to Rollback.
        """
        error_events = [
            {"timestamp": 1700000000000, "message": "ERROR: NullPointerException at line 42"},
            {"timestamp": 1700000001000, "message": "ERROR: database pool exhausted"},
        ]
        with (
            patch("verify_handler.urllib.request.urlopen",
                  return_value=self._mock_http(status=200)),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = MagicMock(
                filter_log_events=MagicMock(return_value={"events": error_events})
            )
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False, (
            "ERROR log events should cause verification to fail, triggering rollback"
        )
        log_check = next(
            c for c in result["checks"] if c["check"] == "cloudwatch_errors"
        )
        assert log_check["passed"] is False
        assert "2" in log_check["detail"]

    def test_connection_refused_fails_verification(self, valid_event, lambda_context):
        """
        Scenario: New ECS tasks are starting but haven't bound the port yet.
        Expected: URLError causes http_health check to fail → Rollback triggered.
        """
        with (
            patch("verify_handler.urllib.request.urlopen",
                  side_effect=urllib.error.URLError("Connection refused")),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = MagicMock(
                filter_log_events=MagicMock(return_value={"events": []})
            )
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        http_check = next(c for c in result["checks"] if c["check"] == "http_health")
        assert http_check["passed"] is False
        assert "Connection refused" in http_check["detail"]

    def test_missing_security_header_fails_verification(self, valid_event, lambda_context):
        """
        Scenario: New image removed the HSTS header middleware.
        Expected: security_headers check fails → verification.passed=False.
        """
        headers_without_hsts = {
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            # Strict-Transport-Security intentionally missing
        }
        with (
            patch("verify_handler.urllib.request.urlopen",
                  return_value=self._mock_http(status=200, headers=headers_without_hsts)),
            patch("verify_handler.boto3") as mock_boto3,
        ):
            mock_boto3.client.return_value = MagicMock(
                filter_log_events=MagicMock(return_value={"events": []})
            )
            result = verify_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        header_check = next(
            c for c in result["checks"] if c["check"] == "security_headers"
        )
        assert header_check["passed"] is False
        assert "Strict-Transport-Security" in header_check["detail"]


# ---------------------------------------------------------------------------
# Negative tests — Rollback handler behaviour
# ---------------------------------------------------------------------------

class TestRollbackHandler:
    """Verify rollback handler reverts ECS service to the previous task definition."""

    def _valid_rollback_event(self, valid_event, deploy_result):
        return {**valid_event, "deploy": deploy_result}

    def _stable_ecs_client(self):
        """ECS client that reports a stable rollback after one poll."""
        mock = MagicMock()
        mock.update_service.return_value = {}
        mock.describe_services.return_value = {
            "services": [{
                "taskDefinition": "arn:...task:41",
                "deployments": [{
                    "rolloutState": "COMPLETED",
                    "runningCount": 1,
                    "desiredCount": 1,
                }],
            }]
        }
        return mock

    def test_rollback_updates_service_to_previous_task_def(
        self, valid_event, deploy_result, lambda_context
    ):
        """
        Scenario: Verification failed; rollback must revert ECS service.
        Expected: update_service called with previous_task_def_arn.
        """
        event = self._valid_rollback_event(valid_event, deploy_result)
        mock_ecs = self._stable_ecs_client()

        with (
            patch("rollback_handler.boto3") as mock_boto3,
            patch("rollback_handler.time") as mock_time,
        ):
            mock_boto3.client.return_value = mock_ecs
            mock_time.sleep.return_value = None
            mock_time.time.side_effect = [0, 0, 20]
            result = rollback_handler.handler(event, lambda_context)

        mock_ecs.update_service.assert_called_once_with(
            cluster=valid_event["cluster_name"],
            service=valid_event["service_name"],
            taskDefinition=deploy_result["previous_task_def_arn"],
            forceNewDeployment=True,
        )
        assert result["rolled_back"] is True
        assert result["task_def_arn"] == deploy_result["previous_task_def_arn"]

    def test_rollback_raises_when_no_previous_task_def(
        self, valid_event, lambda_context
    ):
        """
        Scenario: Deploy Lambda never ran (no previous_task_def_arn in state).
        Expected: ValueError is raised → Step Functions routes to RollbackFailed.
        """
        event = {**valid_event, "deploy": {}}  # no previous_task_def_arn

        with patch("rollback_handler.boto3"):
            with pytest.raises(ValueError, match="previous_task_def_arn"):
                rollback_handler.handler(event, lambda_context)

    def test_rollback_raises_on_timeout(
        self, valid_event, deploy_result, lambda_context
    ):
        """
        Scenario: ECS service never stabilises after rollback update.
        Expected: TimeoutError raised after MAX_WAIT_SECONDS elapsed.
        """
        event = self._valid_rollback_event(valid_event, deploy_result)

        mock_ecs = MagicMock()
        mock_ecs.update_service.return_value = {}
        # Always return an unstable multi-deployment state
        mock_ecs.describe_services.return_value = {
            "services": [{
                "deployments": [
                    {"rolloutState": "IN_PROGRESS", "runningCount": 0, "desiredCount": 1},
                    {"rolloutState": "COMPLETED",   "runningCount": 1, "desiredCount": 1},
                ]
            }]
        }

        with (
            patch("rollback_handler.boto3") as mock_boto3,
            patch("rollback_handler.time") as mock_time,
        ):
            mock_boto3.client.return_value = mock_ecs
            mock_time.sleep.return_value = None
            # First call: set deadline; second call: already past it
            max_wait = rollback_handler.MAX_WAIT_SECONDS
            mock_time.time.side_effect = [0, max_wait + 1]

            with pytest.raises(TimeoutError):
                rollback_handler.handler(event, lambda_context)

    def test_rollback_returns_correct_service_and_cluster(
        self, valid_event, deploy_result, lambda_context
    ):
        """Rollback result includes the service and cluster names for audit trail."""
        event = self._valid_rollback_event(valid_event, deploy_result)
        mock_ecs = self._stable_ecs_client()

        with (
            patch("rollback_handler.boto3") as mock_boto3,
            patch("rollback_handler.time") as mock_time,
        ):
            mock_boto3.client.return_value = mock_ecs
            mock_time.sleep.return_value = None
            mock_time.time.side_effect = [0, 0, 20]
            result = rollback_handler.handler(event, lambda_context)

        assert result["service"] == valid_event["service_name"]
        assert result["cluster"] == valid_event["cluster_name"]
