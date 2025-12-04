#!/bin/bash
#
# Download AWS utilities for offline Offline builds with storage optimization
# Run this on a system with internet access before transferring to Offline
#
# STORAGE OPTIMIZATION:
# - Single SSM Agent file (compatible with both EL8/EL9)
# - Optional compression of packages
# - Version tracking for updates
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OFFLINE_DIR="${REPO_ROOT}/offline-packages"

# Configuration
COMPRESS="${SPEL_OFFLINE_COMPRESS:-true}"
VERIFY_DOWNLOADS="${SPEL_OFFLINE_VERIFY:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check for required commands
if ! command -v wget &> /dev/null; then
    log_error "wget is required but not installed"
    exit 1
fi

if ! command -v dnf &> /dev/null; then
    log_error "dnf is required but not installed (needed to download EPEL packages)"
    exit 1
fi

log_info "Offline packages download configuration:"
log_debug "  Packages directory: $OFFLINE_DIR"
log_debug "  Create compressed archive: $COMPRESS"
log_debug "  Verify downloads: $VERIFY_DOWNLOADS"

mkdir -p "$OFFLINE_DIR"
mkdir -p "$OFFLINE_DIR/ec2-utils-el8"
mkdir -p "$OFFLINE_DIR/ec2-utils-el9"

# Track download sizes
TOTAL_SIZE=0

# 1. AWS CLI v2
log_info "[1/6] Downloading AWS CLI v2..."
AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
AWS_CLI_FILE="${OFFLINE_DIR}/awscli-exe-linux-x86_64.zip"

if wget -N "$AWS_CLI_URL" -O "$AWS_CLI_FILE"; then
    SIZE=$(du -h "$AWS_CLI_FILE" | awk '{print $1}')
    log_info "  Downloaded: awscli-exe-linux-x86_64.zip ($SIZE)"
    TOTAL_SIZE=$((TOTAL_SIZE + $(stat -c%s "$AWS_CLI_FILE")))
else
    log_error "  Failed to download AWS CLI v2"
fi

# 2. CloudFormation Bootstrap
log_info "[2/6] Downloading AWS CloudFormation Bootstrap..."
CFN_URL="https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz"
CFN_FILE="${OFFLINE_DIR}/aws-cfn-bootstrap-py3-latest.tar.gz"

if wget -N "$CFN_URL" -O "$CFN_FILE"; then
    SIZE=$(du -h "$CFN_FILE" | awk '{print $1}')
    log_info "  Downloaded: aws-cfn-bootstrap-py3-latest.tar.gz ($SIZE)"
    TOTAL_SIZE=$((TOTAL_SIZE + $(stat -c%s "$CFN_FILE")))
else
    log_error "  Failed to download CloudFormation Bootstrap"
fi

# 3. SSM Agent (single version for both EL8/EL9)
log_info "[3/6] Downloading AWS SSM Agent..."
SSM_URL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
SSM_FILE="${OFFLINE_DIR}/amazon-ssm-agent.rpm"

if wget -N "$SSM_URL" -O "$SSM_FILE"; then
    SIZE=$(du -h "$SSM_FILE" | awk '{print $1}')
    log_info "  Downloaded: amazon-ssm-agent.rpm ($SIZE)"
    log_debug "  Note: Single SSM Agent RPM is compatible with both EL8 and EL9"
    TOTAL_SIZE=$((TOTAL_SIZE + $(stat -c%s "$SSM_FILE")))
else
    log_error "  Failed to download SSM Agent"
fi

# 4. EC2 utility packages for EL8 from EPEL
log_info "[4/6] Downloading EC2 utility packages for EL8 from EPEL..."
EC2_EL8_DIR="${OFFLINE_DIR}/ec2-utils-el8"

# Enable EPEL repository for downloads
if ! dnf repolist 2>/dev/null | grep -q epel; then
    log_debug "  Installing EPEL repository..."
    dnf install -y epel-release 2>&1 | grep -v "^$" || true
fi

# Download EL8 EC2 packages
EC2_EL8_PACKAGES=(
    "ec2-hibinit-agent"
    "ec2-instance-connect"
    "ec2-instance-connect-selinux"
)

for pkg in "${EC2_EL8_PACKAGES[@]}"; do
    log_debug "  Downloading $pkg for EL8..."
    if dnf download --releasever=8 --destdir="$EC2_EL8_DIR" "$pkg" 2>&1 | grep -v "^$"; then
        log_debug "    ✓ Downloaded $pkg"
    else
        log_warn "    ⚠ Failed to download $pkg (may not be available)"
    fi
done

