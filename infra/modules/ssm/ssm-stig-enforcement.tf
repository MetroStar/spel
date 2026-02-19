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
#    Uses the AWS-managed AWSEC2-ConfigureSTIG SSM document.
#    Auto-detects OS, downloads STIG scripts from AWS S3 buckets.
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
    SourceInfo          = jsonencode({ path = "https://${aws_s3_bucket.ssm.bucket_regional_domain_name}/${var.ansible_s3_key}" })
    PlaybookFile        = "site.yml"
    ExtraVariables      = local.el_extra_vars
    Check               = "False"
    InstallDependencies = var.install_dependencies ? "True" : "False"
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
    commands = join("\n", [
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
# 4. Windows Server STIG Enforcement via AWSEC2-ConfigureSTIG
# -----------------------------------------------------------------------------
# Uses the AWS-managed AWSEC2-ConfigureSTIG SSM Command document to apply
# STIG hardening to Windows Server instances. This document:
#   - Auto-detects the Windows version and applies appropriate settings
#   - Downloads STIG scripts from AWS's regional S3 buckets
#     (s3://aws-windows-downloads-<region>/STIG/Windows/Latest/)
#   - Covers: OS, .NET Framework, Windows Firewall, IE11, Edge, Defender
#   - Updated quarterly by AWS with latest STIG versions
#   - No custom code, Python, or Ansible required on the instance
#
# This is the same mechanism used for AL2023 Linux STIG (LinuxAWSConfigureSTIG)
# but for Windows. Requires s3:GetObject on aws-windows-downloads* buckets
# (added in iam.tf).
#
# Targets instances by tag: StigPlatform = Win2016 | Win2019 | Win2022
# -----------------------------------------------------------------------------

resource "aws_ssm_association" "stig_enforce_windows" {
  count = var.enable_stig_enforcement && var.enable_state_manager ? 1 : 0

  name                = "AWSEC2-ConfigureSTIG"
  association_name    = "${var.name_prefix}-stig-enforce-windows"
  schedule_expression = var.stig_enforcement_schedule
  max_concurrency     = var.patch_max_concurrency
  max_errors          = var.patch_max_errors

  targets {
    key    = "tag:StigPlatform"
    values = ["Win2016", "Win2019", "Win2022"]
  }

  parameters = {
    Level = var.windows_stig_level
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm.id
    s3_key_prefix  = "ssm-output/stig-enforce-windows"
  }
}
