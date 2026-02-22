"""
ECS Rollback Lambda — NTT GCC Self-Healing Deployment Workflow

Reverts the ECS service to the previous stable task definition revision
captured by the Deploy Lambda, then polls until the rollback stabilises.

The previous task definition ARN is read from:
  event["deploy"]["previous_task_def_arn"]

Returns:
  {
    "rolled_back": bool,
    "task_def_arn": str,  # the task definition the service was reverted to
    "service": str,
    "cluster": str,
  }
"""

import json
import logging
import time

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

MAX_WAIT_SECONDS = 300   # 5 minutes maximum wait for rollback to stabilise
POLL_INTERVAL_SECONDS = 15


def handler(event: dict, context) -> dict:
    logger.info(
        "Rollback started. environment=%s", event.get("environment")
    )

    region = event.get("region", "ap-southeast-1")
    cluster = event["cluster_name"]
    service = event["service_name"]

    # The previous task definition ARN is nested under the deploy result
    deploy_result = event.get("deploy", {})
    previous_task_def_arn = deploy_result.get("previous_task_def_arn")

    if not previous_task_def_arn:
        raise ValueError(
            "Cannot roll back: 'previous_task_def_arn' is missing from the deploy result. "
            "The Deploy stage may not have completed successfully."
        )

    logger.info(
        "Rolling back service '%s' in cluster '%s' to task definition '%s'",
        service, cluster, previous_task_def_arn,
    )

    ecs = boto3.client("ecs", region_name=region)

    # -----------------------------------------------------------------------
    # 1. Revert the service to the previous task definition
    # -----------------------------------------------------------------------
    try:
        ecs.update_service(
            cluster=cluster,
            service=service,
            taskDefinition=previous_task_def_arn,
            forceNewDeployment=True,
        )
    except ClientError as exc:
        raise RuntimeError(
            f"Failed to update ECS service '{service}' during rollback: {exc}"
        ) from exc

    logger.info("Rollback update submitted. Waiting for stability…")

    # -----------------------------------------------------------------------
    # 2. Poll for stability
    # -----------------------------------------------------------------------
    deadline = time.time() + MAX_WAIT_SECONDS
    while time.time() < deadline:
        time.sleep(POLL_INTERVAL_SECONDS)

        try:
            svc_response = ecs.describe_services(cluster=cluster, services=[service])
            deployments = svc_response["services"][0].get("deployments", [])
        except ClientError as exc:
            logger.warning("DescribeServices failed during rollback poll: %s", exc)
            continue

        # A single COMPLETED deployment means the rollback has stabilised
        if (
            len(deployments) == 1
            and deployments[0].get("rolloutState") == "COMPLETED"
        ):
            logger.info("Rollback completed successfully.")
            return {
                "rolled_back": True,
                "task_def_arn": previous_task_def_arn,
                "service": service,
                "cluster": cluster,
            }

        running = deployments[0].get("runningCount", 0) if deployments else 0
        desired = deployments[0].get("desiredCount", 0) if deployments else 0
        elapsed = int(MAX_WAIT_SECONDS - (deadline - time.time()))
        logger.info(
            "Rollback in progress… running=%d desired=%d elapsed=%ds",
            running, desired, elapsed,
        )

    raise TimeoutError(
        f"Rollback did not stabilise within {MAX_WAIT_SECONDS}s. "
        "Manual intervention may be required."
    )