# Download ec2-utils from Oracle Linux repository (not available in EPEL for RHEL)
log_debug "  Downloading ec2-utils from Oracle Linux repository..."
EC2_UTILS_URL="https://yum.oracle.com/repo/OracleLinux/OL8/baseos/latest/x86_64/getPackage/ec2-utils-2.2-1.0.2.el8.noarch.rpm"
if wget -N "$EC2_UTILS_URL" -O "${EC2_EL8_DIR}/ec2-utils-2.2-1.0.2.el8.noarch.rpm" 2>&1 | grep -v "^$"; then
    log_debug "    ✓ Downloaded ec2-utils (Oracle Linux)"
else
    log_warn "    ⚠ Failed to download ec2-utils from Oracle Linux repo"
fi

EC2_EL8_COUNT=$(find "$EC2_EL8_DIR" -name "*.rpm" 2>/dev/null | wc -l)
if [ "$EC2_EL8_COUNT" -gt 0 ]; then
    EC2_EL8_SIZE=$(du -sh "$EC2_EL8_DIR" | awk '{print $1}')
    log_info "  Downloaded $EC2_EL8_COUNT EL8 packages ($EC2_EL8_SIZE)"
    TOTAL_SIZE=$((TOTAL_SIZE + $(du -sb "$EC2_EL8_DIR" | awk '{print $1}')))
else
    log_warn "  No EL8 packages downloaded"
fi

# 5. EC2 utility packages for EL9 from EPEL and Oracle Linux
log_info "[5/6] Downloading EC2 utility packages for EL9..."
EC2_EL9_DIR="${OFFLINE_DIR}/ec2-utils-el9"

# Download EL9 EC2 packages directly from EPEL mirror
log_debug "  Downloading ec2-hibinit-agent from EPEL..."
if wget -N "https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/e/ec2-hibinit-agent-1.0.8-1.el9.noarch.rpm" \
    -O "${EC2_EL9_DIR}/ec2-hibinit-agent-1.0.8-1.el9.noarch.rpm" 2>&1 | grep -v "^$"; then
    log_debug "    ✓ Downloaded ec2-hibinit-agent"
else
    log_warn "    ⚠ Failed to download ec2-hibinit-agent"
fi

# Download ec2-utils from Oracle Linux repository (not available in EPEL for RHEL)
log_debug "  Downloading ec2-utils from Oracle Linux repository..."
if wget -N "https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64/getPackage/ec2-utils-2.2-1.0.1.el9.noarch.rpm" \
    -O "${EC2_EL9_DIR}/ec2-utils-2.2-1.0.1.el9.noarch.rpm" 2>&1 | grep -v "^$"; then
    log_debug "    ✓ Downloaded ec2-utils (Oracle Linux)"
else
    log_warn "    ⚠ Failed to download ec2-utils from Oracle Linux repo"
fi

EC2_EL9_COUNT=$(find "$EC2_EL9_DIR" -name "*.rpm" 2>/dev/null | wc -l)
if [ "$EC2_EL9_COUNT" -gt 0 ]; then
    EC2_EL9_SIZE=$(du -sh "$EC2_EL9_DIR" | awk '{print $1}')
    log_info "  Downloaded $EC2_EL9_COUNT EL9 packages ($EC2_EL9_SIZE)"
    TOTAL_SIZE=$((TOTAL_SIZE + $(du -sb "$EC2_EL9_DIR" | awk '{print $1}')))
else
    log_warn "  No EL9 packages downloaded"
fi

# 6. Create repository metadata for EC2 packages
log_info "[6/6] Creating repository metadata for EC2 packages..."

if command -v createrepo_c &> /dev/null; then
    if [ "$EC2_EL8_COUNT" -gt 0 ]; then
        log_debug "  Creating EL8 repository metadata..."
        createrepo_c "$EC2_EL8_DIR" &>/dev/null
        log_debug "    ✓ Created EL8 repository"
    fi
    
    if [ "$EC2_EL9_COUNT" -gt 0 ]; then
        log_debug "  Creating EL9 repository metadata..."
        createrepo_c "$EC2_EL9_DIR" &>/dev/null
        log_debug "    ✓ Created EL9 repository"
    fi
else
    log_warn "  createrepo_c not found - skipping repository metadata creation"
    log_warn "  Install with: dnf install createrepo_c"
fi

