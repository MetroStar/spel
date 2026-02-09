# =============================================================================
# SSM Infrastructure Module — SSM Documents
# =============================================================================
# Custom SSM documents for SPEL-specific operations:
#
# 1. OpenSCAP STIG Scan: Runs oscap xccdf eval with configurable profile
#    and data stream, uploads results to S3. Works on both RHEL 8/9 and
#    Oracle Linux 8/9.
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
            "INSTANCE_ID=$(ec2-metadata -i 2>/dev/null | awk '{print $2}' || curl -s http://169.254.169.254/latest/meta-data/instance-id)",
            "TIMESTAMP=$(date +%Y%m%d-%H%M%S)",
            "RESULTS_DIR=$(mktemp -d)",
            "",
            "echo \"=== OpenSCAP STIG Compliance Scan ===\"",
            "echo \"Instance: $INSTANCE_ID\"",
            "echo \"Profile:  $PROFILE\"",
            "echo \"Time:     $TIMESTAMP\"",
            "",
            "# Install OpenSCAP if not present",
            "if ! command -v oscap &>/dev/null; then",
            "  echo 'Installing OpenSCAP scanner...'",
            "  yum install -y openscap-scanner scap-security-guide 2>/dev/null || dnf install -y openscap-scanner scap-security-guide",
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
            "PASS=$(grep -c 'result=\"pass\"' $RESULTS_DIR/oscap-results.xml 2>/dev/null || echo 0)",
            "FAIL=$(grep -c 'result=\"fail\"' $RESULTS_DIR/oscap-results.xml 2>/dev/null || echo 0)",
            "NOTAPPLICABLE=$(grep -c 'result=\"notapplicable\"' $RESULTS_DIR/oscap-results.xml 2>/dev/null || echo 0)",
            "TOTAL=$((PASS + FAIL + NOTAPPLICABLE))",
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
            "    \"score_percent\": $(echo \"scale=1; $PASS * 100 / ($PASS + $FAIL + 1)\" | bc 2>/dev/null || echo 0)",
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
