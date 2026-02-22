"""
Pre-flight Validation Lambda — NTT GCC Self-Healing Deployment Workflow

Checks performed:
  1. Required input parameters are present
  2. Target region is ap-southeast-1 (GCC constraint)
  3. Caller AWS account ID matches the expected account (if EXPECTED_ACCOUNT_ID is set)
  4. ECS cluster exists and carries the mandatory GCC tags
     (Owner, DataClassification, CostCenter)

Returns:
  { "passed": bool, "checks": [{ "check": str, "passed": bool, "detail": str }] }
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# Configuration (overridable via environment variables)
# ---------------------------------------------------------------------------
ALLOWED_REGION = os.getenv("ALLOWED_REGION", "ap-southeast-1")
EXPECTED_ACCOUNT = os.getenv("EXPECTED_ACCOUNT_ID", "")
REQUIRED_TAGS = {"Owner", "DataClassification", "CostCenter"}

REQUIRED_FIELDS = [
    "environment",
    "region",
    "image_tag",
    "image_uri",
    "endpoint_url",
    "cluster_name",
    "service_name",
    "task_family",
    "container_name",
    "log_group_name",
    "evidence_bucket",
]


# ---------------------------------------------------------------------------
# Check helpers
# ---------------------------------------------------------------------------

def check_required_fields(event: dict) -> dict:
    missing = [f for f in REQUIRED_FIELDS if not event.get(f)]
    if missing:
        return {
            "check": "required_fields",
            "passed": False,
            "detail": f"Missing or empty required fields: {missing}",
        }
    return {
        "check": "required_fields",
        "passed": True,
        "detail": "All required fields are present",
    }


def check_region(event: dict) -> dict:
    region = event.get("region", "")
    if region != ALLOWED_REGION:
        return {
            "check": "region_constraint",
            "passed": False,
            "detail": (
                f"Region '{region}' is not permitted. "
                f"GCC constraint requires '{ALLOWED_REGION}'."
            ),
        }
    return {
        "check": "region_constraint",
        "passed": True,
        "detail": f"Region '{region}' satisfies the GCC constraint",
    }


def check_account_id() -> dict:
    if not EXPECTED_ACCOUNT:
        return {
            "check": "account_id",
            "passed": True,
            "detail": "Account ID check skipped (EXPECTED_ACCOUNT_ID not configured)",
        }
    try:
        sts = boto3.client("sts")
        account_id = sts.get_caller_identity()["Account"]
        if account_id != EXPECTED_ACCOUNT:
            return {
                "check": "account_id",
                "passed": False,
                "detail": (
                    f"Caller account '{account_id}' does not match "
                    f"expected account '{EXPECTED_ACCOUNT}'"
                ),
            }
        return {
            "check": "account_id",
            "passed": True,
            "detail": f"Caller account '{account_id}' matches the expected account",
        }
    except ClientError as exc:
        return {
            "check": "account_id",
            "passed": False,
            "detail": f"STS GetCallerIdentity failed: {exc}",
        }


def check_cluster_tags(cluster_name: str, region: str) -> dict:
    if not cluster_name:
        return {
            "check": "cluster_tags",
            "passed": False,
            "detail": "cluster_name is empty; cannot validate tags",
        }
    try:
        ecs = boto3.client("ecs", region_name=region or ALLOWED_REGION)
        response = ecs.describe_clusters(clusters=[cluster_name], include=["TAGS"])
        clusters = response.get("clusters", [])
        if not clusters:
            return {
                "check": "cluster_tags",
                "passed": False,
                "detail": f"ECS cluster '{cluster_name}' not found",
            }
        present_tags = {t["key"] for t in clusters[0].get("tags", [])}
        missing_tags = REQUIRED_TAGS - present_tags
        if missing_tags:
            return {
                "check": "cluster_tags",
                "passed": False,
                "detail": (
                    f"ECS cluster '{cluster_name}' is missing mandatory tags: "
                    f"{sorted(missing_tags)}"
                ),
            }
        return {
            "check": "cluster_tags",
            "passed": True,
            "detail": (
                f"All mandatory tags present on cluster '{cluster_name}': "
                f"{sorted(REQUIRED_TAGS)}"
            ),
        }
    except ClientError as exc:
        return {
            "check": "cluster_tags",
            "passed": False,
            "detail": f"ECS DescribeClusters failed: {exc}",
        }


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------

def handler(event: dict, context) -> dict:
    logger.info("Pre-flight validation started. Input: %s", json.dumps(event))

    checks = []

    # 1. Required fields
    result = check_required_fields(event)
    checks.append(result)
    if not result["passed"]:
        # No point running further checks if basic inputs are missing
        output = {"passed": False, "checks": checks}
        logger.info("Pre-flight failed early (missing fields): %s", json.dumps(output))
        return output

    # 2. Region constraint
    checks.append(check_region(event))

    # 3. Account ID
    checks.append(check_account_id())

    # 4. ECS cluster tags
    checks.append(
        check_cluster_tags(
            cluster_name=event["cluster_name"],
            region=event.get("region", ALLOWED_REGION),
        )
    )

    passed = all(c["passed"] for c in checks)
    output = {"passed": passed, "checks": checks}

    if passed:
        logger.info("Pre-flight PASSED. All %d checks succeeded.", len(checks))
    else:
        failed = [c["check"] for c in checks if not c["passed"]]
        logger.warning("Pre-flight FAILED. Failed checks: %s", failed)

    logger.info("Pre-flight result: %s", json.dumps(output))
    return output
