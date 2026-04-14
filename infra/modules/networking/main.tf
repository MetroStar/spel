# =============================================================================
# Networking Module — VPC, Subnet, Internet Gateway, Security Group
# =============================================================================
# Creates the foundational network infrastructure for Crucible Packer builds.
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
# Internet Gateway (only when enabled)
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  count  = var.enable_internet_gateway ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# -----------------------------------------------------------------------------
# Route Table (always created — needed by the S3 gateway endpoint in the SSM
# module even when there is no internet gateway)
# -----------------------------------------------------------------------------

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt"
  })
}

resource "aws_route" "default" {
  count                  = var.enable_internet_gateway ? 1 : 0
  route_table_id         = aws_route_table.this.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "this" {
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this.id
}

# -----------------------------------------------------------------------------
# Security Group — Packer build instances
# -----------------------------------------------------------------------------

resource "aws_security_group" "packer" {
  name        = "${var.name_prefix}-packer-sg"
  description = "Security group for Crucible Packer build instances"
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
  cidr_blocks       = [var.enable_internet_gateway ? "0.0.0.0/0" : var.vpc_cidr]
  security_group_id = aws_security_group.packer.id
  description       = var.enable_internet_gateway ? "SSH from anywhere (Packer connects from GitHub Actions)" : "SSH from within the VPC (air-gapped)"
}

resource "aws_security_group_rule" "winrm_ingress" {
  type              = "ingress"
  from_port         = 5986
  to_port           = 5986
  protocol          = "tcp"
  cidr_blocks       = [var.enable_internet_gateway ? "0.0.0.0/0" : var.vpc_cidr]
  security_group_id = aws_security_group.packer.id
  description       = var.enable_internet_gateway ? "WinRM-HTTPS from anywhere (Packer connects from GitHub Actions)" : "WinRM-HTTPS from within the VPC (air-gapped)"
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

# -----------------------------------------------------------------------------
# VPC Endpoints — Packer API access (ec2 + sts)
# Only needed when the internet gateway is disabled. Packer calls
# RunInstances, CreateImage, etc. via the EC2 endpoint and
# AssumeRole / GetCallerIdentity via the STS endpoint.
# -----------------------------------------------------------------------------

locals {
  packer_endpoint_services = var.enable_packer_endpoints ? toset([
    "com.amazonaws.${data.aws_region.current.id}.ec2",
    "com.amazonaws.${data.aws_region.current.id}.sts",
  ]) : toset([])
}

resource "aws_security_group" "packer_endpoints" {
  count       = var.enable_packer_endpoints ? 1 : 0
  name        = "${var.name_prefix}-packer-ep-sg"
  description = "Allow HTTPS from the VPC to Packer VPC endpoints (ec2, sts)"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-packer-ep-sg"
  })
}

resource "aws_security_group_rule" "packer_endpoints_ingress" {
  count             = var.enable_packer_endpoints ? 1 : 0
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.packer_endpoints[0].id
  description       = "HTTPS from VPC to Packer endpoints"
}

resource "aws_vpc_endpoint" "packer" {
  for_each = local.packer_endpoint_services

  vpc_id              = aws_vpc.this.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.this.id]
  security_group_ids  = [aws_security_group.packer_endpoints[0].id]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${element(split(".", each.value), length(split(".", each.value)) - 1)}-ep"
  })
}
