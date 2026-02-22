"""
ECS Deploy Lambda — NTT GCC Self-Healing Deployment Workflow

Steps:
  1. Describe the current ECS service to capture the previous task definition ARN
  2. Retrieve and clone the current task definition, updating the container image
  3. Register the new task definition revision
  4. Update the ECS service to use the new revision (forced new deployment)

The previous task definition ARN is returned so the Rollback Lambda can revert if needed.

Returns:
  {
    "deployed": bool,
    "new_task_def_arn": str,
    "previous_task_def_arn": str,
    "image_uri": str,
  }
"""

import json
import logging

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Fields from the task definition that must NOT be forwarded when re-registering
_SKIP_TD_FIELDS = {
    "taskDefinitionArn",
    "revision",
    "status",
    "requiresAttributes",
    "compatibilities",
    "registeredAt",
    "registeredBy",
    "deregisteredAt",
}


def handler(event: dict, context) -> dict:
    logger.info(
        "Deploy started. environment=%s image_tag=%s",
        event.get("environment"),
        event.get("image_tag"),
    )

    region = event.get("region", "ap-southeast-1")
    cluster = event["cluster_name"]
    service = event["service_name"]
    container_name = event["container_name"]
    image_uri = event["image_uri"]

    ecs = boto3.client("ecs", region_name=region)

    # -----------------------------------------------------------------------
    # 1. Capture the current task definition ARN before making any change
    # -----------------------------------------------------------------------
    try:
        svc_response = ecs.describe_services(cluster=cluster, services=[service])
        services = svc_response.get("services", [])
        if not services:
            raise ValueError(
                f"ECS service '{service}' not found in cluster '{cluster}'"
            )
        previous_task_def_arn = services[0]["taskDefinition"]
    except ClientError as exc:
        raise RuntimeError(
            f"Failed to describe ECS service '{service}': {exc}"
        ) from exc

    logger.info("Previous task definition: %s", previous_task_def_arn)

    # -----------------------------------------------------------------------
    # 2. Retrieve and patch the task definition
    # -----------------------------------------------------------------------
    try:
        td_response = ecs.describe_task_definition(taskDefinition=previous_task_def_arn)
        td = td_response["taskDefinition"]
    except ClientError as exc:
        raise RuntimeError(
            f"Failed to describe task definition '{previous_task_def_arn}': {exc}"
        ) from exc

    # Update the target container image
    container_defs = td.get("containerDefinitions", [])
    updated = False
    for container in container_defs:
        if container["name"] == container_name:
            old_image = container.get("image", "")
            container["image"] = image_uri
            logger.info(
                "Updated container '%s' image: %s → %s",
                container_name, old_image, image_uri,
            )
            updated = True

    if not updated:
        raise ValueError(
            f"Container '{container_name}' not found in task definition "
            f"'{previous_task_def_arn}'. Available containers: "
            f"{[c['name'] for c in container_defs]}"
        )

    # Build the register_task_definition kwargs (strip read-only fields)
    td_kwargs = {k: v for k, v in td.items() if k not in _SKIP_TD_FIELDS}

    # -----------------------------------------------------------------------
    # 3. Register new task definition revision
    # -----------------------------------------------------------------------
    try:
        new_td_response = ecs.register_task_definition(**td_kwargs)
        new_task_def_arn = new_td_response["taskDefinition"]["taskDefinitionArn"]
    except ClientError as exc:
        raise RuntimeError(
            f"Failed to register new task definition: {exc}"
        ) from exc

    logger.info("New task definition registered: %s", new_task_def_arn)

    # -----------------------------------------------------------------------
    # 4. Update the ECS service to use the new revision
    # -----------------------------------------------------------------------
    try:
        ecs.update_service(
            cluster=cluster,
            service=service,
            taskDefinition=new_task_def_arn,
            forceNewDeployment=True,
        )
    except ClientError as exc:
        raise RuntimeError(
            f"Failed to update ECS service '{service}': {exc}"
        ) from exc

    logger.info(
        "ECS service '%s' updated to task definition '%s'",
        service, new_task_def_arn,
    )

    return {
        "deployed": True,
        "new_task_def_arn": new_task_def_arn,
        "previous_task_def_arn": previous_task_def_arn,
        "image_uri": image_uri,
    }
