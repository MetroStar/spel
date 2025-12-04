#!/bin/bash
#
# Download Ansible Core and dependencies for offline Offline builds
# Run this on a system with internet access before transferring to Offline
#
# This script downloads:
# - ansible-core (>=2.16.0, <2.19.0)
# - Python dependencies: pywinrm, requests, requests-ntlm, passlib, lxml, xmltodict, jmespath
# - Test dependencies: distro, pytest, pytest-logger, pytest-testinfra
#
# Uses combined approach:
# - Pure-Python wheels where available (--only-binary=:none:)
# - Platform-specific binary wheels (manylinux2014_x86_64) where needed
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/../tools/python-deps"

# Configuration
PYTHON_VERSION="${SPEL_PYTHON_VERSION:-3.12}"
ANSIBLE_VERSION="${SPEL_ANSIBLE_VERSION:->=2.14.0,<2.16.0}"  # 2.14.x and 2.15.x support Python 3.9+

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
for cmd in pip python3; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is required but not installed"
        exit 1
    fi
done

log_info "Ansible Core download configuration:"
log_debug "  Python version: ${PYTHON_VERSION}"
log_debug "  Ansible Core version: ${ANSIBLE_VERSION}"
log_debug "  Target directory: ${TOOLS_DIR}"

mkdir -p "$TOOLS_DIR"

# Download Ansible Core and dependencies
log_info "Downloading Ansible Core and dependencies..."
log_debug "  Using combined pure-Python and platform-specific approach"

# List of packages to download
PACKAGES=(
    "ansible-core${ANSIBLE_VERSION}"
    "pywinrm>=0.4.3"
    "requests>=2.31.0"
    "requests-ntlm>=1.2.0"
    "passlib>=1.7.4"
    "lxml>=4.9.0"
    "xmltodict>=0.13.0"
    "jmespath>=1.0.1"
    "distro>=1.8.0"
    "pytest>=7.4.0"
    "pytest-logger>=0.5.1"
    "pytest-testinfra>=9.0.0"
)

log_info "Packages to download:"
for pkg in "${PACKAGES[@]}"; do
    log_debug "  - ${pkg}"
done

# Download wheels with combined approach
# This will get pure-Python wheels where available and platform-specific where needed
log_info "Downloading Python wheels..."

# Download for the specified Python version (defaults to 3.12 for GitHub Actions compatibility)
# This will download all dependencies including lxml with proper binary wheels
if pip download \
    --dest "$TOOLS_DIR" \
    --python-version "$PYTHON_VERSION" \
    --platform manylinux2014_x86_64 \
    --implementation cp \
    --only-binary=:all: \
    "${PACKAGES[@]}" 2>&1 | tee /tmp/pip-download.log; then
    
    log_info "  ✓ Wheels downloaded successfully"
else
    log_error "  ✗ Failed to download wheels"
    log_error "Check /tmp/pip-download.log for details"
    exit 1
fi

# Count downloaded wheels
WHEEL_COUNT=$(find "$TOOLS_DIR" -name "*.whl" | wc -l)
log_info "Downloaded ${WHEEL_COUNT} wheel files"

# Calculate total size
TOTAL_SIZE=$(du -sh "$TOOLS_DIR" | awk '{print $1}')
log_info "Total size: ${TOTAL_SIZE}"

# Create version manifest
VERSION_FILE="${TOOLS_DIR}/VERSIONS.txt"
log_info "Creating version manifest..."

cat > "$VERSION_FILE" <<EOF
# Ansible Core and Dependencies - Python Wheels
# Downloaded on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Python Version: ${PYTHON_VERSION}
Platform: manylinux2014_x86_64
Ansible Core Version: ${ANSIBLE_VERSION}

Downloaded Packages
===================
EOF

# List all downloaded wheels with sizes
log_debug "Listing downloaded wheels..."
find "$TOOLS_DIR" -name "*.whl" -type f | sort | while read -r wheel; do
    filename=$(basename "$wheel")
    size=$(du -h "$wheel" | awk '{print $1}')
    sha256=$(sha256sum "$wheel" | awk '{print $1}')
    
    echo "${filename}" >> "$VERSION_FILE"
    echo "  Size: ${size}" >> "$VERSION_FILE"
    echo "  SHA256: ${sha256}" >> "$VERSION_FILE"
    echo "" >> "$VERSION_FILE"
done

cat >> "$VERSION_FILE" <<EOF

Total Files: ${WHEEL_COUNT}
Total Size: ${TOTAL_SIZE}

Installation Instructions
=========================

On Offline system after extraction:

1. Ensure Python ${PYTHON_VERSION} is installed:
   python3.9 --version

2. Install Ansible Core and dependencies from wheels:
   pip install --no-index --find-links tools/python-deps/ "ansible-core${ANSIBLE_VERSION}"

   Or install all wheels:
   pip install --no-index --find-links tools/python-deps/ tools/python-deps/*.whl

3. Verify installation:
   ansible --version
   ansible-galaxy --version

4. Test Ansible:
   ansible localhost -m ping

Notes
=====
- Wheels are compatible with Python ${PYTHON_VERSION} on Linux x86_64
- Includes both pure-Python and platform-specific binary wheels
- All dependencies for pywinrm, requests, passlib, lxml, xmltodict, jmespath included
- No internet connection required for installation

Package Details
===============
EOF

# Add package descriptions
cat >> "$VERSION_FILE" <<EOF

ansible-core:
  Purpose: Core Ansible automation engine
  Required for: Running Packer provisioners, system configuration

pywinrm:
  Purpose: Windows Remote Management protocol implementation
  Required for: Windows AMI builds with Ansible provisioner

requests:
  Purpose: HTTP library for Python
  Required for: Ansible modules, AWS API calls

requests-ntlm:
  Purpose: NTLM authentication handler for requests
  Required for: Windows WinRM authentication

passlib:
  Purpose: Password hashing library
  Required for: Ansible user management modules

lxml:
  Purpose: XML/HTML parsing library
  Required for: Ansible modules that process XML

xmltodict:
  Purpose: XML to dictionary converter
  Required for: Ansible AWS modules

jmespath:
  Purpose: JSON query language
  Required for: Ansible filters and AWS API response processing

distro:
  Purpose: Linux distribution detection
  Required for: Build scripts and system detection

pytest:
  Purpose: Python testing framework
  Required for: Running test suites

pytest-logger:
  Purpose: Pytest logging plugin
  Required for: Test logging

pytest-testinfra:
  Purpose: Infrastructure testing framework
  Required for: AMI validation tests
EOF

log_info "Version manifest created: ${VERSION_FILE}"

# Display summary
log_info ""
log_info "========================================="
log_info "Ansible Core Download Complete!"
log_info "========================================="
log_info ""
log_info "Downloaded wheels:"
find "$TOOLS_DIR" -name "*.whl" -type f | sort | while read -r wheel; do
    filename=$(basename "$wheel")
    size=$(du -h "$wheel" | awk '{print $1}')
    printf "  %-60s %10s\n" "$filename" "$size"
done

log_info ""
log_info "Summary:"
log_info "  Total wheels: ${WHEEL_COUNT}"
log_info "  Total size: ${TOTAL_SIZE}"
log_info "  Location: ${TOOLS_DIR}"
log_info "  Manifest: ${VERSION_FILE}"
log_info ""
log_info "Installation command for Offline:"
log_info "  pip install --no-index --find-links tools/python-deps/ \"ansible-core${ANSIBLE_VERSION}\""
log_info "========================================="
