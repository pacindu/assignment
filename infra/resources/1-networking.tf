locals {
  prefix_raw = "${var.name}-${terraform.workspace}"

  prefix = replace(title(replace(local.prefix_raw, "-", " ")), " ", "-")

  # ---------------------------------------------------------------------------
  # Simplified 3-Tier NACL Architecture
  # NACLs are coarse subnet isolation only.
  # Security Groups handle all port-level rules.
  # ---------------------------------------------------------------------------

  # ===========================================================================
  # PUBLIC NACL — Internet-facing tier (ALB, NAT Gateway)
  # Allows:
  # - Internet access
  # - Communication with Private tier
  # ===========================================================================

  public_nacl_ingress = concat(
    [
      # Allow all from internet
      {
        rule_no    = 100
        protocol   = "-1"
        action     = "allow"
        cidr_block = "0.0.0.0/0"
        from_port  = 0
        to_port    = 0
      }
    ],
    # [
    #   # Allow all from Private tier
    #   for i, cidr in var.private_subnet_cidrs : {
    #     rule_no    = 200 + i * 10
    #     protocol   = "-1"
    #     action     = "allow"
    #     cidr_block = cidr
    #     from_port  = 0
    #     to_port    = 0
    #   }
    # ]
  )

  public_nacl_egress = [
    # Allow all outbound (internet + private)
    {
      rule_no    = 100
      protocol   = "-1"
      action     = "allow"
      cidr_block = "0.0.0.0/0"
      from_port  = 0
      to_port    = 0
    }
  ]


  # ===========================================================================
  # PRIVATE NACL — Application tier (ECS/Fargate)
  # Allows:
  # - Public tier
  # - Secure tier
  # - Outbound internet via NAT
  # ===========================================================================

  private_nacl_ingress = concat(
    [
      # Allow all from Public tier (ALB → ECS)
      for i, cidr in var.public_subnet_cidrs : {
        rule_no    = 100 + i * 10
        protocol   = "-1"
        action     = "allow"
        cidr_block = cidr
        from_port  = 0
        to_port    = 0
      }
    ],
    [
      # Allow all from Secure tier (DB responses)
      for i, cidr in var.secure_subnet_cidrs : {
        rule_no    = 200 + i * 10
        protocol   = "-1"
        action     = "allow"
        cidr_block = cidr
        from_port  = 0
        to_port    = 0
      }
    ],
    [
      # Allow return traffic from internet via NAT Gateway.
      # NACLs are stateless — without this rule, responses from ECR, CloudWatch,
      # and other AWS public endpoints are silently dropped at the subnet boundary.
      {
        rule_no    = 300
        protocol   = "-1"
        action     = "allow"
        cidr_block = "0.0.0.0/0"
        from_port  = 0
        to_port    = 0
      }
    ]
  )

  private_nacl_egress = [
    # Allow all outbound (internet via NAT + secure tier)
    {
      rule_no    = 100
      protocol   = "-1"
      action     = "allow"
      cidr_block = "0.0.0.0/0"
      from_port  = 0
      to_port    = 0
    }
  ]


  # ===========================================================================
  # SECURE NACL — Data tier (RDS, ElastiCache, etc.)
  # Allows:
  # - Only communication with Private tier
  # - NO internet access
  # ===========================================================================

  secure_nacl_ingress = [
    # Allow all from Private tier only
    for i, cidr in var.private_subnet_cidrs : {
      rule_no    = 100 + i * 10
      protocol   = "-1"
      action     = "allow"
      cidr_block = cidr
      from_port  = 0
      to_port    = 0
    }
  ]

  secure_nacl_egress = [
    # Allow responses only to Private tier
    for i, cidr in var.private_subnet_cidrs : {
      rule_no    = 100 + i * 10
      protocol   = "-1"
      action     = "allow"
      cidr_block = cidr
      from_port  = 0
      to_port    = 0
    }
  ]
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
module "igw" {
  source = "../modules/igw"

  name   = "${local.prefix}-Igw"
  vpc_id = module.vpc.vpc_id
  tags   = var.tags
}

# -----------------------------------------------------------------------------
# NAT Gateway — single NAT in AZ-a (cost-optimised)
# For full HA, provision one NAT per AZ
# -----------------------------------------------------------------------------
module "natgw" {
  source = "../modules/natgw"

  name             = "${local.prefix}-Natgw"
  public_subnet_id = module.subnets.public_subnet_ids[0]
  tags             = var.tags

  depends_on = [module.igw]
}

# -----------------------------------------------------------------------------
# Route Tables
# Public  : 0.0.0.0/0 → IGW
# Private : 0.0.0.0/0 → NAT GW
# Secure  : no routes (local VPC traffic only)
# -----------------------------------------------------------------------------
module "route_tables" {
  source = "../modules/routetable"

  name               = local.prefix
  vpc_id             = module.vpc.vpc_id
  igw_id             = module.igw.igw_id
  natgw_id           = module.natgw.natgw_id
  public_subnet_ids  = module.subnets.public_subnet_ids
  private_subnet_ids = module.subnets.private_subnet_ids
  secure_subnet_ids  = module.subnets.secure_subnet_ids
  tags               = var.tags
}

# -----------------------------------------------------------------------------
# NACLs — stateless subnet-level access control (2nd layer after security groups)
# Public  : allow HTTP/HTTPS in, container port to ECS out
# Private : allow container port from ALB, DB ports to secure, NAT return
# Secure  : allow DB ports from ECS only, no internet
# -----------------------------------------------------------------------------
module "nacl_public" {
  source = "../modules/acl"

  name          = "${local.prefix}-Nacl-Public"
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.subnets.public_subnet_ids
  ingress_rules = local.public_nacl_ingress
  egress_rules  = local.public_nacl_egress
  tags          = var.tags
}

module "nacl_private" {
  source = "../modules/acl"

  name          = "${local.prefix}-Nacl-Private"
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.subnets.private_subnet_ids
  ingress_rules = local.private_nacl_ingress
  egress_rules  = local.private_nacl_egress
  tags          = var.tags
}

module "nacl_secure" {
  source = "../modules/acl"

  name          = "${local.prefix}-Nacl-Secure"
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.subnets.secure_subnet_ids
  ingress_rules = local.secure_nacl_ingress
  egress_rules  = local.secure_nacl_egress
  tags          = var.tags
}


# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../modules/vpc"

  name     = "${local.prefix}-Vpc"
  vpc_cidr = var.vpc_cidr
  tags     = var.tags
}

