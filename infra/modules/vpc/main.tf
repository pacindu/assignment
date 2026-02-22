#checkov:skip=CKV2_AWS_12:VPC flow logging requires a dedicated IAM role and log group; configure at the environment layer if needed
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = var.name
  })
}

# Restrict the default security group — deny all ingress and egress by default
# so no workload accidentally inherits unrestricted access (CKV2_AWS_12)
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-default-sg-restricted"
  })
}
