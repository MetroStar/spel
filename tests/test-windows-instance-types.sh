#!/bin/bash
# Test Windows AMI boot compatibility across different EC2 instance families
# Usage: ./test-windows-instance-types.sh [--quick] <AMI_ID> <SUBNET_ID> <SECURITY_GROUP_ID> [KEY_NAME]
#
# This script launches the AMI on multiple Nitro generation instance types to verify
# boot compatibility. Older Nitro (t3, m5) vs newer Nitro (m6i, m7i) may have different
# driver requirements that could be affected by STIG hardening or Sysprep cleanup.
#
# Options:
#   --quick   Test only 3 key instance types (t3, m6i, m7i) for CI pipelines
#             Without --quick, tests 8 instance types across all Nitro generations

set -e

# Parse --quick flag
QUICK_MODE=false
if [[ "$1" == "--quick" ]]; then
  QUICK_MODE=true
  shift
fi

AMI_ID="${1:?Usage: $0 [--quick] <AMI_ID> <SUBNET_ID> <SECURITY_GROUP_ID> [KEY_NAME]}"
SUBNET_ID="${2:?Usage: $0 [--quick] <AMI_ID> <SUBNET_ID> <SECURITY_GROUP_ID> [KEY_NAME]}"
SECURITY_GROUP="${3:?Usage: $0 [--quick] <AMI_ID> <SUBNET_ID> <SECURITY_GROUP_ID> [KEY_NAME]}"
KEY_NAME="${4:-}"
REGION="${AWS_REGION:-us-east-1}"

# Output directory for console logs
OUTPUT_DIR="./test-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

# Instance types to test - depends on mode
if $QUICK_MODE; then
  # Quick mode: 3 key types covering each Nitro generation (for CI)
  INSTANCE_TYPES=(
    "t3.medium"      # Nitro Gen 1 (baseline)
    "m6i.large"      # Nitro Gen 2 (Intel Ice Lake)
    "m7i.large"      # Nitro Gen 3 (Intel Sapphire Rapids)
  )
else
  # Full mode: 8 instance types across all Nitro generations
  INSTANCE_TYPES=(
    "t3.medium"      # Nitro Gen 1 (baseline)
    "m5.large"       # Nitro Gen 1
    "c5.large"       # Nitro Gen 1
    "m6i.large"      # Nitro Gen 2 (Intel Ice Lake)
    "c6i.large"      # Nitro Gen 2
    "r6i.large"      # Nitro Gen 2
    "m7i.large"      # Nitro Gen 3 (Intel Sapphire Rapids)
    "c7i.large"      # Nitro Gen 3
  )
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${NC}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

# Track results
declare -A RESULTS

echo "=============================================="
echo "Windows AMI Instance Type Compatibility Test"
echo "=============================================="
echo "Mode:           $($QUICK_MODE && echo 'Quick (CI)' || echo 'Full')"
echo "Instance Types: ${#INSTANCE_TYPES[@]}"
echo "AMI ID:         $AMI_ID"
echo "Subnet:         $SUBNET_ID"
echo "Security Group: $SECURITY_GROUP"
echo "Region:         $REGION"
echo "Output Dir:     $OUTPUT_DIR"
echo "=============================================="
echo ""

# Get AMI info
AMI_NAME=$(aws ec2 describe-images --region "$REGION" --image-ids "$AMI_ID" \
  --query 'Images[0].Name' --output text 2>/dev/null || echo "Unknown")
echo "AMI Name: $AMI_NAME"
echo ""