# -----------------------------------------------------------------------------
# Subnets — 3 tiers across 2 AZs
# Public  : ALB, NAT Gateway
# Private : ECS Fargate (outbound via NAT)
# Secure  : Databases (no internet access)
# -----------------------------------------------------------------------------
module "subnets" {
  source = "../modules/subnet"

  name               = local.prefix
  vpc_id             = module.vpc.vpc_id
  availability_zones = var.availability_zones

  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  secure_subnet_cidrs  = var.secure_subnet_cidrs

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security Groups
#
# sg_alb  : Internet-facing ALB — HTTP/HTTPS inbound, all outbound
# sg_ecs  : ECS Fargate tasks — container port from ALB, HTTPS outbound
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ALB Security Group
# -----------------------------------------------------------------------------
module "sg_alb" {
  source = "../modules/sg"

  name        = "${local.prefix}-Sg-Alb"
  description = "ALB: allow HTTP/HTTPS from internet"
  vpc_id      = module.vpc.vpc_id
  tags        = var.tags

  ingress_rules = [
    {
      description = "Allow HTTP from internet"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "Allow HTTPS from internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  egress_rules = [
    {
      description = "Allow all outbound"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

# -----------------------------------------------------------------------------
# ECS Security Group
# -----------------------------------------------------------------------------
module "sg_ecs" {
  source = "../modules/sg"

  name        = "${local.prefix}-Sg-Ecs"
  description = "ECS: allow container port from ALB, HTTPS outbound via NAT"
  vpc_id      = module.vpc.vpc_id
  tags        = var.tags

  ingress_rules = [
    {
      description       = "Allow container port from ALB"
      from_port         = var.container_port
      to_port           = var.container_port
      protocol          = "tcp"
      security_group_id = module.sg_alb.sg_id
    }
  ]

  egress_rules = [
    {
      description = "Allow HTTPS outbound (ECR, CloudWatch, Secrets Manager)"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}
