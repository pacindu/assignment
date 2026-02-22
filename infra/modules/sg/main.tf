resource "aws_security_group" "this" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = var.name
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  count = length(var.ingress_rules)

  security_group_id            = aws_security_group.this.id
  description                  = var.ingress_rules[count.index].description
  from_port                    = var.ingress_rules[count.index].protocol == "-1" ? null : var.ingress_rules[count.index].from_port
  to_port                      = var.ingress_rules[count.index].protocol == "-1" ? null : var.ingress_rules[count.index].to_port
  ip_protocol                  = var.ingress_rules[count.index].protocol
  cidr_ipv4                    = length(var.ingress_rules[count.index].cidr_blocks) > 0 ? var.ingress_rules[count.index].cidr_blocks[0] : null
  referenced_security_group_id = var.ingress_rules[count.index].security_group_id
}

resource "aws_vpc_security_group_egress_rule" "this" {
  count = length(var.egress_rules)

  security_group_id            = aws_security_group.this.id
  description                  = var.egress_rules[count.index].description
  from_port                    = var.egress_rules[count.index].protocol == "-1" ? null : var.egress_rules[count.index].from_port
  to_port                      = var.egress_rules[count.index].protocol == "-1" ? null : var.egress_rules[count.index].to_port
  ip_protocol                  = var.egress_rules[count.index].protocol
  cidr_ipv4                    = length(var.egress_rules[count.index].cidr_blocks) > 0 ? var.egress_rules[count.index].cidr_blocks[0] : null
  referenced_security_group_id = var.egress_rules[count.index].security_group_id
}
