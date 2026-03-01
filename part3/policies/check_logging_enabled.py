# CKV_CUSTOM_4 - ALB must have access_logs enabled
# CKV_CUSTOM_5 - ECS task containers must use awslogs log driver

import json

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck


# ---------------------------------------------------------------------------
# CKV_CUSTOM_4 — ALB access logs
# ---------------------------------------------------------------------------

class ALBAccessLogsCheck(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name="Ensure ALB/NLB has access logging explicitly enabled",
            id="CKV_CUSTOM_4",
            categories=[CheckCategories.LOGGING],
            supported_resources=["aws_lb", "aws_alb"],
        )

    def scan_resource_conf(self, conf):
        access_logs = conf.get("access_logs", [{}])
        if isinstance(access_logs, list):
            access_logs = access_logs[0] if access_logs else {}
        if not isinstance(access_logs, dict):
            return CheckResult.FAILED

        enabled = access_logs.get("enabled", [False])
        if isinstance(enabled, list):
            enabled = enabled[0] if enabled else False

        return CheckResult.PASSED if enabled is True else CheckResult.FAILED


# ---------------------------------------------------------------------------
# CKV_CUSTOM_5 — ECS task definition awslogs driver
# ---------------------------------------------------------------------------

class ECSLoggingCheck(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name=(
                "Ensure ECS task definition container definitions use the "
                "awslogs log driver (CloudWatch Logs)"
            ),
            id="CKV_CUSTOM_5",
            categories=[CheckCategories.LOGGING],
            supported_resources=["aws_ecs_task_definition"],
        )

    def scan_resource_conf(self, conf):
        container_defs = conf.get("container_definitions", ["[]"])
        if isinstance(container_defs, list):
            container_defs = container_defs[0] if container_defs else "[]"

        if isinstance(container_defs, str):
            try:
                container_defs = json.loads(container_defs)
            except (json.JSONDecodeError, TypeError):
                return CheckResult.UNKNOWN

        if not isinstance(container_defs, list):
            return CheckResult.UNKNOWN

        for container in container_defs:
            log_config = container.get("logConfiguration", {})
            if log_config.get("logDriver") != "awslogs":
                return CheckResult.FAILED

        return CheckResult.PASSED


check_alb = ALBAccessLogsCheck()
check_ecs = ECSLoggingCheck()
