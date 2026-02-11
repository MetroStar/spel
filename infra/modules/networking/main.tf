# =============================================================================
# Networking Module — VPC, Subnet, Internet Gateway, Security Group
# =============================================================================
# Creates the foundational network infrastructure for SPEL Packer builds.
# Supports both commercial and GovCloud partitions.
# =============================================================================

data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# -----------------------------------------------------------------------------
# Subnet
# -----------------------------------------------------------------------------

resource "aws_subnet" "this" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = var.public_subnet

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-subnet"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway + Route (only for public subnets)
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  count  = var.public_subnet ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

resource "aws_route_table" "this" {
  count  = var.public_subnet ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt"
  })
}

resource "aws_route" "default" {
  count                  = var.public_subnet ? 1 : 0
  route_table_id         = aws_route_table.this[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "this" {
  count          = var.public_subnet ? 1 : 0
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this[0].id
}

# -----------------------------------------------------------------------------
# Security Group — Packer build instances
# -----------------------------------------------------------------------------

resource "aws_security_group" "packer" {
  name        = "${var.name_prefix}-packer-sg"
  description = "Security group for SPEL Packer build instances"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-packer-sg"
  })
}

resource "aws_security_group_rule" "ssh_ingress" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.packer.id
  description       = "SSH from VPC CIDR"
}

resource "aws_security_group_rule" "winrm_ingress" {
  type              = "ingress"
  from_port         = 5986
  to_port           = 5986
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.packer.id
  description       = "WinRM-HTTPS from VPC CIDR"
}

resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.packer.id
  description       = "Allow all outbound"
}
