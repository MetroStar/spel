# =============================================================================
# SSM Infrastructure Module — Outputs
# =============================================================================
# All outputs needed by Packer builds, CI/CD pipelines, and production consumers.
# =============================================================================

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the KMS key used for SSM encryption (created or external)"
  value       = local.kms_enabled ? local.effective_kms_key_arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key (only set when create_kms_key = true)"
  value       = var.create_kms_key ? aws_kms_key.ssm[0].key_id : null
}

output "kms_alias_name" {
  description = "Alias of the KMS key (only set when create_kms_key = true)"
  value       = var.create_kms_key ? aws_kms_alias.ssm[0].name : null
}

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

output "vpc_endpoint_kms_dns" {
  description = "DNS name of the KMS VPC endpoint (only when KMS and VPC endpoints are enabled)"
  value       = var.enable_vpc_endpoints && local.kms_enabled ? aws_vpc_endpoint.kms[0].dns_entry[0].dns_name : null
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

output "session_manager_document_name" {
  description = "Name of the Session Manager preferences document"
  value       = var.enable_session_manager ? aws_ssm_document.session_manager_prefs[0].name : null
}

# -----------------------------------------------------------------------------
# Patch Manager
# -----------------------------------------------------------------------------

output "linux_patch_baseline_id" {
  description = "ID of the Linux STIG patch baseline"
  value       = var.enable_patch_manager ? aws_ssm_patch_baseline.linux[0].id : null
}

output "windows_patch_baseline_id" {
  description = "ID of the Windows STIG patch baseline"
  value       = var.enable_patch_manager ? aws_ssm_patch_baseline.windows[0].id : null
}

output "linux_maintenance_window_id" {
  description = "ID of the Linux patching maintenance window"
  value       = var.enable_patch_manager ? aws_ssm_maintenance_window.linux[0].id : null
}

output "windows_maintenance_window_id" {
  description = "ID of the Windows patching maintenance window"
  value       = var.enable_patch_manager ? aws_ssm_maintenance_window.windows[0].id : null
}

# -----------------------------------------------------------------------------
# STIG Enforcement
# -----------------------------------------------------------------------------

output "stig_enforce_el_association_id" {
  description = "ID of the State Manager association for EL STIG enforcement"
  value       = var.enable_stig_enforcement && var.enable_state_manager ? aws_ssm_association.stig_enforce_el[0].association_id : null
}

output "stig_enforce_al2023_association_id" {
  description = "ID of the State Manager association for AL2023 STIG enforcement"
  value       = var.enable_stig_enforcement && var.enable_state_manager ? aws_ssm_association.stig_enforce_al2023[0].association_id : null
}

output "ssm_agent_update_association_id" {
  description = "ID of the State Manager association for SSM agent auto-update"
  value       = var.enable_ssm_agent_update && var.enable_state_manager ? aws_ssm_association.ssm_agent_update[0].association_id : null
}

output "stig_enforce_windows_association_ids" {
  description = "Map of Windows Server version to STIG enforcement association IDs"
  value       = { for k, v in aws_ssm_association.stig_enforce_windows : k => v.association_id }
}

# -----------------------------------------------------------------------------
# Default Host Management Configuration (DHMC)
# -----------------------------------------------------------------------------

output "dhmc_role_name" {
  description = "Name of the IAM role used for Default Host Management Configuration"
  value       = var.enable_dhmc ? aws_iam_role.dhmc[0].name : null
}

output "dhmc_role_arn" {
  description = "ARN of the IAM role used for Default Host Management Configuration"
  value       = var.enable_dhmc ? aws_iam_role.dhmc[0].arn : null
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

output "s3_access_logs_bucket_name" {
  description = "Name of the S3 access logging bucket"
  value       = aws_s3_bucket.ssm_access_logs.id
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

# -----------------------------------------------------------------------------
# SNS
# -----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic for SSM alerts"
  value       = aws_sns_topic.ssm_alerts.arn
}

# -----------------------------------------------------------------------------
# Auto-Tagging
# -----------------------------------------------------------------------------

output "auto_tagging_automation_name" {
  description = "Name of the SSM Automation document for AMI tag propagation"
  value       = var.enable_auto_tagging ? aws_ssm_document.ami_tag_propagation[0].name : null
}

output "auto_tagging_eventbridge_rule_name" {
  description = "Name of the EventBridge rule that triggers AMI tag propagation"
  value       = var.enable_auto_tagging ? aws_cloudwatch_event_rule.instance_launch[0].name : null
}
