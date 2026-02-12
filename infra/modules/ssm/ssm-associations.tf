# =============================================================================
# SSM Infrastructure Module — State Manager Associations (Compliance Verification)
# =============================================================================
# Scheduled SSM associations for ongoing compliance VERIFICATION:
#
# 1. Ansible STIG check-mode: Runs Ansible playbook in --check mode to
#    verify continued compliance without modifying the instance.
# 2. OpenSCAP scan: Runs the custom SSM document on a schedule.
# 3. Software Inventory: Collects installed software and configuration data.
#
# For STIG ENFORCEMENT (actually applying hardening), see:
#   ssm-stig-enforcement.tf
#
# Associations target instances by tag (default: StigManaged=true).
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Ansible STIG Compliance Check (check-mode only)
# -----------------------------------------------------------------------------

resource "aws_ssm_association" "ansible_stig_check" {
  count = var.enable_state_manager ? 1 : 0

  name                = "AWS-ApplyAnsiblePlaybooks"
  association_name    = "${var.name_prefix}-stig-ansible-check"
  schedule_expression = var.ansible_schedule

  targets {
    key    = "tag:${var.target_tag_key}"
    values = [var.target_tag_value]
  }

  parameters = {
    SourceType          = "S3"
    SourceInfo          = jsonencode({ path = "https://s3.amazonaws.com/${aws_s3_bucket.ssm.id}/${var.ansible_s3_key}" })
    PlaybookFile        = "site.yml"
    ExtraVariables      = jsonencode(var.stig_extra_variables)
    Check               = "True"
    InstallDependencies = "True"
    Verbose             = "-v"
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm.id
    s3_key_prefix  = "ssm-output/ansible-stig-check"
  }
}

# -----------------------------------------------------------------------------
# 2. OpenSCAP Scheduled Scan
# -----------------------------------------------------------------------------

resource "aws_ssm_association" "oscap_scan" {
  count = var.enable_state_manager ? 1 : 0

  name                = aws_ssm_document.oscap_scan.name
  association_name    = "${var.name_prefix}-oscap-scheduled-scan"
  schedule_expression = var.oscap_schedule

  targets {
    key    = "tag:${var.target_tag_key}"
    values = [var.target_tag_value]
  }

  parameters = {
    Profile     = var.oscap_profile
    S3Bucket    = aws_s3_bucket.ssm.id
    S3KeyPrefix = "oscap-results"
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ssm.id
    s3_key_prefix  = "ssm-output/oscap-scan"
  }
}

# -----------------------------------------------------------------------------
# 3. Software Inventory Collection
# -----------------------------------------------------------------------------

resource "aws_ssm_association" "inventory" {
  count = var.enable_inventory ? 1 : 0

  name                = "AWS-GatherSoftwareInventory"
  association_name    = "${var.name_prefix}-software-inventory"
  schedule_expression = "rate(12 hours)"

  targets {
    key    = "tag:${var.target_tag_key}"
    values = [var.target_tag_value]
  }

  parameters = {
    applications                = "Enabled"
    awsComponents               = "Enabled"
    customInventory             = "Enabled"
    instanceDetailedInformation = "Enabled"
    networkConfig               = "Enabled"
    services                    = "Enabled"
    windowsRoles                = "Enabled"
    windowsUpdates              = "Enabled"
  }
}