for INSTANCE_TYPE in "${INSTANCE_TYPES[@]}"; do
  echo "=============================================="
  log_info "Testing: $INSTANCE_TYPE"
  echo "=============================================="
  
  # Check if instance type is available in the region
  AVAILABLE=$(aws ec2 describe-instance-type-offerings --region "$REGION" \
    --filters "Name=instance-type,Values=$INSTANCE_TYPE" \
    --query 'InstanceTypeOfferings[0].InstanceType' --output text 2>/dev/null || echo "")
  
  if [[ -z "$AVAILABLE" || "$AVAILABLE" == "None" ]]; then
    log_warning "$INSTANCE_TYPE not available in $REGION, skipping..."
    RESULTS["$INSTANCE_TYPE"]="SKIPPED (unavailable)"
    continue
  fi
  
  # Build launch command
  LAUNCH_CMD="aws ec2 run-instances --region $REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --subnet-id $SUBNET_ID \
    --security-group-ids $SECURITY_GROUP \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=granite-test-$INSTANCE_TYPE}]' \
    --query Instances[0].InstanceId \
    --output text"
  
  if [[ -n "$KEY_NAME" ]]; then
    LAUNCH_CMD="$LAUNCH_CMD --key-name $KEY_NAME"
  fi
  
  # Launch instance
  log_info "Launching instance..."
  INSTANCE_ID=$(eval "$LAUNCH_CMD" 2>&1)
  
  if [[ ! "$INSTANCE_ID" =~ ^i- ]]; then
    log_error "Failed to launch: $INSTANCE_ID"
    RESULTS["$INSTANCE_TYPE"]="FAILED (launch error)"
    continue
  fi
  
  log_info "Instance ID: $INSTANCE_ID"
  
  # Wait for instance to be running
  log_info "Waiting for instance to start..."
  aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID" 2>/dev/null || true
  
  # Wait for status checks (up to 10 minutes)
  log_info "Waiting for status checks (timeout: 10 minutes)..."
  BOOT_SUCCESS=false
  SYSTEM_STATUS="unknown"
  INSTANCE_STATUS="unknown"
  
  for i in {1..60}; do
    STATUS_OUTPUT=$(aws ec2 describe-instance-status --region "$REGION" \
      --instance-ids "$INSTANCE_ID" \
      --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
      --output text 2>/dev/null || echo "pending pending")
    
    SYSTEM_STATUS=$(echo "$STATUS_OUTPUT" | awk '{print $1}')
    INSTANCE_STATUS=$(echo "$STATUS_OUTPUT" | awk '{print $2}')
    
    # Show progress every 30 seconds
    if (( i % 3 == 0 )); then
      log_info "  Check $i/60: System=$SYSTEM_STATUS, Instance=$INSTANCE_STATUS"
    fi
    
    if [[ "$SYSTEM_STATUS" == "ok" && "$INSTANCE_STATUS" == "ok" ]]; then
      BOOT_SUCCESS=true
      break
    fi
    
    # Check for impaired status (boot failure)
    if [[ "$SYSTEM_STATUS" == "impaired" || "$INSTANCE_STATUS" == "impaired" ]]; then
      log_error "Instance status impaired - likely boot failure"
      break
    fi
    
    sleep 10
  done
  
  # Get console output for debugging
  log_info "Fetching console output..."
  CONSOLE_FILE="$OUTPUT_DIR/console-${INSTANCE_TYPE//\./-}.txt"
  aws ec2 get-console-output --region "$REGION" --instance-id "$INSTANCE_ID" \
    --query 'Output' --output text > "$CONSOLE_FILE" 2>/dev/null || true
  
  # Get screenshot if available
  SCREENSHOT_FILE="$OUTPUT_DIR/screenshot-${INSTANCE_TYPE//\./-}.jpg"
  aws ec2 get-console-screenshot --region "$REGION" --instance-id "$INSTANCE_ID" \
    --query 'ImageData' --output text 2>/dev/null | base64 -d > "$SCREENSHOT_FILE" 2>/dev/null || true
  
  # Record result
  if $BOOT_SUCCESS; then
    log_success "$INSTANCE_TYPE - Boot successful!"
    RESULTS["$INSTANCE_TYPE"]="SUCCESS"
  else
    log_error "$INSTANCE_TYPE - Boot failed (System=$SYSTEM_STATUS, Instance=$INSTANCE_STATUS)"
    RESULTS["$INSTANCE_TYPE"]="FAILED (System=$SYSTEM_STATUS, Instance=$INSTANCE_STATUS)"
    
    # Check console output for driver issues
    if [[ -s "$CONSOLE_FILE" ]]; then
      if grep -qi "inaccessible boot device\|driver\|nvme\|ena" "$CONSOLE_FILE"; then
        log_warning "Console output may indicate driver issues - check $CONSOLE_FILE"
      fi
    fi
  fi
  
  # Terminate instance
  log_info "Terminating instance..."
  aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" > /dev/null 2>&1 || true
  
  echo ""
done

# Summary
echo "=============================================="
echo "                 SUMMARY"
echo "=============================================="
echo "AMI: $AMI_ID ($AMI_NAME)"
echo ""

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for INSTANCE_TYPE in "${INSTANCE_TYPES[@]}"; do
  RESULT="${RESULTS[$INSTANCE_TYPE]:-UNKNOWN}"
  
  if [[ "$RESULT" == "SUCCESS" ]]; then
    echo -e "${GREEN}✓ $INSTANCE_TYPE: $RESULT${NC}"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  elif [[ "$RESULT" == *"SKIPPED"* ]]; then
    echo -e "${YELLOW}○ $INSTANCE_TYPE: $RESULT${NC}"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  else
    echo -e "${RED}✗ $INSTANCE_TYPE: $RESULT${NC}"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

echo ""
echo "Results: $SUCCESS_COUNT passed, $FAILED_COUNT failed, $SKIPPED_COUNT skipped"
echo "Console logs saved to: $OUTPUT_DIR"

# Exit with error if any failed
if [[ $FAILED_COUNT -gt 0 ]]; then
  echo ""
  log_error "Some instance types failed to boot. Check console logs for driver issues."
  log_info "Common causes:"
  log_info "  - Missing ENA driver (network)"
  log_info "  - Missing NVMe driver (storage)"
  log_info "  - STIG controls blocking driver installation"
  log_info "  - DISM cleanup removing driver packages"
  exit 1
fi

exit 0
