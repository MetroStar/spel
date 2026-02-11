# =============================================================================
# SPEL Infrastructure — Root Module
# =============================================================================
# Orchestrates all SPEL infrastructure using submodules:
#   - modules/networking : VPC, subnet, IGW, security group
#   - modules/iam        : Packer builder IAM role, policy, instance profile
#   - modules/ssm        : SSM endpoints, KMS, S3, CloudWatch, patching
#
# Single `terraform apply` creates everything; single `terraform destroy`
# tears it all down. Replaces the previous split between CLI scripts and
# Terraform, consolidating all infrastructure-as-code.
# =============================================================================

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

module "networking" {
  source = "./modules/networking"

  name_prefix   = var.name_prefix
  vpc_cidr      = var.vpc_cidr
  subnet_cidr   = var.subnet_cidr
  public_subnet = var.public_subnet
  tags          = local.common_tags
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

  # Wire SSM module to use the IAM module's role (no duplicate IAM)
  create_instance_profile     = false
  existing_instance_role_name = module.iam.role_name

  # Feature toggles
  enable_vpc_endpoints   = var.enable_vpc_endpoints
  enable_session_manager = var.enable_session_manager
  enable_state_manager   = var.enable_state_manager
  enable_patch_manager   = var.enable_patch_manager
  enable_inventory       = var.enable_inventory
  create_kms_key         = var.create_kms_key
  kms_key_arn            = var.kms_key_arn
  alert_email            = var.alert_email

  tags = local.common_tags
}
