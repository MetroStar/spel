# =============================================================================
# SPEL Infrastructure — Root Module
# =============================================================================
# Orchestrates all SPEL infrastructure using submodules:
#   - modules/networking : VPC, subnet, IGW, security group, Packer endpoints
#   - modules/iam        : Packer builder IAM role, policy, instance profile
#   - modules/ssm        : SSM endpoints, KMS, S3, CloudWatch, patching
#
# Single `tofu apply` creates everything; single `tofu destroy`
# tears it all down. Replaces the previous split between CLI scripts and
# OpenTofu, consolidating all infrastructure-as-code.
# =============================================================================

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

module "networking" {
  source = "./modules/networking"

  name_prefix             = var.name_prefix
  vpc_cidr                = var.vpc_cidr
  subnet_cidr             = var.subnet_cidr
  public_subnet           = var.public_subnet
  enable_internet_gateway = var.enable_internet_gateway
  enable_packer_endpoints = var.enable_packer_endpoints
  tags                    = local.common_tags
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

module "iam" {
  source = "./modules/iam"

  name_prefix = var.name_prefix
  tags        = local.common_tags
}

# -----------------------------------------------------------------------------
# SSM
# -----------------------------------------------------------------------------

module "ssm" {
  source = "./modules/ssm"

  name_prefix = var.name_prefix
  vpc_id      = module.networking.vpc_id
  subnet_ids  = [module.networking.subnet_id]
  vpc_cidr    = var.vpc_cidr
  route_table_ids = module.networking.route_table_ids

  # Wire SSM module to use the IAM module's role (no duplicate IAM)
  create_instance_profile     = false
  existing_instance_role_name = module.iam.role_name

  # Feature toggles
  enable_vpc_endpoints    = var.enable_vpc_endpoints
  enable_session_manager  = var.enable_session_manager
  enable_state_manager    = var.enable_state_manager
  enable_patch_manager    = var.enable_patch_manager
  enable_inventory        = var.enable_inventory
  enable_stig_enforcement = var.enable_stig_enforcement
  enable_ssm_agent_update = var.enable_ssm_agent_update
  enable_dhmc             = var.enable_dhmc
  enable_auto_tagging     = var.enable_auto_tagging
  create_kms_key          = var.create_kms_key
  kms_key_arn             = var.kms_key_arn
  alert_email             = var.alert_email

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Cross-module policy: Grant Packer builder role S3 access to SSM bucket
# (Lives in root module to avoid circular dependency between iam and ssm modules)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "packer_s3_access" {
  name = "${var.name_prefix}-packer-builder-s3"
  role = module.iam.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BuildArtifacts"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.ssm.s3_bucket_arn,
          "${module.ssm.s3_bucket_arn}/*"
        ]
      },
      {
        Sid    = "KMSDecryptBuildArtifacts"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = module.ssm.kms_key_arn != null ? [module.ssm.kms_key_arn] : ["*"]
      }
    ]
  })
}
