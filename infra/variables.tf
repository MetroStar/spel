# =============================================================================
# Granite Infrastructure — Root Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for all resource names (e.g., 'granite', 'granite-ci')"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must contain only alphanumeric characters and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet" {
  description = "Whether the subnet should auto-assign public IPs on launch"
  type        = bool
  default     = true
}

variable "enable_internet_gateway" {
  description = "Create an Internet Gateway and a default route. Set to false for air-gapped builds that rely on VPC endpoints."
  type        = bool
  default     = true
}

variable "enable_packer_endpoints" {
  description = "Create VPC endpoints for EC2 and STS so Packer can reach AWS APIs without an internet gateway"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# SSM Feature Toggles
# -----------------------------------------------------------------------------

variable "enable_vpc_endpoints" {
  description = "Create VPC endpoints for SSM services (required for air-gapped environments)"
  type        = bool
  default     = true
}

variable "enable_session_manager" {
  description = "Enable Session Manager with KMS encryption and logging"
  type        = bool
  default     = true
}

variable "enable_state_manager" {
  description = "Create State Manager associations for scheduled scans"
  type        = bool
  default     = true
}

variable "enable_patch_manager" {
  description = "Create patch baselines and maintenance windows"
  type        = bool
  default     = true
}

variable "enable_inventory" {
  description = "Create SSM Inventory association for data collection"
  type        = bool
  default     = true
}

variable "enable_stig_enforcement" {
  description = "Create State Manager associations to enforce STIG hardening. CI/CD pipelines upload playbook packages to S3 automatically."
  type        = bool
  default     = true
}

variable "enable_ssm_agent_update" {
  description = "Create State Manager association to keep the SSM agent up to date"
  type        = bool
  default     = true
}

variable "enable_dhmc" {
  description = "Enable Default Host Management Configuration (DHMC). Auto-registers all EC2 instances with SSM."
  type        = bool
  default     = true
}

variable "enable_auto_tagging" {
  description = "Enable automatic propagation of StigPlatform/StigManaged tags from AMIs to instances via EventBridge + SSM Automation."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Encryption
# -----------------------------------------------------------------------------

variable "create_kms_key" {
  description = "Create a new KMS CMK for SSM encryption. Set to false to use an existing key."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key (only used when create_kms_key = false)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Alerting
# -----------------------------------------------------------------------------

variable "alert_email" {
  description = "Email for SNS alert notifications (leave empty to skip subscription)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  common_tags = merge(var.tags, {
    Project   = "GRANITE"
    ManagedBy = "opentofu"
  })
}
