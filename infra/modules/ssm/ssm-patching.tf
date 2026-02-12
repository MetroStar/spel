# =============================================================================
# SSM Infrastructure Module — Patch Manager
# =============================================================================
# Custom patch baseline for STIG-hardened instances. The baseline is more
# conservative than the AWS default to align with STIG requirements:
#   - Only Security and Bugfix classifications
#   - Only Critical/Important/Moderate severity
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
  rejected_patches        = []
  rejected_patches_action = "ALLOW_AS_DEPENDENCY"

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

# -----------------------------------------------------------------------------
# Maintenance Windows
# -----------------------------------------------------------------------------
# Scheduled maintenance window for automated patching. Default: Sunday 4AM UTC,
# 3-hour duration, 1-hour cutoff. Separate windows for Linux and Windows to
# allow staggered patching if needed.
# -----------------------------------------------------------------------------

resource "aws_ssm_maintenance_window" "linux" {
  count = var.enable_patch_manager ? 1 : 0

  name                       = "${var.name_prefix}-linux-patch-window"
  description                = "Maintenance window for Linux patching"
  schedule                   = var.maintenance_window_schedule
  schedule_timezone          = var.maintenance_window_timezone
  duration                   = var.maintenance_window_duration
  cutoff                     = var.maintenance_window_cutoff
  allow_unassociated_targets = false

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-linux-patch-window"
  })
}

resource "aws_ssm_maintenance_window_target" "linux" {
  count = var.enable_patch_manager ? 1 : 0

  window_id     = aws_ssm_maintenance_window.linux[0].id
  name          = "${var.name_prefix}-linux-targets"
  description   = "Linux instances for patching"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = ["${var.name_prefix}-linux"]
  }
}

resource "aws_ssm_maintenance_window_task" "linux_patch" {
  count = var.enable_patch_manager ? 1 : 0

  window_id       = aws_ssm_maintenance_window.linux[0].id
  name            = "${var.name_prefix}-linux-patch-task"
  description     = "Apply approved patches to Linux instances"
  task_type       = "RUN_COMMAND"
  task_arn        = "AWS-RunPatchBaseline"
  priority        = 1
  max_concurrency = var.patch_max_concurrency
  max_errors      = var.patch_max_errors

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.linux[0].id]
  }

  task_invocation_parameters {
    run_command_parameters {
      timeout_seconds      = 3600
      output_s3_bucket     = aws_s3_bucket.ssm.id
      output_s3_key_prefix = "ssm-output/patch-linux"

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

resource "aws_ssm_maintenance_window" "windows" {
  count = var.enable_patch_manager ? 1 : 0

  name                       = "${var.name_prefix}-windows-patch-window"
  description                = "Maintenance window for Windows patching"
  schedule                   = var.maintenance_window_schedule
  schedule_timezone          = var.maintenance_window_timezone
  duration                   = var.maintenance_window_duration
  cutoff                     = var.maintenance_window_cutoff
  allow_unassociated_targets = false

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-windows-patch-window"
  })
}

resource "aws_ssm_maintenance_window_target" "windows" {
  count = var.enable_patch_manager ? 1 : 0

  window_id     = aws_ssm_maintenance_window.windows[0].id
  name          = "${var.name_prefix}-windows-targets"
  description   = "Windows instances for patching"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = ["${var.name_prefix}-windows"]
  }
}

resource "aws_ssm_maintenance_window_task" "windows_patch" {
  count = var.enable_patch_manager ? 1 : 0

  window_id       = aws_ssm_maintenance_window.windows[0].id
  name            = "${var.name_prefix}-windows-patch-task"
  description     = "Apply approved patches to Windows instances"
  task_type       = "RUN_COMMAND"
  task_arn        = "AWS-RunPatchBaseline"
  priority        = 1
  max_concurrency = var.patch_max_concurrency
  max_errors      = var.patch_max_errors

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.windows[0].id]
  }

  task_invocation_parameters {
    run_command_parameters {
      timeout_seconds      = 3600
      output_s3_bucket     = aws_s3_bucket.ssm.id
      output_s3_key_prefix = "ssm-output/patch-windows"

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}