# Verify downloads
if [ "$VERIFY_DOWNLOADS" = "true" ]; then
    log_info "Verifying downloads..."
    
    # Check file sizes (basic verification)
    if [ -f "$AWS_CLI_FILE" ] && [ $(stat -c%s "$AWS_CLI_FILE") -gt 1000000 ]; then
        log_debug "  ✓ AWS CLI appears valid (>1MB)"
    else
        log_warn "  ⚠ AWS CLI may be incomplete"
    fi
    
    if [ -f "$CFN_FILE" ] && [ $(stat -c%s "$CFN_FILE") -gt 100000 ]; then
        log_debug "  ✓ CFN Bootstrap appears valid (>100KB)"
    else
        log_warn "  ⚠ CFN Bootstrap may be incomplete"
    fi
    
    if [ -f "$SSM_FILE" ] && [ $(stat -c%s "$SSM_FILE") -gt 10000000 ]; then
        log_debug "  ✓ SSM Agent appears valid (>10MB)"
    else
        log_warn "  ⚠ SSM Agent may be incomplete"
    fi
fi

# Create version tracking file
VERSION_FILE="${OFFLINE_DIR}/VERSIONS.txt"
log_info "Creating version tracking file..."

cat > "$VERSION_FILE" <<EOF
# Offline Packages Version Information
# Downloaded on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

AWS CLI v2:
  URL: $AWS_CLI_URL
  File: awscli-exe-linux-x86_64.zip
  Size: $(du -h "$AWS_CLI_FILE" 2>/dev/null | awk '{print $1}' || echo "N/A")
  SHA256: $(sha256sum "$AWS_CLI_FILE" 2>/dev/null | awk '{print $1}' || echo "N/A")

CloudFormation Bootstrap:
  URL: $CFN_URL
  File: aws-cfn-bootstrap-py3-latest.tar.gz
  Size: $(du -h "$CFN_FILE" 2>/dev/null | awk '{print $1}' || echo "N/A")
  SHA256: $(sha256sum "$CFN_FILE" 2>/dev/null | awk '{print $1}' || echo "N/A")

SSM Agent:
  URL: $SSM_URL
  File: amazon-ssm-agent.rpm
  Size: $(du -h "$SSM_FILE" 2>/dev/null | awk '{print $1}' || echo "N/A")
  SHA256: $(sha256sum "$SSM_FILE" 2>/dev/null | awk '{print $1}' || echo "N/A")
  Compatible: EL8, EL9

EC2 Utility Packages (EL8):
  Source: EPEL 8
  Directory: ec2-utils-el8/
  Packages: $EC2_EL8_COUNT
  Size: $(du -sh "$EC2_EL8_DIR" 2>/dev/null | awk '{print $1}' || echo "N/A")
  Files:
$(find "$EC2_EL8_DIR" -name "*.rpm" -type f 2>/dev/null | sort | sed 's|^|    - |' || echo "    None")

EC2 Utility Packages (EL9):
  Source: EPEL 9
  Directory: ec2-utils-el9/
  Packages: $EC2_EL9_COUNT
  Size: $(du -sh "$EC2_EL9_DIR" 2>/dev/null | awk '{print $1}' || echo "N/A")
  Files:
$(find "$EC2_EL9_DIR" -name "*.rpm" -type f 2>/dev/null | sort | sed 's|^|    - |' || echo "    None")

Total Size: $(du -sh "$OFFLINE_DIR" | awk '{print $1}')

Notes:
  - python39* and crypto-policies-scripts packages are available in RHEL base repositories
  - EC2 utility packages are from EPEL and required for RHEL builds
  - Repository metadata created for EC2 packages (if createrepo_c available)
EOF

log_info "Version information saved to VERSIONS.txt"

# Create compressed archive
if [ "$COMPRESS" = "true" ]; then
    ARCHIVE_PATH="${SCRIPT_DIR}/../offline-packages.tar.gz"
    log_info "Creating compressed archive..."
    
    tar czf "$ARCHIVE_PATH" \
        -C "$(dirname "$OFFLINE_DIR")" \
        "$(basename "$OFFLINE_DIR")"
    
    ARCHIVE_SIZE=$(du -sh "$ARCHIVE_PATH" | awk '{print $1}')
    UNCOMPRESSED_SIZE=$(du -sh "$OFFLINE_DIR" | awk '{print $1}')
    
    log_info "Created: offline-packages.tar.gz"
    log_info "  Uncompressed: $UNCOMPRESSED_SIZE"
    log_info "  Compressed: $ARCHIVE_SIZE"
    log_info "  Archive location: $ARCHIVE_PATH"
fi

# Summary
log_info ""
log_info "Offline packages download complete!"
log_info "Downloaded files:"
ls -lh "$OFFLINE_DIR" | grep -E '\.(zip|tar\.gz|rpm)$' | awk '{print "  " $9 " (" $5 ")"}'

log_info ""
log_info "Total package size: $(du -sh "$OFFLINE_DIR" | awk '{print $1}')"
log_info "SHA256 checksums saved in VERSIONS.txt"
