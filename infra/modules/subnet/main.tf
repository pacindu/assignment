# Public subnets — internet-facing tier (ALB, NAT Gateway)
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = var.vpc_id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-public-${var.availability_zones[count.index]}"
    Tier = "Public"
  })
}

# Private subnets — application tier (ECS Fargate, outbound via NAT)
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = var.vpc_id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-private-${var.availability_zones[count.index]}"
    Tier = "Private"
  })
}

# Secure subnets — data tier (databases, no internet access, no NAT route)
resource "aws_subnet" "secure" {
  count = length(var.secure_subnet_cidrs)

  vpc_id                  = var.vpc_id
  cidr_block              = var.secure_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-secure-${var.availability_zones[count.index]}"
    Tier = "Secure"
  })
}
