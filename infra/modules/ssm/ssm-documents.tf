# =============================================================================
# SSM Infrastructure Module — SSM Documents
# =============================================================================
# Custom SSM documents for Chimera-specific operations:
#
# 1. OpenSCAP STIG Scan: Runs oscap xccdf eval with configurable profile
#    and data stream, uploads results to S3. Works on both RHEL 8/9 and
#    Oracle Linux 8/9.
#
# 2. Windows STIG Enforce: Wraps the AWS-managed AWSEC2-ConfigureSTIG
#    document, then restores the built-in admin rename (SID-500 → maintuser).
#    AWSEC2-ConfigureSTIG resets the NewAdministratorName Local Security
#    Policy, undoing the rename applied during the AMI build.
#
# 3. Session Manager Preferences: Configures Session Manager with KMS
#    encryption, S3/CloudWatch logging, and STIG-aligned idle timeout.
# =============================================================================

resource "aws_ssm_document" "oscap_scan" {
  name            = "${var.name_prefix}-RunOpenSCAPScan"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Run OpenSCAP STIG compliance scan and upload results to S3"
    parameters = {
      Profile = {
        type        = "String"
        description = "OpenSCAP XCCDF profile to evaluate"
        default     = var.oscap_profile
      }
      S3Bucket = {
        type        = "String"
        description = "S3 bucket for results upload"
        default     = aws_s3_bucket.ssm.id
      }
      S3KeyPrefix = {
        type        = "String"
        description = "S3 key prefix for results"
        default     = "oscap-results"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "RunOpenSCAPScan"
        precondition = {
          StringEquals = ["platformType", "Linux"]
        }
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "",
            "PROFILE='{{ Profile }}'",
            "S3_BUCKET='{{ S3Bucket }}'",
            "S3_PREFIX='{{ S3KeyPrefix }}'",
            "INSTANCE_ID=$(ec2-metadata -i 2>/dev/null | awk '{print $2}' || { TOKEN=$(curl -sf -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600') && curl -sf -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/instance-id; })",
            "TIMESTAMP=$(date +%Y%m%d-%H%M%S)",
            "RESULTS_DIR=$(mktemp -d)",
            "",
            "echo \"=== OpenSCAP STIG Compliance Scan ===\"",
            "echo \"Instance: $INSTANCE_ID\"",
            "echo \"Profile:  $PROFILE\"",
            "echo \"Time:     $TIMESTAMP\"",
            "",
            "# Verify OpenSCAP is installed (should be pre-installed on Chimera AMIs)",
            "if ! command -v oscap &>/dev/null; then",
            "  echo 'WARN: OpenSCAP not installed. Attempting install (requires repo access)...'",
            "  yum install -y openscap-scanner scap-security-guide 2>/dev/null || dnf install -y openscap-scanner scap-security-guide || {",
            "    echo 'ERROR: Failed to install OpenSCAP. In air-gapped environments, openscap-scanner and scap-security-guide must be pre-installed on the AMI.'",
            "    exit 1",
            "  }",
            "fi",
            "",
            "# Determine the correct data stream",
            "SCAP_DS=''",
            "if [ -f /etc/os-release ]; then",
            "  . /etc/os-release",
            "  case \"$ID\" in",
            "    rhel|centos)",
            "      case \"$VERSION_ID\" in",
            "        9*) SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml ;;",
            "        8*) SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-rhel8-ds.xml ;;",
            "      esac",
            "      ;;",
            "    ol)",
            "      case \"$VERSION_ID\" in",
            "        9*) SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-ol9-ds.xml ;;",
            "        8*) SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-ol8-ds.xml ;;",
            "      esac",
            "      ;;",
            "    amzn)",
            "      echo 'WARN: No official DISA STIG benchmark for Amazon Linux. Skipping.'",
            "      echo '{\"scan_skipped\": true, \"reason\": \"No DISA AL2023 STIG benchmark\"}' > $RESULTS_DIR/scan-summary.json",
            "      aws s3 cp $RESULTS_DIR/scan-summary.json s3://$S3_BUCKET/$S3_PREFIX/$INSTANCE_ID/$TIMESTAMP/scan-summary.json",
            "      exit 0",
            "      ;;",
            "    *)",
            "      echo \"ERROR: Unsupported OS: $ID\"",
            "      exit 1",
            "      ;;",
            "  esac",
            "fi",
            "",
            "if [ ! -f \"$SCAP_DS\" ]; then",
            "  echo \"ERROR: SCAP data stream not found: $SCAP_DS\"",
            "  exit 1",
            "fi",
            "",
            "echo \"Data stream: $SCAP_DS\"",
            "",
            "# Run the scan",
            "oscap xccdf eval \\",
            "  --profile \"$PROFILE\" \\",
            "  --results \"$RESULTS_DIR/oscap-results.xml\" \\",
            "  --report \"$RESULTS_DIR/oscap-report.html\" \\",
            "  \"$SCAP_DS\" || true  # oscap returns non-zero for any non-pass findings",
            "",
            "# Generate machine-readable summary",
            "PASS=$(grep -c 'result=\"pass\"' $RESULTS_DIR/oscap-results.xml 2>/dev/null) || true",
            "FAIL=$(grep -c 'result=\"fail\"' $RESULTS_DIR/oscap-results.xml 2>/dev/null) || true",
            "NOTAPPLICABLE=$(grep -c 'result=\"notapplicable\"' $RESULTS_DIR/oscap-results.xml 2>/dev/null) || true",
            "PASS=$${PASS:-0}; FAIL=$${FAIL:-0}; NOTAPPLICABLE=$${NOTAPPLICABLE:-0}",
            "TOTAL=$((PASS + FAIL + NOTAPPLICABLE))",
            "",
            "if [ $((PASS + FAIL)) -gt 0 ]; then",
            "  SCORE=$(( PASS * 100 / (PASS + FAIL) ))",
            "else",
            "  SCORE=0",
            "fi",
            "",
            "cat > $RESULTS_DIR/scan-summary.json <<SUMEOF",
            "{",
            "  \"instance_id\": \"$INSTANCE_ID\",",
            "  \"timestamp\": \"$TIMESTAMP\",",
            "  \"profile\": \"$PROFILE\",",
            "  \"data_stream\": \"$SCAP_DS\",",
            "  \"results\": {",
            "    \"pass\": $PASS,",
            "    \"fail\": $FAIL,",
            "    \"not_applicable\": $NOTAPPLICABLE,",
            "    \"total\": $TOTAL,",
            "    \"score_percent\": $SCORE",
            "  }",
            "}",
            "SUMEOF",
            "",
            "echo ''",
            "echo '=== Scan Results ==='",
            "cat $RESULTS_DIR/scan-summary.json",
            "",
            "# Upload results to S3",
            "echo ''",
            "echo 'Uploading results to S3...'",
            "aws s3 cp $RESULTS_DIR/oscap-results.xml s3://$S3_BUCKET/$S3_PREFIX/$INSTANCE_ID/$TIMESTAMP/oscap-results.xml",
            "aws s3 cp $RESULTS_DIR/oscap-report.html s3://$S3_BUCKET/$S3_PREFIX/$INSTANCE_ID/$TIMESTAMP/oscap-report.html",
            "aws s3 cp $RESULTS_DIR/scan-summary.json s3://$S3_BUCKET/$S3_PREFIX/$INSTANCE_ID/$TIMESTAMP/scan-summary.json",
            "",
            "echo 'Results uploaded to s3://'$S3_BUCKET'/'$S3_PREFIX'/'$INSTANCE_ID'/'$TIMESTAMP'/'",
            "",
            "# Cleanup",
            "rm -rf $RESULTS_DIR"
          ]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-RunOpenSCAPScan"
  })
}

