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

variable "route_table_ids" {
  description = "List of route table IDs to associate with the S3 gateway endpoint. Passed from the networking module to avoid data source race conditions."
  type        = list(string)
  default     = []
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
  default     = true
}

variable "enable_patch_manager" {
  description = "Create custom patch baseline and patch group for STIG-hardened instances"
  type        = bool
  default     = true
}

variable "enable_inventory" {
  description = "Create SSM Inventory association for software and configuration data collection"
  type        = bool
  default     = true
}

variable "enable_stig_enforcement" {
  description = "Create State Manager associations to enforce STIG hardening on a schedule. Uses AWS-RunAnsiblePlaybook for EL distros and a shell script for AL2023."
  type        = bool
  default     = true
}

variable "enable_ssm_agent_update" {
  description = "Create State Manager association to keep the SSM agent up to date"
  type        = bool
  default     = true
}

variable "enable_dhmc" {
  description = "Enable Default Host Management Configuration (DHMC). When enabled, ALL EC2 instances in the account/region auto-register with SSM without needing an instance profile."
  type        = bool
  default     = true
}

variable "enable_auto_tagging" {
  description = "Enable automatic propagation of StigPlatform and StigManaged tags from AMIs to newly launched instances via EventBridge + SSM Automation."
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

variable "stig_enforcement_schedule" {
  description = "Cron or rate expression for STIG enforcement runs (applies hardening). Example: 'rate(7 days)'"
  type        = string
  default     = "rate(7 days)"
}

variable "stig_al2023_s3_key" {
  description = "S3 key (path) for the AL2023 STIG enforcement script package"
  type        = string
  default     = "ansible/al2023-stig-script.zip"
}

variable "ssm_agent_update_schedule" {
  description = "Cron or rate expression for SSM agent update schedule. Default: daily at 3AM UTC."
  type        = string
  default     = "cron(0 3 ? * * *)"
}

variable "stig_extra_variables" {
  description = <<-EOT
    Extra variables passed to the Ansible STIG playbook for both check-mode
    and enforcement runs. Passed via ExtraVariables in key=value format.
    Must include safety-critical overrides to prevent SSH/SSM lockout.
    Combines EL8 and EL9 variables — Ansible roles ignore unknown vars.
    NOTE: Only scalar values (string, bool, number) are supported here.
    List/complex values must go in the playbook package's site.yml vars.
  EOT
  type        = map(string)
  default = {
    # Common
    SSM           = "true"
    system_is_ec2 = "true"

    # EL9 — disable AIDE/crypto controls incompatible with EC2
    rhel_09_251010 = "false"
    rhel_09_251015 = "false"
    rhel_09_251020 = "false"
    rhel_09_251025 = "false"
    rhel_09_251030 = "false"
    rhel_09_251035 = "false"
    rhel_09_251040 = "false"
    rhel_09_251045 = "false"

    # EL8 — disable incompatible controls
    rhel8stig_copy_existing_zone = "false"
    rhel_08_040136               = "false"
  }
}

variable "oscap_profile" {
  description = "OpenSCAP XCCDF profile name for STIG scanning"
  type        = string
  default     = "xccdf_org.ssgproject.content_profile_stig"
}

variable "windows_stig_s3_key" {
  description = "S3 key (path) for the Windows STIG playbook zip package containing per-version playbooks"
  type        = string
  default     = "ansible/windows-stig-playbook.zip"
}

variable "windows_stig_extra_variables" {
  description = <<-EOT
    Extra variables passed to the Windows Ansible STIG playbooks.
    Combines all version-specific overrides — Ansible roles ignore unknown vars.
    WinRM/Packer-specific vars are omitted (SSM runs Ansible locally).
    Passed via ExtraVariables in key=value format (scalars only).
  EOT
  type        = map(string)
  default = {
    # Common Windows STIG vars
    SSM                           = "true"
    ansible_windows_domain_role   = "Standalone"
    ansible_windows_domain_member = "false"
    ansible_system_vendor         = "NA"
    ansible_virtualization_type   = "hvm"
    win_skip_for_test             = "false"

    # Win2016 — disable EC2-incompatible controls
    wn16_00_000030_pass_age           = "60"
    wn16_cc_000500                    = "false"
    wn16_cc_000530                    = "false"
    wn16_so_000010                    = "false"
    wn16_so_000020                    = "false"
    wn16_so_000030                    = "false"
    wn16_00_000450                    = "false"
    wn16_cc_000010                    = "false"
    wn16_cc_000020                    = "false"
    wn16stig_newadministratorname     = "maintuser"

    # Win2019 — disable EC2-incompatible controls
    wn19_cc_000470                    = "false"
    wn19_cc_000500                    = "false"
    wn19_so_000010                    = "false"
    wn19_so_000020                    = "false"
    wn19_so_000030                    = "false"
    wn19_00_000450                    = "false"
    wn19_cc_000010                    = "false"
    wn19_cc_000020                    = "false"
    wn19stig_newadministratorname     = "maintuser"

    # Win2022 — disable EC2-incompatible controls
    wn22_ac_000010                    = "false"
    wn22_cc_000470                    = "false"
    wn22_cc_000500                    = "false"
    wn22_so_000010                    = "false"
    wn22_so_000020                    = "false"
    wn22_so_000030                    = "false"
    wn22_00_000450                    = "false"
    wn22_cc_000010                    = "false"
    wn22_cc_000020                    = "false"
    wn22stig_newadministratorname     = "maintuser"
  }
}

variable "target_tag_key" {
  description = "EC2 instance tag key used to target SSM associations. Hardened AMIs are tagged with StigManaged=true."
  type        = string
  default     = "StigManaged"
}

variable "target_tag_value" {
  description = "EC2 instance tag value used to target SSM associations. Hardened AMIs are tagged with StigManaged=true."
  type        = string
  default     = "true"
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

variable "create_kms_key" {
  description = "Create a new KMS CMK for SSM encryption. Set to false and provide kms_key_arn to use an existing key."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key for S3/CloudWatch/SSM encryption. Only used when create_kms_key = false."
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
# Alerting
# -----------------------------------------------------------------------------

variable "alert_email" {
  description = "Email address for SNS alert notifications. Leave empty to skip email subscription (topic is always created)."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Session Manager
# -----------------------------------------------------------------------------

variable "session_idle_timeout" {
  description = "Session Manager idle timeout in minutes (STIG AC-12 / SC-10 recommends 20)"
  type        = number
  default     = 20
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
  default     = ["Critical", "Important", "Moderate"]
}

variable "patch_approve_after_days" {
  description = "Number of days after release before auto-approving patches"
  type        = number
  default     = 7
}

variable "maintenance_window_schedule" {
  description = "Cron or rate expression for the maintenance window. Default: Sunday 4AM UTC."
  type        = string
  default     = "cron(0 4 ? * SUN *)"
}

variable "maintenance_window_timezone" {
  description = "IANA timezone for the maintenance window schedule"
  type        = string
  default     = "UTC"
}

variable "maintenance_window_duration" {
  description = "Duration of the maintenance window in hours"
  type        = number
  default     = 3
}

variable "maintenance_window_cutoff" {
  description = "Hours before the end of the maintenance window to stop scheduling new tasks"
  type        = number
  default     = 1
}

variable "patch_max_concurrency" {
  description = "Maximum number of targets to patch simultaneously"
  type        = string
  default     = "25%"
}

variable "patch_max_errors" {
  description = "Maximum number of errors allowed before stopping the patching task"
  type        = string
  default     = "25%"
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
