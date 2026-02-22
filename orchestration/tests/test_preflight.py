"""
Unit tests for the Pre-flight Validation Lambda.

All boto3 calls are mocked — no AWS credentials required.
"""

import importlib.util
import os
import sys
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

preflight_handler = _load_lambda("preflight_handler", "preflight/handler.py")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_cluster_response(tags=None):
    """Build a mock ecs.describe_clusters() response."""
    return {
        "clusters": [
            {
                "clusterName": "Ntt-Gcc-Production-Cluster",
                "status": "ACTIVE",
                "tags": tags or [
                    {"key": "Owner", "value": "NTT"},
                    {"key": "DataClassification", "value": "Internal"},
                    {"key": "CostCenter", "value": "NTT"},
                    {"key": "Project", "value": "GCC"},
                ],
            }
        ],
        "failures": [],
    }


def _ecs_client(response=None):
    mock = MagicMock()
    mock.describe_clusters.return_value = response or _make_cluster_response()
    return mock


def _sts_client(account_id="992382521824"):
    mock = MagicMock()
    mock.get_caller_identity.return_value = {"Account": account_id}
    return mock


# ---------------------------------------------------------------------------
# 1. Happy path
# ---------------------------------------------------------------------------

class TestPreflightPasses:

    def test_returns_passed_true_with_valid_input(self, valid_event, lambda_context):
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(os.environ, {"EXPECTED_ACCOUNT_ID": ""}, clear=False),
        ):
            mock_boto3.client.side_effect = lambda svc, **kw: (
                _ecs_client() if svc == "ecs" else _sts_client()
            )
            result = preflight_handler.handler(valid_event, lambda_context)

        assert result["passed"] is True

    def test_all_checks_pass_individually(self, valid_event, lambda_context):
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(os.environ, {"EXPECTED_ACCOUNT_ID": ""}, clear=False),
        ):
            mock_boto3.client.side_effect = lambda svc, **kw: (
                _ecs_client() if svc == "ecs" else _sts_client()
            )
            result = preflight_handler.handler(valid_event, lambda_context)

        checks = {c["check"]: c["passed"] for c in result["checks"]}
        assert checks["required_fields"] is True
        assert checks["region_constraint"] is True
        assert checks["cluster_tags"] is True


# ---------------------------------------------------------------------------
# 2. Missing required fields
# ---------------------------------------------------------------------------

class TestMissingFields:

    def test_fails_when_image_tag_missing(self, valid_event, lambda_context):
        event = {**valid_event, "image_tag": ""}
        with patch("preflight_handler.boto3"):
            result = preflight_handler.handler(event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["required_fields"]["passed"] is False
        assert "image_tag" in checks["required_fields"]["detail"]

    def test_fails_when_multiple_fields_missing(self, lambda_context):
        event = {"environment": "Production", "region": "ap-southeast-1"}
        with patch("preflight_handler.boto3"):
            result = preflight_handler.handler(event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["required_fields"]["passed"] is False
        # Should have stopped early — no cluster_tags check run
        assert "cluster_tags" not in checks


# ---------------------------------------------------------------------------
# 3. Region constraint
# ---------------------------------------------------------------------------

class TestRegionConstraint:

    def test_fails_with_wrong_region(self, valid_event, lambda_context):
        event = {**valid_event, "region": "us-east-1"}
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(os.environ, {"EXPECTED_ACCOUNT_ID": ""}, clear=False),
        ):
            mock_boto3.client.side_effect = lambda svc, **kw: (
                _ecs_client() if svc == "ecs" else _sts_client()
            )
            result = preflight_handler.handler(event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["region_constraint"]["passed"] is False
        assert "us-east-1" in checks["region_constraint"]["detail"]

    def test_passes_with_correct_region(self, valid_event, lambda_context):
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(os.environ, {"EXPECTED_ACCOUNT_ID": ""}, clear=False),
        ):
            mock_boto3.client.side_effect = lambda svc, **kw: (
                _ecs_client() if svc == "ecs" else _sts_client()
            )
            result = preflight_handler.handler(valid_event, lambda_context)

        checks = {c["check"]: c for c in result["checks"]}
        assert checks["region_constraint"]["passed"] is True


# ---------------------------------------------------------------------------
# 4. Cluster tag validation
# ---------------------------------------------------------------------------

class TestClusterTags:

    def test_fails_when_owner_tag_missing(self, valid_event, lambda_context):
        tags_missing_owner = [
            {"key": "DataClassification", "value": "Internal"},
            {"key": "CostCenter", "value": "NTT"},
        ]
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(os.environ, {"EXPECTED_ACCOUNT_ID": ""}, clear=False),
        ):
            mock_boto3.client.side_effect = lambda svc, **kw: (
                _ecs_client(_make_cluster_response(tags_missing_owner))
                if svc == "ecs"
                else _sts_client()
            )
            result = preflight_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["cluster_tags"]["passed"] is False
        assert "Owner" in checks["cluster_tags"]["detail"]

    def test_fails_when_cluster_not_found(self, valid_event, lambda_context):
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(os.environ, {"EXPECTED_ACCOUNT_ID": ""}, clear=False),
        ):
            mock_ecs = MagicMock()
            mock_ecs.describe_clusters.return_value = {"clusters": [], "failures": []}
            mock_boto3.client.side_effect = lambda svc, **kw: (
                mock_ecs if svc == "ecs" else _sts_client()
            )
            result = preflight_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["cluster_tags"]["passed"] is False
        assert "not found" in checks["cluster_tags"]["detail"]

    def test_passes_with_all_required_tags(self, valid_event, lambda_context):
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(os.environ, {"EXPECTED_ACCOUNT_ID": ""}, clear=False),
        ):
            mock_boto3.client.side_effect = lambda svc, **kw: (
                _ecs_client() if svc == "ecs" else _sts_client()
            )
            result = preflight_handler.handler(valid_event, lambda_context)

        checks = {c["check"]: c for c in result["checks"]}
        assert checks["cluster_tags"]["passed"] is True


# ---------------------------------------------------------------------------
# 5. Account ID check
# ---------------------------------------------------------------------------

class TestAccountIdCheck:

    def test_passes_when_account_matches(self, valid_event, lambda_context):
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.dict(
                os.environ, {"EXPECTED_ACCOUNT_ID": "992382521824"}, clear=False
            ),
        ):
            mock_boto3.client.side_effect = lambda svc, **kw: (
                _ecs_client() if svc == "ecs" else _sts_client("992382521824")
            )
            result = preflight_handler.handler(valid_event, lambda_context)

        checks = {c["check"]: c for c in result["checks"]}
        assert checks["account_id"]["passed"] is True

    def test_fails_when_account_mismatches(self, valid_event, lambda_context):
        # EXPECTED_ACCOUNT is read at module load time, so patch the module constant
        with (
            patch("preflight_handler.boto3") as mock_boto3,
            patch.object(preflight_handler, "EXPECTED_ACCOUNT", "111111111111"),
        ):
            mock_boto3.client.side_effect = lambda svc, **kw: (
                _ecs_client() if svc == "ecs" else _sts_client("992382521824")
            )
            result = preflight_handler.handler(valid_event, lambda_context)

        assert result["passed"] is False
        checks = {c["check"]: c for c in result["checks"]}
        assert checks["account_id"]["passed"] is False
