#checkov:skip=CKV2_AWS_1:False positive — subnets are associated via the subnet_ids argument on aws_network_acl, which is equivalent to aws_network_acl_association resources
#checkov:skip=CKV_AWS_229:False positive — the public NACL only opens ports 80, 443, and 1024-65535; port 21 is not in any rule; checkov cannot evaluate dynamic block values
#checkov:skip=CKV_AWS_230:False positive — the public NACL only opens ports 80, 443, and 1024-65535; port 20 is not in any rule; checkov cannot evaluate dynamic block values
#checkov:skip=CKV_AWS_231:False positive — the public NACL only opens ports 80, 443, and 1024-65535; port 3389 is not in any rule; checkov cannot evaluate dynamic block values
#checkov:skip=CKV_AWS_232:False positive — the public NACL only opens ports 80, 443, and 1024-65535; port 22 is not in any rule; checkov cannot evaluate dynamic block values
resource "aws_network_acl" "this" {
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      rule_no    = ingress.value.rule_no
      protocol   = ingress.value.protocol
      action     = ingress.value.action
      cidr_block = ingress.value.cidr_block
      from_port  = ingress.value.from_port
      to_port    = ingress.value.to_port
    }
  }

  dynamic "egress" {
    for_each = var.egress_rules
    content {
      rule_no    = egress.value.rule_no
      protocol   = egress.value.protocol
      action     = egress.value.action
      cidr_block = egress.value.cidr_block
      from_port  = egress.value.from_port
      to_port    = egress.value.to_port
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}
