# =============================================================================
# Networking Module — Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "subnet_id" {
  description = "ID of the created subnet"
  value       = aws_subnet.this.id
}

output "security_group_id" {
  description = "ID of the Packer security group"
  value       = aws_security_group.packer.id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway (null if public_subnet = false)"
  value       = var.public_subnet ? aws_internet_gateway.this[0].id : null
}
