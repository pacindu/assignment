# Public route table — routes all outbound traffic through the IGW
resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.igw_id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-public"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_ids)
  subnet_id      = var.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}

# Private route tables — one per AZ, outbound through NAT Gateway
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_ids)
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.natgw_id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-private-${count.index}"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_ids)
  subnet_id      = var.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private[count.index].id
}

# Secure route tables — one per AZ, no routes (fully isolated, no internet or NAT access)
resource "aws_route_table" "secure" {
  count  = length(var.secure_subnet_ids)
  vpc_id = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-secure-${count.index}"
  })
}

resource "aws_route_table_association" "secure" {
  count          = length(var.secure_subnet_ids)
  subnet_id      = var.secure_subnet_ids[count.index]
  route_table_id = aws_route_table.secure[count.index].id
}
