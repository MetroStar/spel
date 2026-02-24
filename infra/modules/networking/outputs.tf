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
  description = "ID of the internet gateway (null when enable_internet_gateway = false)"
  value       = var.enable_internet_gateway ? aws_internet_gateway.this[0].id : null
}

output "route_table_ids" {
  description = "List of route table IDs created by this module"
  value       = [aws_route_table.this.id]
}

output "packer_endpoints_security_group_id" {
  description = "ID of the security group attached to Packer VPC endpoints (null when enable_packer_endpoints = false)"
  value       = var.enable_packer_endpoints ? aws_security_group.packer_endpoints[0].id : null
}
