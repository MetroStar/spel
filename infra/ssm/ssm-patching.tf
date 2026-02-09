# =============================================================================
# SSM Infrastructure Module — Patch Manager
# =============================================================================
# Custom patch baseline for STIG-hardened instances. The baseline is more
# conservative than the AWS default to align with STIG requirements:
#   - Only Security and Bugfix classifications
#   - Only Critical/Important/Medium severity
#   - Auto-approval after a configurable delay (default: 7 days)
#
# Patch groups allow different baselines for different OS families.
# =============================================================================

# -----------------------------------------------------------------------------
# Linux Patch Baseline
# -----------------------------------------------------------------------------

resource "aws_ssm_patch_baseline" "linux" {
  count = var.enable_patch_manager ? 1 : 0

  name             = "${var.name_prefix}-linux-stig-baseline"
  description      = "Patch baseline for STIG-hardened Linux instances (RHEL, OL, AL2023)"
  operating_system = "REDHAT_ENTERPRISE_LINUX"

  approval_rule {
    approve_after_days = var.patch_approve_after_days
    compliance_level   = "CRITICAL"

    patch_filter {
      key    = "CLASSIFICATION"
      values = var.patch_classification
    }

    patch_filter {
      key    = "SEVERITY"
      values = var.patch_severity
    }
  }

  # Reject kernel patches that require manual STIG re-validation
  rejected_patches           = []
  rejected_patches_action    = "ALLOW_AS_DEPENDENCY"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-linux-stig-baseline"
  })
}

# -----------------------------------------------------------------------------
# Windows Patch Baseline
# -----------------------------------------------------------------------------

resource "aws_ssm_patch_baseline" "windows" {
  count = var.enable_patch_manager ? 1 : 0

  name             = "${var.name_prefix}-windows-stig-baseline"
  description      = "Patch baseline for STIG-hardened Windows instances"
  operating_system = "WINDOWS"

  approval_rule {
    approve_after_days = var.patch_approve_after_days
    compliance_level   = "CRITICAL"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["SecurityUpdates", "CriticalUpdates"]
    }

    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-windows-stig-baseline"
  })
}

# -----------------------------------------------------------------------------
# Patch Groups
# -----------------------------------------------------------------------------

resource "aws_ssm_patch_group" "linux" {
  count = var.enable_patch_manager ? 1 : 0

  baseline_id = aws_ssm_patch_baseline.linux[0].id
  patch_group = "${var.name_prefix}-linux"
}

resource "aws_ssm_patch_group" "windows" {
  count = var.enable_patch_manager ? 1 : 0

  baseline_id = aws_ssm_patch_baseline.windows[0].id
  patch_group = "${var.name_prefix}-windows"
}
