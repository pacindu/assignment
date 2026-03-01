# CKV_CUSTOM_1 - all GCC resources must have mandatory tags
# fails if Project, Environment, Owner, CostCenter or Terraform tag is missing

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

REQUIRED_TAGS = {"Project", "Environment", "Owner", "CostCenter", "Terraform"}

# All resource types deployed in this project that support tags.
TAGGED_RESOURCES = [
    "aws_vpc",
    "aws_subnet",
    "aws_internet_gateway",
    "aws_nat_gateway",
    "aws_eip",
    "aws_network_acl",
    "aws_route_table",
    "aws_security_group",
    "aws_lb",
    "aws_alb",
    "aws_lb_target_group",
    "aws_lb_listener",
    "aws_ecs_cluster",
    "aws_ecs_service",
    "aws_ecs_task_definition",
    "aws_ecr_repository",
    "aws_s3_bucket",
    "aws_cloudwatch_log_group",
    "aws_cloudwatch_metric_alarm",
    "aws_kms_key",
    "aws_iam_role",
    "aws_wafv2_web_acl",
    "aws_elasticache_replication_group",
    "aws_db_instance",
    "aws_db_subnet_group",
    "aws_elasticache_subnet_group",
]


class MandatoryTagsCheck(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name="Ensure GCC resources have mandatory tags (Project, Environment, Owner, CostCenter, Terraform)",
            id="CKV_CUSTOM_1",
            categories=[CheckCategories.GENERAL_SECURITY],
            supported_resources=TAGGED_RESOURCES,
        )

    def scan_resource_conf(self, conf):
        tags = conf.get("tags", [{}])
        # checkov wraps HCL values in lists
        if isinstance(tags, list):
            tags = tags[0] if tags else {}
        if not isinstance(tags, dict):
            return CheckResult.FAILED
        if REQUIRED_TAGS - set(tags.keys()):
            return CheckResult.FAILED
        return CheckResult.PASSED


check = MandatoryTagsCheck()
