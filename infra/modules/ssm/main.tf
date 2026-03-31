# =============================================================================
# SSM Infrastructure Module — Main
# =============================================================================
# Data sources for GovCloud-safe ARN construction and region-aware service
# names. Uses data.aws_partition to dynamically resolve "aws" vs "aws-us-gov".
# =============================================================================

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.id
  account_id = data.aws_caller_identity.current.account_id

  # ARN prefix: "arn:aws" or "arn:aws-us-gov"
  arn_prefix = "arn:${local.partition}"

  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    ManagedBy = "opentofu"
    Module    = "chimera-ssm"
  })

  # Convert extra-variables maps to SSM-compatible "key=value key2=value2" format.
  # AWS-ApplyAnsiblePlaybooks validates ExtraVariables against a regex that
  # only allows key=value pairs — JSON format is rejected.
  el_extra_vars = join(" ", [
    for k, v in var.stig_extra_variables : "${k}=${v}"
  ])
}
