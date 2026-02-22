"""
Evidence Upload Lambda — NTT GCC Self-Healing Deployment Workflow

Builds a structured JSON audit artefact from the full state machine context
and uploads it to an S3 bucket with a timestamped key. This lambda is called
from every terminal path (success, rollback, and failure) to ensure an
auditable record exists regardless of outcome.

Input (from Step Functions Parameters block):
  {
    "outcome": "SUCCESS" | "ROLLBACK_COMPLETE" | "PREFLIGHT_FAILED"
              | "DEPLOY_FAILED" | "FAILED",
    "context": { ...full state machine state... }
  }

Returns:
  {
    "uploaded": bool,
    "s3_bucket": str,
    "s3_key": str,
    "outcome": str,
  }
"""

import datetime
import json
import logging

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event: dict, context) -> dict:
    outcome = event.get("outcome", "UNKNOWN")
    ctx = event.get("context", event)

    logger.info(
        "Evidence upload started. outcome=%s environment=%s image_tag=%s",
        outcome,
        ctx.get("environment", "unknown"),
        ctx.get("image_tag", "unknown"),
    )

    now = datetime.datetime.utcnow()
    timestamp_iso = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    timestamp_path = now.strftime("%Y/%m/%d")

    environment = ctx.get("environment", "unknown")
    image_tag = ctx.get("image_tag", "unknown")
    evidence_bucket = ctx.get("evidence_bucket", "")

    # -----------------------------------------------------------------------
    # Build the structured audit artefact
    # -----------------------------------------------------------------------
    summary = {
        "schema_version": "1.0",
        "outcome": outcome,
        "timestamp": timestamp_iso,
        "environment": environment,
        "region": ctx.get("region", "unknown"),
        "image_tag": image_tag,
        "image_uri": ctx.get("image_uri", "unknown"),
        "stages": {
            "preflight": ctx.get("preflight", {}),
            "deploy": ctx.get("deploy", {}),
            "verification": ctx.get("verification", {}),
            "rollback": ctx.get("rollback", {}),
        },
        "error": ctx.get("error", {}),
    }

    logger.info("Evidence summary: %s", json.dumps(summary, indent=2))

    # -----------------------------------------------------------------------
    # Upload to S3
    # -----------------------------------------------------------------------
    if not evidence_bucket:
        logger.warning(
            "evidence_bucket is not set; skipping S3 upload. "
            "Evidence logged to CloudWatch only."
        )
        return {"uploaded": False, "outcome": outcome, "summary": summary}

    # Sanitise image_tag for use in an S3 key (replace : and / with -)
    safe_tag = image_tag.replace(":", "-").replace("/", "-")
    s3_key = (
        f"deployment-evidence/{environment}/{timestamp_path}/"
        f"{now.strftime('%H%M%S')}-{safe_tag}-{outcome}.json"
    )

    try:
        s3 = boto3.client("s3", region_name=ctx.get("region", "ap-southeast-1"))
        s3.put_object(
            Bucket=evidence_bucket,
            Key=s3_key,
            Body=json.dumps(summary, indent=2).encode("utf-8"),
            ContentType="application/json",
            ServerSideEncryption="aws:kms",
        )
        logger.info(
            "Evidence uploaded to s3://%s/%s", evidence_bucket, s3_key
        )
        return {
            "uploaded": True,
            "s3_bucket": evidence_bucket,
            "s3_key": s3_key,
            "outcome": outcome,
        }
    except ClientError as exc:
        # Evidence upload failure must NOT block the terminal state
        logger.error("Failed to upload evidence to S3: %s", exc)
        return {
            "uploaded": False,
            "outcome": outcome,
            "error": str(exc),
        }
