# =============================================================================
# SSM Infrastructure Module — Outputs
# =============================================================================
# All outputs needed by Packer builds, CI/CD pipelines, and production consumers.
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Endpoints
# -----------------------------------------------------------------------------

output "vpc_endpoint_ssm_dns" {
  description = "DNS name of the SSM VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ssm[0].dns_entry[0].dns_name : null
}

output "vpc_endpoint_ssmmessages_dns" {
  description = "DNS name of the SSM Messages VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ssmmessages[0].dns_entry[0].dns_name : null
}

output "vpc_endpoint_ec2messages_dns" {
  description = "DNS name of the EC2 Messages VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ec2messages[0].dns_entry[0].dns_name : null
}

output "vpc_endpoint_logs_dns" {
  description = "DNS name of the CloudWatch Logs VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.logs[0].dns_entry[0].dns_name : null
}

output "vpc_endpoint_s3_prefix_list_id" {
  description = "Prefix list ID of the S3 gateway endpoint (for route table / SG rules)"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.s3[0].prefix_list_id : null
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

output "instance_profile_name" {
  description = "Name of the IAM instance profile with SSM permissions"
  value       = var.create_instance_profile ? aws_iam_instance_profile.ssm[0].name : null
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile with SSM permissions"
  value       = var.create_instance_profile ? aws_iam_instance_profile.ssm[0].arn : null
}

output "instance_role_name" {
  description = "Name of the IAM role attached to the instance profile"
  value       = var.create_instance_profile ? aws_iam_role.ssm_instance[0].name : null
}

output "instance_role_arn" {
  description = "ARN of the IAM role attached to the instance profile"
  value       = var.create_instance_profile ? aws_iam_role.ssm_instance[0].arn : null
}

output "caller_policy_arn" {
  description = "ARN of the IAM policy for CI runners / humans to invoke SSM operations"
  value       = aws_iam_policy.ssm_caller.arn
}

# -----------------------------------------------------------------------------
# SSM
# -----------------------------------------------------------------------------

output "ssm_document_oscap_name" {
  description = "Name of the custom SSM document for OpenSCAP scanning"
  value       = aws_ssm_document.oscap_scan.name
}

output "ssm_document_oscap_arn" {
  description = "ARN of the custom SSM document for OpenSCAP scanning"
  value       = aws_ssm_document.oscap_scan.arn
}

# -----------------------------------------------------------------------------
# S3
# -----------------------------------------------------------------------------

output "s3_bucket_name" {
  description = "Name of the S3 bucket for SSM outputs and Ansible playbook delivery"
  value       = aws_s3_bucket.ssm.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for SSM outputs and Ansible playbook delivery"
  value       = aws_s3_bucket.ssm.arn
}

# -----------------------------------------------------------------------------
# CloudWatch
# -----------------------------------------------------------------------------

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for SSM output"
  value       = aws_cloudwatch_log_group.ssm.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for SSM output"
  value       = aws_cloudwatch_log_group.ssm.arn
}
