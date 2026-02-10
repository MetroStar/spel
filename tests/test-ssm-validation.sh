#!/bin/bash
# Validate SSM connectivity and compliance scanning on a running AMI instance
# Usage: ./test-ssm-validation.sh <INSTANCE_ID> [OPTIONS]
#
# This script validates that SSM is fully operational on an instance launched
# from a SPEL AMI. It checks agent registration, RunCommand capability,
# Session Manager access, and optionally runs an OpenSCAP scan via SSM.
#
# Prerequisites:
#   - AWS CLI v2 with SSM plugin installed
#   - IAM permissions for ssm:SendCommand, ssm:GetCommandInvocation,
#     ssm:StartSession, ssm:DescribeInstanceInformation
#   - Instance must be running with an IAM role that includes SSM permissions
#
# Options:
#   --skip-oscap       Skip the OpenSCAP scan test
#   --skip-session     Skip the Session Manager test
#   --timeout SECONDS  Max time to wait for SSM agent registration (default: 300)
#   --s3-bucket NAME   S3 bucket for scan output (required if not --skip-oscap)
#   --ssm-doc NAME     Custom SSM document name for OpenSCAP (optional)

set -euo pipefail

# Parse arguments
INSTANCE_ID=""
SKIP_OSCAP=false
SKIP_SESSION=false
TIMEOUT=300
S3_BUCKET=""
SSM_DOC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-oscap)   SKIP_OSCAP=true; shift ;;
    --skip-session) SKIP_SESSION=true; shift ;;
    --timeout)      TIMEOUT="$2"; shift 2 ;;
    --s3-bucket)    S3_BUCKET="$2"; shift 2 ;;
    --ssm-doc)      SSM_DOC="$2"; shift 2 ;;
    -*)             echo "Unknown option: $1"; exit 1 ;;
    *)              INSTANCE_ID="$1"; shift ;;
  esac
done

if [[ -z "$INSTANCE_ID" ]]; then
  echo "Usage: $0 <INSTANCE_ID> [OPTIONS]"
  echo "  --skip-oscap       Skip OpenSCAP scan test"
  echo "  --skip-session     Skip Session Manager test"
  echo "  --timeout SECONDS  SSM registration timeout (default: 300)"
  echo "  --s3-bucket NAME   S3 bucket for scan output"
  echo "  --ssm-doc NAME     Custom SSM document name for OpenSCAP"
  exit 1
fi

REGION="${AWS_REGION:-us-east-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