# -----------------------------------------------------------------------------
# 2. Windows STIG Enforce (AWSEC2-ConfigureSTIG + Admin Rename)
# -----------------------------------------------------------------------------
# Wraps the AWS-managed AWSEC2-ConfigureSTIG document in a two-step Command
# document:
#
#   Step 1 — aws:runDocument → AWSEC2-ConfigureSTIG
#     Applies DISA STIG hardening (OS, .NET, Firewall, Defender, etc.).
#     Downloads STIG scripts from AWS's regional S3 buckets.
#
#   Step 2 — aws:runPowerShellScript → Restore admin rename
#     AWSEC2-ConfigureSTIG resets the Local Security Policy setting
#     "Accounts: Rename administrator account", which reverts the AMI
#     build's rename of the SID-500 account from Administrator → maintuser.
#     This step re-applies the rename via both secedit (persistent policy)
#     and Rename-LocalUser (immediate SAM update).
#
# This ensures the built-in admin stays named "maintuser" (or whatever
# AdminUsername is set to) across STIG enforcement cycles.
# -----------------------------------------------------------------------------

resource "aws_ssm_document" "windows_stig_enforce" {
  name            = "${var.name_prefix}-WindowsSTIGEnforce"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Apply AWSEC2-ConfigureSTIG then restore built-in admin rename (SID-500 to maintuser)"
    parameters = {
      Level = {
        type          = "String"
        description   = "STIG severity level"
        default       = "High"
        allowedValues = ["High", "Medium", "Low"]
      }
      AdminUsername = {
        type        = "String"
        description = "Name for the built-in Administrator account (SID-500)"
        default     = "maintuser"
      }
    }
    mainSteps = [
      {
        action = "aws:runDocument"
        name   = "ApplyAWSConfigureSTIG"
        onFailure = "Continue"
        precondition = {
          StringEquals = ["platformType", "Windows"]
        }
        inputs = {
          documentType = "SSMDocument"
          documentPath = "AWSEC2-ConfigureSTIG"
          documentParameters = jsonencode({
            Level = "{{ Level }}"
          })
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "RestoreAdminRename"
        precondition = {
          StringEquals = ["platformType", "Windows"]
        }
        inputs = {
          timeoutSeconds = "120"
          runCommand = [
            "$adminName = '{{ AdminUsername }}'",
            "",
            "# Find built-in Administrator (SID-500)",
            "$builtinAdmin = Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' }",
            "",
            "if (-not $builtinAdmin) {",
            "    Write-Warning 'Could not find built-in administrator account (SID ending in -500)'",
            "    exit 0",
            "}",
            "",
            "$currentName = $builtinAdmin.Name",
            "Write-Output \"Current built-in admin name: $currentName\"",
            "",
            "# Set via Local Security Policy (secedit) to persist across policy refreshes",
            "$tempDir = Join-Path $env:TEMP 'stig-admin-fixup'",
            "$null = New-Item -ItemType Directory -Path $tempDir -Force",
            "$cfgFile = Join-Path $tempDir 'secpol.cfg'",
            "$dbFile = Join-Path $tempDir 'secpol.sdb'",
            "",
            "# Export current security policy",
            "secedit /export /cfg $cfgFile /quiet",
            "",
            "# Update the NewAdministratorName setting",
            "$content = Get-Content $cfgFile -Raw",
            "$pattern = 'NewAdministratorName\\s*=\\s*\"[^\"]*\"'",
            "$replacement = 'NewAdministratorName = \"' + $adminName + '\"'",
            "$content = [regex]::Replace($content, $pattern, $replacement)",
            "$content | Set-Content $cfgFile",
            "",
            "# Apply the updated policy",
            "secedit /configure /db $dbFile /cfg $cfgFile /areas SECURITYPOLICY /quiet",
            "",
            "# Direct immediate rename",
            "if ($currentName -ne $adminName) {",
            "    Rename-LocalUser -SID $builtinAdmin.SID -NewName $adminName",
            "    Write-Output \"Renamed '$currentName' to '$adminName'\"",
            "} else {",
            "    Write-Output \"Already named '$adminName' - no action needed\"",
            "}",
            "",
            "# Cleanup",
            "Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue",
            "Write-Output \"Admin account secured as '$adminName'\""
          ]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-WindowsSTIGEnforce"
  })
}

# -----------------------------------------------------------------------------
# 3. Session Manager Preferences
# -----------------------------------------------------------------------------
# Configures Session Manager with:
#   - KMS encryption for session data (STIG V-72057 / AC-17)
#   - S3 logging of session output
#   - CloudWatch logging
#   - 20-minute idle timeout (STIG-aligned: AC-12 / SC-10)
#   - Shell profile banner
# -----------------------------------------------------------------------------

resource "aws_ssm_document" "session_manager_prefs" {
  count = var.enable_session_manager ? 1 : 0

  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences for ${var.name_prefix}"
    sessionType   = "Standard_Stream"
    inputs = {
      kmsKeyId                    = local.kms_enabled ? local.effective_kms_key_arn : ""
      s3BucketName                = aws_s3_bucket.ssm.id
      s3KeyPrefix                 = "session-logs"
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.ssm.name
      cloudWatchEncryptionEnabled = local.kms_enabled
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = tostring(var.session_idle_timeout)
      maxSessionDuration          = ""
      runAsEnabled                = false
      shellProfile = {
        linux   = "echo '*** STIG-hardened instance — Session Manager ***'; echo ''"
        windows = ""
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-session-manager-prefs"
  })
}
