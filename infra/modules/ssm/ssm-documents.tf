# =============================================================================
# SSM Infrastructure Module — SSM Documents
# =============================================================================
# Custom SSM documents for SPEL-specific operations:
#
# 1. OpenSCAP STIG Scan: Runs oscap xccdf eval with configurable profile
#    and data stream, uploads results to S3. Works on both RHEL 8/9 and
#    Oracle Linux 8/9.
#
# 2. Session Manager Preferences: Configures Session Manager with KMS
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
            "# Verify OpenSCAP is installed (should be pre-installed on SPEL AMIs)",
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
# 2. Windows Ansible Playbook Runner
# -----------------------------------------------------------------------------
# Custom SSM document that installs Ansible on Windows via pip and runs a
# playbook from an S3 package. Required because the AWS-managed
# AWS-ApplyAnsiblePlaybooks document only supports Linux (its steps use
# aws:runShellScript which has a platformType=Linux precondition).
#
# Steps:
#   1. Install/upgrade pip and Ansible via PowerShell
#   2. Download and extract the playbook package from S3
#   3. Run ansible-playbook with configurable extra vars and check mode
# -----------------------------------------------------------------------------

resource "aws_ssm_document" "windows_ansible" {
  name            = "${var.name_prefix}-RunWindowsAnsiblePlaybook"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install Ansible and run a playbook on Windows from an S3 package"
    parameters = {
      SourceUrl = {
        type        = "String"
        description = "S3 URL of the playbook .zip package"
      }
      PlaybookFile = {
        type        = "String"
        description = "Relative path to the playbook file inside the package"
        default     = "site.yml"
      }
      ExtraVariables = {
        type        = "String"
        description = "Space-separated key=value extra variables"
        default     = ""
      }
      Check = {
        type          = "String"
        description   = "Run in check mode (True/False)"
        default       = "False"
        allowedValues = ["True", "False"]
      }
      Verbose = {
        type        = "String"
        description = "Ansible verbosity flag (-v, -vv, etc.)"
        default     = "-v"
      }
      TimeoutSeconds = {
        type        = "String"
        description = "Execution timeout in seconds"
        default     = "3600"
      }
    }
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "RunWindowsAnsiblePlaybook"
        precondition = {
          StringEquals = ["platformType", "Windows"]
        }
        inputs = {
          timeoutSeconds = "{{ TimeoutSeconds }}"
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "",
            "# ----- Helper: ensure pip + ansible are installed -----",
            "Write-Host '=== Installing/upgrading Ansible ==='",
            "if (-not (Get-Command python -ErrorAction SilentlyContinue)) {",
            "  Write-Host 'ERROR: Python is not installed on this instance.'",
            "  exit 1",
            "}",
            "python -m pip install --upgrade pip 2>&1 | Write-Host",
            "python -m pip install --upgrade ansible-core pywinrm 2>&1 | Write-Host",
            "",
            "# Verify ansible-playbook is available",
            "$ansiblePath = (python -c \"import shutil; print(shutil.which('ansible-playbook') or '')\" 2>$null).Trim()",
            "if (-not $ansiblePath) {",
            "  # Try the Python Scripts directory directly",
            "  $scriptsDir = python -c \"import sys, os; print(os.path.join(sys.prefix, 'Scripts'))\"",
            "  $env:PATH = \"$scriptsDir;$env:PATH\"",
            "  $ansiblePath = (Get-Command ansible-playbook -ErrorAction SilentlyContinue).Source",
            "}",
            "if (-not $ansiblePath) {",
            "  Write-Host 'ERROR: ansible-playbook not found after pip install.'",
            "  exit 1",
            "}",
            "Write-Host \"  ansible-playbook: $ansiblePath\"",
            "& $ansiblePath --version | Select-Object -First 1 | Write-Host",
            "",
            "# ----- Download and extract playbook package from S3 -----",
            "Write-Host ''",
            "Write-Host '=== Downloading playbook package from S3 ==='",
            "$workDir = Join-Path $env:TEMP \"ansible-$(Get-Date -Format 'yyyyMMdd-HHmmss')\"",
            "New-Item -ItemType Directory -Force -Path $workDir | Out-Null",
            "$zipPath = Join-Path $workDir 'playbook.zip'",
            "",
            "# Parse S3 URL to bucket and key",
            "$sourceUrl = '{{ SourceUrl }}'",
            "if ($sourceUrl -match '^https://(.+?)\\.s3[.-].*?/(.*+)$') {",
            "  $bucket = $Matches[1]; $key = $Matches[2]",
            "} elseif ($sourceUrl -match '^s3://([^/]+)/(.+)$') {",
            "  $bucket = $Matches[1]; $key = $Matches[2]",
            "} else {",
            "  Write-Host \"ERROR: Cannot parse S3 URL: $sourceUrl\"",
            "  exit 1",
            "}",
            "",
            "aws s3 cp \"s3://$bucket/$key\" $zipPath 2>&1 | Write-Host",
            "if ($LASTEXITCODE -ne 0) { Write-Host 'ERROR: S3 download failed'; exit 1 }",
            "",
            "Expand-Archive -Path $zipPath -DestinationPath $workDir -Force",
            "Write-Host '  Package extracted.'",
            "",
            "# ----- Run the playbook -----",
            "Write-Host ''",
            "Write-Host '=== Running Ansible Playbook ==='",
            "$playbookPath = Join-Path $workDir '{{ PlaybookFile }}'",
            "if (-not (Test-Path $playbookPath)) {",
            "  Write-Host \"ERROR: Playbook not found: $playbookPath\"",
            "  exit 1",
            "}",
            "",
            "$ansibleArgs = @($playbookPath, '--connection', 'local', '-i', 'localhost,', '{{ Verbose }}')",
            "",
            "# Check mode",
            "if ('{{ Check }}' -eq 'True') {",
            "  $ansibleArgs += '--check'",
            "  Write-Host '  Mode: CHECK (dry-run, no changes)'",
            "} else {",
            "  Write-Host '  Mode: ENFORCE'",
            "}",
            "",
            "# Extra variables",
            "$extraVars = '{{ ExtraVariables }}'",
            "if ($extraVars) {",
            "  $ansibleArgs += @('--extra-vars', $extraVars)",
            "}",
            "",
            "Write-Host \"  Playbook: {{ PlaybookFile }}\"",
            "Write-Host \"  Args: $($ansibleArgs -join ' ')\"",
            "Write-Host ''",
            "",
            "& $ansiblePath @ansibleArgs",
            "$exitCode = $LASTEXITCODE",
            "",
            "# ----- Cleanup -----",
            "Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue",
            "",
            "if ($exitCode -ne 0) {",
            "  Write-Host \"Ansible playbook exited with code: $exitCode\"",
            "  exit $exitCode",
            "}",
            "",
            "Write-Host ''",
            "Write-Host '=== Playbook completed successfully ==='"
          ]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-RunWindowsAnsiblePlaybook"
  })
}

# -----------------------------------------------------------------------------
# 2. Session Manager Preferences
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