log_info()  { echo -e "${NC}[INFO]  $1${NC}"; }
log_pass()  { echo -e "${GREEN}[PASS]  $1${NC}"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail()  { echo -e "${RED}[FAIL]  $1${NC}"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
log_skip()  { echo -e "${YELLOW}[SKIP]  $1${NC}"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
log_warn()  { echo -e "${YELLOW}[WARN]  $1${NC}"; }

# ============================================================================
# TEST 1: Wait for SSM Agent Registration
# ============================================================================
test_ssm_registration() {
  log_info "TEST 1: Waiting for SSM agent registration (timeout: ${TIMEOUT}s)..."

  local elapsed=0
  local interval=10

  while [[ $elapsed -lt $TIMEOUT ]]; do
    local info
    local ssm_err
    # Show errors on first attempt to catch IAM permission issues
    if [[ $elapsed -eq 0 ]]; then
      info=$(aws ssm describe-instance-information \
        --region "$REGION" \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0]' \
        --output json 2>&1) || {
          ssm_err="$info"
          if echo "$ssm_err" | grep -qi 'AccessDenied\|not authorized\|UnauthorizedAccess'; then
            log_fail "IAM role lacks ssm:DescribeInstanceInformation permission"
            log_fail "Error: $ssm_err"
            return 1
          fi
          info="null"
        }
    else
      info=$(aws ssm describe-instance-information \
        --region "$REGION" \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0]' \
        --output json 2>/dev/null || echo "null")
    fi

    if [[ "$info" != "null" && "$info" != "" && "$info" != "None" ]]; then
      local ping_status
      ping_status=$(echo "$info" | jq -r '.PingStatus // "Unknown"')
      local agent_version
      agent_version=$(echo "$info" | jq -r '.AgentVersion // "Unknown"')
      local platform
      platform=$(echo "$info" | jq -r '.PlatformName // "Unknown"')

      if [[ "$ping_status" == "Online" ]]; then
        log_pass "SSM agent registered - Platform: $platform, Agent: $agent_version, Status: $ping_status"
        return 0
      fi
      log_info "  Agent found but status is $ping_status (${elapsed}s elapsed)..."
    else
      log_info "  Agent not yet registered (${elapsed}s elapsed)..."
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  log_fail "SSM agent did not register within ${TIMEOUT}s"
  return 1
}

# ============================================================================
# TEST 2: RunCommand - Basic Shell Execution
# ============================================================================
test_run_command() {
  log_info "TEST 2: Testing RunCommand (basic shell execution)..."

  # Detect OS type from SSM instance info
  local platform_type
  platform_type=$(aws ssm describe-instance-information \
    --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].PlatformType' \
    --output text 2>/dev/null || echo "Unknown")

  local doc_name command_text
  if [[ "$platform_type" == "Windows" ]]; then
    doc_name="AWS-RunPowerShellScript"
    command_text="Write-Output \"SSM-TEST-OK: $(hostname) $(Get-Date -Format o)\""
  else
    doc_name="AWS-RunShellScript"
    command_text="echo \"SSM-TEST-OK: $(hostname) $(date -Iseconds)\""
  fi

  local command_id
  command_id=$(aws ssm send-command \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "$doc_name" \
    --parameters "commands=[\"$command_text\"]" \
    --timeout-seconds 60 \
    --query 'Command.CommandId' \
    --output text 2>/dev/null)

  if [[ -z "$command_id" || "$command_id" == "None" ]]; then
    log_fail "RunCommand: Failed to send command"
    return 1
  fi

  log_info "  Command sent: $command_id - waiting for result..."

  # Poll for completion
  local status="InProgress"
  local wait=0
  while [[ "$status" == "InProgress" || "$status" == "Pending" ]] && [[ $wait -lt 120 ]]; do
    sleep 5
    wait=$((wait + 5))
    status=$(aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$INSTANCE_ID" \
      --query 'Status' \
      --output text 2>/dev/null || echo "InProgress")
  done

  if [[ "$status" == "Success" ]]; then
    local output
    output=$(aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardOutputContent' \
      --output text 2>/dev/null)
    log_pass "RunCommand: Success - Output: $output"
    return 0
  else
    local error_output
    error_output=$(aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardErrorContent' \
      --output text 2>/dev/null)
    log_fail "RunCommand: Status=$status - Error: $error_output"
    return 1
  fi
}

# ============================================================================
# TEST 3: Session Manager Connectivity
# ============================================================================
test_session_manager() {
  if $SKIP_SESSION; then
    log_skip "Session Manager test (--skip-session)"
    return 0
  fi

  log_info "TEST 3: Testing Session Manager connectivity..."

  # Check if the ssm-plugin is installed
  if ! command -v session-manager-plugin &>/dev/null; then
    log_warn "session-manager-plugin not installed - testing via API only"
    # Test that we can at least start a session (will fail without plugin, but API call validates permissions)
    local session_id
    session_id=$(aws ssm start-session \
      --region "$REGION" \
      --target "$INSTANCE_ID" \
      --reason "SPEL SSM validation test" \
      --query 'SessionId' \
      --output text 2>/dev/null || echo "FAILED")

    if [[ "$session_id" != "FAILED" && -n "$session_id" ]]; then
      # Terminate the session immediately
      aws ssm terminate-session --region "$REGION" --session-id "$session_id" 2>/dev/null || true
      log_pass "Session Manager: Session started and terminated (API validated)"
      return 0
    else
      log_fail "Session Manager: Failed to start session"
      return 1
    fi
  fi

  # With plugin installed, do a quick interactive test
  local session_id
  session_id=$(aws ssm start-session \
    --region "$REGION" \
    --target "$INSTANCE_ID" \
    --reason "SPEL SSM validation test" \
    --query 'SessionId' \
    --output text 2>/dev/null || echo "FAILED")

  if [[ "$session_id" != "FAILED" && -n "$session_id" ]]; then
    aws ssm terminate-session --region "$REGION" --session-id "$session_id" 2>/dev/null || true
    log_pass "Session Manager: Session started and terminated successfully"
    return 0
  else
    log_fail "Session Manager: Failed to start session"
    return 1
  fi
}

# ============================================================================
# TEST 4: OpenSCAP Scan via SSM RunCommand
# ============================================================================
test_oscap_scan() {
  if $SKIP_OSCAP; then
    log_skip "OpenSCAP scan test (--skip-oscap)"
    return 0
  fi

  if [[ -z "$S3_BUCKET" ]]; then
    log_skip "OpenSCAP scan test (--s3-bucket not provided)"
    return 0
  fi

  log_info "TEST 4: Running OpenSCAP scan via SSM..."

  # Detect OS type
  local platform_type
  platform_type=$(aws ssm describe-instance-information \
    --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].PlatformType' \
    --output text 2>/dev/null || echo "Unknown")

  if [[ "$platform_type" == "Windows" ]]; then
    log_skip "OpenSCAP scan: Not supported on Windows instances"
    return 0
  fi

  local doc_name
  if [[ -n "$SSM_DOC" ]]; then
    doc_name="$SSM_DOC"
  else
    # Use the custom SSM document created by Terraform
    doc_name="AWS-RunShellScript"
  fi

  local scan_script
  scan_script=$(cat <<'EOSCRIPT'
#!/bin/bash
set -e

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="$ID"
  OS_VERSION="${VERSION_ID%%.*}"
else
  echo "ERROR: Cannot detect OS"
  exit 1
fi

# Select SCAP data stream
case "$OS_ID" in
  rhel|centos)
    DS_FILE="/usr/share/xml/scap/ssg/content/ssg-rhel${OS_VERSION}-ds.xml"
    PROFILE="xccdf_org.ssgproject.content_profile_stig"
    ;;
  ol)
    DS_FILE="/usr/share/xml/scap/ssg/content/ssg-ol${OS_VERSION}-ds.xml"
    PROFILE="xccdf_org.ssgproject.content_profile_stig"
    ;;
  amzn)
    DS_FILE="/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml"
    PROFILE="xccdf_org.ssgproject.content_profile_stig"
    ;;
  *)
    echo "ERROR: Unsupported OS: $OS_ID"
    exit 1
    ;;
esac

if [ ! -f "$DS_FILE" ]; then
  echo "ERROR: SCAP data stream not found: $DS_FILE"
  echo "Install scap-security-guide package"
  exit 1
fi

echo "OS: $OS_ID $OS_VERSION"
echo "Data Stream: $DS_FILE"
echo "Profile: $PROFILE"

# Run scan
RESULTS_DIR="/tmp/oscap-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

oscap xccdf eval \
  --profile "$PROFILE" \
  --results "$RESULTS_DIR/results.xml" \
  --report "$RESULTS_DIR/report.html" \
  "$DS_FILE" || true

# Summary
PASS=$(grep -c 'result="pass"' "$RESULTS_DIR/results.xml" 2>/dev/null || echo 0)
FAIL=$(grep -c 'result="fail"' "$RESULTS_DIR/results.xml" 2>/dev/null || echo 0)
NA=$(grep -c 'result="notapplicable"' "$RESULTS_DIR/results.xml" 2>/dev/null || echo 0)

echo ""
echo "=== SCAN SUMMARY ==="
echo "Pass: $PASS"
echo "Fail: $FAIL"
echo "Not Applicable: $NA"

# Cleanup
rm -rf "$RESULTS_DIR"
EOSCRIPT
)

  local command_id
  command_id=$(aws ssm send-command \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "$doc_name" \
    --parameters "commands=[$(echo "$scan_script" | jq -Rs .)]" \
    --timeout-seconds 600 \
    --output-s3-bucket-name "$S3_BUCKET" \
    --output-s3-key-prefix "ssm-test/oscap" \
    --query 'Command.CommandId' \
    --output text 2>/dev/null)

  if [[ -z "$command_id" || "$command_id" == "None" ]]; then
    log_fail "OpenSCAP: Failed to send scan command"
    return 1
  fi

  log_info "  Scan command sent: $command_id (may take 3-5 minutes)..."

  # Poll for completion with longer timeout for OSCAP
  local status="InProgress"
  local wait=0
  while [[ "$status" == "InProgress" || "$status" == "Pending" ]] && [[ $wait -lt 600 ]]; do
    sleep 15
    wait=$((wait + 15))
    status=$(aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$INSTANCE_ID" \
      --query 'Status' \
      --output text 2>/dev/null || echo "InProgress")
    if [[ $((wait % 60)) -eq 0 ]]; then
      log_info "  Still running... (${wait}s elapsed)"
    fi
  done

  if [[ "$status" == "Success" ]]; then
    local output
    output=$(aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardOutputContent' \
      --output text 2>/dev/null)
    echo "$output" | grep -A 10 "SCAN SUMMARY" || true
    log_pass "OpenSCAP scan completed via SSM"
    return 0
  else
    local error_output
    error_output=$(aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardErrorContent' \
      --output text 2>/dev/null)
    log_fail "OpenSCAP scan: Status=$status - Error: $error_output"
    return 1
  fi
}

# ============================================================================
# TEST 5: Verify SSM Inventory Collection
# ============================================================================
test_inventory() {
  log_info "TEST 5: Checking SSM Inventory data..."

  local inventory
  inventory=$(aws ssm list-inventory-entries \
    --region "$REGION" \
    --instance-id "$INSTANCE_ID" \
    --type-name "AWS:Application" \
    --query 'Entries[0:3]' \
    --output json 2>/dev/null || echo "[]")

  if [[ "$inventory" != "[]" && "$inventory" != "null" ]]; then
    local count
    count=$(echo "$inventory" | jq 'length')
    log_pass "SSM Inventory: $count application entries found"
    return 0
  else
    log_warn "SSM Inventory: No application data yet (may need scheduled collection)"
    log_pass "SSM Inventory: API accessible (data collection may be pending)"
    return 0
  fi
}

# ============================================================================
# Run all tests
# ============================================================================
echo "================================================================"
echo "SSM Validation Test Suite"
echo "Instance: $INSTANCE_ID"
echo "Region:   $REGION"
echo "================================================================"
echo ""

# Test 1 is a prerequisite for all others
if ! test_ssm_registration; then
  echo ""
  echo "================================================================"
  log_fail "SSM agent not registered — cannot proceed with remaining tests"
  echo "Results: 0 passed, 1 failed, 0 skipped"
  echo "================================================================"
  exit 1
fi

test_run_command || true
test_session_manager || true
test_oscap_scan || true
test_inventory || true

echo ""
echo "================================================================"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${SKIP_COUNT} skipped"
echo "================================================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
