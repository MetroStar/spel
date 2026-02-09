# =============================================================================
# SSM Infrastructure Module — Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for all resource names (e.g., 'spel-ci', 'spel-prod')"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must contain only alphanumeric characters and hyphens."
  }
}

variable "vpc_id" {
  description = "ID of the existing VPC to attach SSM infrastructure to"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for VPC interface endpoints. Use private subnets for air-gapped environments."
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (used for endpoint security group ingress)"
  type        = string
}

# -----------------------------------------------------------------------------
# Feature Toggles
# -----------------------------------------------------------------------------

variable "enable_vpc_endpoints" {
  description = "Create VPC endpoints for SSM services (required for air-gapped/private subnet environments)"
  type        = bool
  default     = true
}

variable "enable_session_manager" {
  description = "Enable Session Manager support (adds KMS encryption and logging for sessions)"
  type        = bool
  default     = true
}

variable "enable_state_manager" {
  description = "Create State Manager associations for scheduled Ansible and OpenSCAP runs"
  type        = bool
  default     = false
}

variable "enable_patch_manager" {
  description = "Create custom patch baseline and patch group for STIG-hardened instances"
  type        = bool
  default     = false
}

variable "enable_inventory" {
  description = "Create SSM Inventory association for software and configuration data collection"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# SSM Configuration
# -----------------------------------------------------------------------------

variable "oscap_schedule" {
  description = "Cron or rate expression for scheduled OpenSCAP scans (State Manager). Example: 'rate(7 days)'"
  type        = string
  default     = "rate(7 days)"
}

variable "ansible_schedule" {
  description = "Cron or rate expression for scheduled Ansible STIG check-mode runs. Example: 'rate(7 days)'"
  type        = string
  default     = "rate(7 days)"
}

variable "ansible_s3_key" {
  description = "S3 key (path) for the Ansible STIG playbook zip package. Set by package-ansible-stig.sh."
  type        = string
  default     = "ansible/stig-playbook.zip"
}

variable "oscap_profile" {
  description = "OpenSCAP XCCDF profile name for STIG scanning"
  type        = string
  default     = "xccdf_org.ssgproject.content_profile_stig"
}

variable "target_tag_key" {
  description = "EC2 instance tag key used to target SSM associations"
  type        = string
  default     = "Project"
}

variable "target_tag_value" {
  description = "EC2 instance tag value used to target SSM associations"
  type        = string
  default     = "SPEL"
}

# -----------------------------------------------------------------------------
# CloudWatch & Logging
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 90

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention value."
  }
}

# -----------------------------------------------------------------------------
# Encryption
# -----------------------------------------------------------------------------

variable "kms_key_arn" {
  description = "ARN of an existing KMS key for S3/CloudWatch/SSM encryption. If empty, uses AWS-managed keys."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Tagging
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Patch Manager Configuration
# -----------------------------------------------------------------------------

variable "patch_classification" {
  description = "Patch classifications to approve (Linux). Example: ['Security', 'Bugfix']"
  type        = list(string)
  default     = ["Security", "Bugfix"]
}

variable "patch_severity" {
  description = "Patch severities to approve (Linux). Example: ['Critical', 'Important']"
  type        = list(string)
  default     = ["Critical", "Important", "Medium"]
}

variable "patch_approve_after_days" {
  description = "Number of days after release before auto-approving patches"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Instance Profile
# -----------------------------------------------------------------------------

variable "create_instance_profile" {
  description = "Create a new IAM instance profile with SSM permissions. Set to false if using an existing profile."
  type        = bool
  default     = true
}

variable "existing_instance_role_name" {
  description = "Name of an existing IAM role to attach SSM policies to (only used when create_instance_profile = false)"
  type        = string
  default     = ""
}
