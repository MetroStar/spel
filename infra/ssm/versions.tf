# =============================================================================
# Terraform / OpenTofu Version & Provider Requirements
# =============================================================================
# Compatible with both HashiCorp Terraform (>= 1.0) and OpenTofu (>= 1.0).
# - No BSL-only features (removed blocks, provider-defined functions)
# - No OpenTofu-only features (encryption blocks, -exclude flag)
# - DynamoDB locking over S3-native locking for broad version compatibility
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
