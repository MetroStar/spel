# =============================================================================
# SSM Infrastructure Module — STIG Enforcement Associations
# =============================================================================
# Scheduled SSM associations that ENFORCE STIG hardening (not check-mode).
#
# 1. EL (RHEL/CentOS/OracleLinux) STIG Enforcement:
#    Uses AWS-ApplyAnsiblePlaybooks with Ansible Lockdown playbooks.
#    Targets instances tagged StigPlatform = EL8 | EL9.
#    Includes boot-fips-wrapper.sh pre/post for EL8 FIPS boot repair.
#
# 2. Amazon Linux 2023 STIG Enforcement:
#    Uses AWS-RunShellScript to run AL2023's native STIG script.
#    Targets instances tagged StigPlatform = AL2023.
#
# 3. SSM Agent Update:
#    Uses AWS-UpdateSSMAgent to keep the agent current.
#    Runs daily before maintenance windows.
#
# 4. Windows Server STIG Enforcement (2016/2019/2022):
#    Uses AWS-ApplyAnsiblePlaybooks with per-version playbooks.
#    Targets instances tagged StigPlatform = Win2016 | Win2019 | Win2022.
#
# All associations are gated by their respective enable_* variables.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. EL (RHEL/OL/CentOS) STIG Enforcement via Ansible Lockdown
# -----------------------------------------------------------------------------
# Uses the AWS-ApplyAnsiblePlaybook document to apply the Ansible Lockdown
# STIG role in ENFORCE mode (Check = False). The playbook package must be
# uploaded to the S3 bucket at the configured ansible_s3_key path.
#
# The package's site.yml auto-detects the OS (EL8 vs EL9) and applies the
# correct role. For EL8, pre/post tasks run boot-fips-wrapper.sh to repair
# FIPS boot integrity after the RHEL8-STIG role templates /etc/default/grub.
#
# Targets instances tagged: StigPlatform = EL8 | EL9
# -----------------------------------------------------------------------------

resource "aws_ssm_association" "stig_enforce_el" {
  count = var.enable_stig_enforcement && var.enable_state_manager ? 1 : 0

  name                = "AWS-ApplyAnsiblePlaybooks"
  association_name    = "${var.name_prefix}-stig-enforce-el"
  schedule_expression = var.stig_enforcement_schedule
  max_concurrency     = var.patch_max_concurrency
  max_errors          = var.patch_max_errors

  targets {
    key    = "tag:StigPlatform"
    values = ["EL8", "EL9"]
  }

  parameters = {
    SourceType          = "S3"
    SourceInfo          = jsonencode({ path = "https://s3.amazonaws.com/${aws_s3_bucket.ssm.id}/${var.ansible_s3_key}" })
    PlaybookFile        = "site.yml"
    ExtraVariables      = local.el_extra_vars
    Check               = "False"
    InstallDependencies = "True"
    Verbose             = "-v"
    TimeoutSeconds      = tostring(var.ansible_timeout)
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm.id
    s3_key_prefix  = "ssm-output/stig-enforce-el"
  }
}

# -----------------------------------------------------------------------------
# 2. Amazon Linux 2023 STIG Enforcement via Shell Script
# -----------------------------------------------------------------------------
# AL2023 does not use the Ansible Lockdown playbooks. Instead it has its own
# STIG-hardening script. This association runs it via AWS-RunShellScript.
#
# Targets instances with BOTH:
#   - StigManaged = true (or configured target tag)
#   - StigPlatform = AL2023
# -----------------------------------------------------------------------------

resource "aws_ssm_association" "stig_enforce_al2023" {
  count = var.enable_stig_enforcement && var.enable_state_manager ? 1 : 0

  name                = "AWS-RunShellScript"
  association_name    = "${var.name_prefix}-stig-enforce-al2023"
  schedule_expression = var.stig_enforcement_schedule
  max_concurrency     = var.patch_max_concurrency
  max_errors          = var.patch_max_errors

  targets {
    key    = "tag:StigPlatform"
    values = ["AL2023"]
  }

  parameters = {
    commands = jsonencode([
      "set -eu",
      "WORK_DIR=$(mktemp -d)",
      "trap 'rm -rf \"$WORK_DIR\"' EXIT",
      "aws s3 cp s3://${aws_s3_bucket.ssm.id}/${var.stig_al2023_s3_key} \"$WORK_DIR/stig-package.zip\"",
      "cd \"$WORK_DIR\"",
      "unzip -q stig-package.zip",
      "chmod +x apply-stig.sh",
      "bash apply-stig.sh"
    ])
    executionTimeout = "3600"
    workingDirectory = "/tmp"
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm.id
    s3_key_prefix  = "ssm-output/stig-enforce-al2023"
  }
}

# -----------------------------------------------------------------------------
# 3. SSM Agent Auto-Update
# -----------------------------------------------------------------------------
# Keeps the SSM agent up to date on all STIG-managed instances.
# Runs daily (default: 3AM UTC) before the patch maintenance window.
# Uses the built-in AWS-UpdateSSMAgent document.
# -----------------------------------------------------------------------------

resource "aws_ssm_association" "ssm_agent_update" {
  count = var.enable_ssm_agent_update && var.enable_state_manager ? 1 : 0

  name                = "AWS-UpdateSSMAgent"
  association_name    = "${var.name_prefix}-ssm-agent-update"
  schedule_expression = var.ssm_agent_update_schedule
  max_concurrency     = "50%"
  max_errors          = "25%"

  targets {
    key    = "InstanceIds"
    values = ["*"]
  }
}

# -----------------------------------------------------------------------------
# 4. Windows Server STIG Enforcement via Ansible Lockdown
# -----------------------------------------------------------------------------
# Per-version associations using AWS-ApplyAnsiblePlaybooks to enforce
# Windows Server STIG hardening. Each version has a separate playbook file
# but all share the same S3 package and combined extra variables.
#
# WinRM/Packer-specific vars (winrm_password, ansible_port, etc.) are
# omitted — SSM runs Ansible locally on the instance, not via WinRM.
#
# Targets instances by tag: StigPlatform = Win2016 | Win2019 | Win2022
# -----------------------------------------------------------------------------

locals {
  windows_stig_versions = var.enable_stig_enforcement && var.enable_state_manager ? {
    win2016 = {
      tag_value     = "Win2016"
      playbook_file = "windows-2016-stig-playbook.yml"
    }
    win2019 = {
      tag_value     = "Win2019"
      playbook_file = "windows-2019-stig-playbook.yml"
    }
    win2022 = {
      tag_value     = "Win2022"
      playbook_file = "windows-2022-stig-playbook.yml"
    }
  } : {}
}

resource "aws_ssm_association" "stig_enforce_windows" {
  for_each = local.windows_stig_versions

  name                = "AWS-ApplyAnsiblePlaybooks"
  association_name    = "${var.name_prefix}-stig-enforce-${each.key}"
  schedule_expression = var.stig_enforcement_schedule
  max_concurrency     = var.patch_max_concurrency
  max_errors          = var.patch_max_errors

  targets {
    key    = "tag:StigPlatform"
    values = [each.value.tag_value]
  }

  parameters = {
    SourceType          = "S3"
    SourceInfo          = jsonencode({ path = "https://s3.amazonaws.com/${aws_s3_bucket.ssm.id}/${var.windows_stig_s3_key}" })
    PlaybookFile        = each.value.playbook_file
    ExtraVariables      = local.windows_extra_vars
    Check               = "False"
    InstallDependencies = "True"
    Verbose             = "-v"
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm.id
    s3_key_prefix  = "ssm-output/stig-enforce-${each.key}"
  }
}
