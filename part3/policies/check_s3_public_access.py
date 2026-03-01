# CKV_CUSTOM_2 - S3 public access block
# all four block settings must be explicitly true

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

BLOCK_SETTINGS = [
    "block_public_acls",
    "block_public_policy",
    "ignore_public_acls",
    "restrict_public_buckets",
]


class S3PublicAccessBlockCheck(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name=(
                "Ensure S3 bucket public access block has all four settings "
                "enabled (block_public_acls, block_public_policy, "
                "ignore_public_acls, restrict_public_buckets)"
            ),
            id="CKV_CUSTOM_2",
            categories=[CheckCategories.GENERAL_SECURITY],
            supported_resources=["aws_s3_bucket_public_access_block"],
        )

    def scan_resource_conf(self, conf):
        for setting in BLOCK_SETTINGS:
            val = conf.get(setting, [False])
            if isinstance(val, list):
                val = val[0] if val else False
            if val is not True:
                return CheckResult.FAILED
        return CheckResult.PASSED


check = S3PublicAccessBlockCheck()
