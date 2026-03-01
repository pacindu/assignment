# CKV_CUSTOM_6 - no IAM policy should have Action: "*" with Effect: Allow
# service-scoped wildcards like ecr:* are fine, full admin wildcard is not

import json

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck


class IAMWildcardAdminCheck(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name=(
                "Ensure IAM policies do not grant full wildcard admin "
                "actions (Action: '*') without justification"
            ),
            id="CKV_CUSTOM_6",
            categories=[CheckCategories.IAM],
            supported_resources=["aws_iam_policy", "aws_iam_role_policy"],
        )

    def scan_resource_conf(self, conf):
        policy_doc = conf.get("policy", ["{}"])
        if isinstance(policy_doc, list):
            policy_doc = policy_doc[0] if policy_doc else "{}"

        # Policy may be a raw JSON string (templatefile / jsonencode result)
        if isinstance(policy_doc, str):
            try:
                policy_doc = json.loads(policy_doc)
            except (json.JSONDecodeError, TypeError):
                # Cannot parse — skip rather than false-positive
                return CheckResult.UNKNOWN

        if not isinstance(policy_doc, dict):
            return CheckResult.UNKNOWN

        for stmt in policy_doc.get("Statement", []):
            if stmt.get("Effect", "Deny") != "Allow":
                continue
            actions = stmt.get("Action", [])
            if isinstance(actions, str):
                actions = [actions]
            if "*" in actions:
                return CheckResult.FAILED

        return CheckResult.PASSED


check = IAMWildcardAdminCheck()
