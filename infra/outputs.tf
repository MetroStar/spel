# =============================================================================
# Granite Infrastructure — Outputs
# =============================================================================
# All outputs needed by Packer builds and CI/CD pipelines.
# =============================================================================

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = module.networking.subnet_id
}

output "security_group_id" {
  description = "ID of the Packer security group"
  value       = module.networking.security_group_id
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

output "instance_profile_name" {
  description = "Name of the Packer builder instance profile"
  value       = module.iam.instance_profile_name
}

output "instance_profile_arn" {
  description = "ARN of the Packer builder instance profile"
  value       = module.iam.instance_profile_arn
}

output "instance_role_name" {
  description = "Name of the Packer builder IAM role"
  value       = module.iam.role_name
}

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the KMS key for EBS/SSM encryption"
  value       = module.ssm.kms_key_arn
}

output "kms_key_id" {
  description = "ID of the KMS key (only when create_kms_key = true)"
  value       = module.ssm.kms_key_id
}

# -----------------------------------------------------------------------------
# SSM
# -----------------------------------------------------------------------------

output "s3_bucket_name" {
  description = "Name of the S3 bucket for SSM outputs"
  value       = module.ssm.s3_bucket_name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for SSM"
  value       = module.ssm.cloudwatch_log_group_name
}

output "ssm_document_oscap_name" {
  description = "Name of the OpenSCAP SSM document"
  value       = module.ssm.ssm_document_oscap_name
}

output "caller_policy_arn" {
  description = "ARN of the IAM policy for CI runners to invoke SSM operations"
  value       = module.ssm.caller_policy_arn
}

output "session_manager_document_name" {
  description = "Name of the Session Manager preferences document"
  value       = module.ssm.session_manager_document_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for SSM alerts"
  value       = module.ssm.sns_topic_arn
}
