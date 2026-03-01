# CKV_CUSTOM_3 - SG must not allow 0.0.0.0/0 on port 22 (SSH) or 3389 (RDP)
# use SSM Session Manager instead of opening admin ports to the internet

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

ADMIN_PORTS = {22, 3389}
OPEN_CIDRS = {"0.0.0.0/0", "::/0"}


class SGAdminPortsCheck(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name=(
                "Ensure security groups do not allow unrestricted internet "
                "access on admin ports (22/SSH, 3389/RDP)"
            ),
            id="CKV_CUSTOM_3",
            categories=[CheckCategories.GENERAL_SECURITY],
            supported_resources=["aws_security_group", "aws_security_group_rule"],
        )

    def scan_resource_conf(self, conf):
        # --- aws_security_group: check inline ingress blocks ---
        ingress_rules = conf.get("ingress", [])
        if isinstance(ingress_rules, list) and ingress_rules:
            # Checkov may wrap the list itself in another list
            if isinstance(ingress_rules[0], list):
                ingress_rules = ingress_rules[0]
            for rule in ingress_rules:
                if isinstance(rule, dict) and self._rule_exposes_admin(rule):
                    return CheckResult.FAILED

        # --- aws_security_group_rule: the conf IS the rule ---
        rule_type = conf.get("type", [""])
        if isinstance(rule_type, list):
            rule_type = rule_type[0] if rule_type else ""
        if rule_type == "ingress" and self._rule_exposes_admin(conf):
            return CheckResult.FAILED

        return CheckResult.PASSED

    def _rule_exposes_admin(self, rule):
        from_port = rule.get("from_port", [0])
        to_port   = rule.get("to_port",   [0])
        cidrs     = rule.get("cidr_blocks",      [[]])
        ipv6      = rule.get("ipv6_cidr_blocks", [[]])

        if isinstance(from_port, list):
            from_port = from_port[0] if from_port else 0
        if isinstance(to_port,   list):
            to_port   = to_port[0]   if to_port   else 0
        if isinstance(cidrs, list) and cidrs and isinstance(cidrs[0], list):
            cidrs = cidrs[0]
        if isinstance(ipv6,  list) and ipv6  and isinstance(ipv6[0],  list):
            ipv6  = ipv6[0]

        all_cidrs = set(cidrs or []) | set(ipv6 or [])
        if not (OPEN_CIDRS & all_cidrs):
            return False

        try:
            from_port = int(from_port)
            to_port   = int(to_port)
        except (TypeError, ValueError):
            return False

        return any(from_port <= p <= to_port for p in ADMIN_PORTS)


check = SGAdminPortsCheck()
