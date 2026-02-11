# =============================================================================
# IAM Module — Outputs
# =============================================================================

output "role_name" {
  description = "Name of the Packer builder IAM role"
  value       = aws_iam_role.packer_builder.name
}

output "role_arn" {
  description = "ARN of the Packer builder IAM role"
  value       = aws_iam_role.packer_builder.arn
}

output "instance_profile_name" {
  description = "Name of the Packer builder instance profile"
  value       = aws_iam_instance_profile.packer_builder.name
}

output "instance_profile_arn" {
  description = "ARN of the Packer builder instance profile"
  value       = aws_iam_instance_profile.packer_builder.arn
}
