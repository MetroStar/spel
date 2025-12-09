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
PYTHON_VERSION="${SPEL_PYTHON_VERSION:-3.9}"  # RHEL 8/9 default Python version
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

# Download for Python 3.9 (EL9, AL2023, CI/CD runners) - Ansible 2.14-2.15
log_info "Downloading Python 3.9 wheels for RHEL 9, Oracle Linux 9, Amazon Linux 2023, CI/CD..."
if python3.9 -m pip download \
    --dest "$TOOLS_DIR" \
    --python-version 39 \
    --platform manylinux2014_x86_64 \
    --implementation cp \
    --only-binary=:all: \
    "${PACKAGES[@]}" 2>&1 | tee /tmp/pip-download-py39.log; then
    
    log_info "  ✓ Python 3.9 wheels downloaded successfully"
else
    log_error "  ✗ Failed to download Python 3.9 wheels"
    log_error "Check /tmp/pip-download-py39.log for details"
    exit 1
fi

# Download for Python 3.6 (EL8 - RHEL 8, Oracle Linux 8) - Use 'ansible' package
# Note: ansible-core 2.11.x was removed from PyPI, but 'ansible' 4.x (includes core 2.11.x) is still available
log_info "Downloading Python 3.6 wheels for RHEL 8, Oracle Linux 8 (using ansible 4.x package)..."

# First, download all dependencies as wheels
PACKAGES_PY36=(
    "pywinrm>=0.4.3"
    "requests>=2.27.0,<2.32.0"
    "requests-ntlm>=1.1.0"
    "passlib>=1.7.4"
    "lxml>=4.6.0,<5.0.0"
    "xmltodict>=0.13.0"
    "jmespath>=0.10.0"
    "distro>=1.6.0"
    "pytest>=6.2.0,<8.0.0"
    "pytest-logger>=0.5.1"
    "pytest-testinfra>=6.0.0,<10.0.0"
)

python3.9 -m pip download \
    --dest "$TOOLS_DIR" \
    --python-version 36 \
    --platform manylinux2014_x86_64 \
    --implementation cp \
    --only-binary=:all: \
    "${PACKAGES_PY36[@]}" 2>&1 | tee /tmp/pip-download-py36-wheels.log

log_info "  ✓ Python 3.6 dependency wheels downloaded"

# Second, download ansible package separately as source (no platform constraints needed)
# Note: ansible 4.x only available as source distribution (.tar.gz)
log_info "Downloading ansible 4.x package for Python 3.6 (source distribution)..."
python3.9 -m pip download \
    --dest "$TOOLS_DIR" \
    --python-version 36 \
    "ansible>=4.0.0,<5.0.0" 2>&1 | tee /tmp/pip-download-py36-ansible.log

log_info "  ✓ ansible package downloaded (source distribution)"

# Count downloaded packages (wheels and source distributions)
WHEEL_COUNT=$(find "$TOOLS_DIR" -name "*.whl" | wc -l)
SDIST_COUNT=$(find "$TOOLS_DIR" -name "*.tar.gz" | wc -l)
TOTAL_PACKAGES=$((WHEEL_COUNT + SDIST_COUNT))
log_info "Downloaded ${WHEEL_COUNT} wheels and ${SDIST_COUNT} source distributions (${TOTAL_PACKAGES} total)"

# Calculate total size
TOTAL_SIZE=$(du -sh "$TOOLS_DIR" | awk '{print $1}')
log_info "Total size: ${TOTAL_SIZE}"

# Create version manifest
VERSION_FILE="${TOOLS_DIR}/VERSIONS.txt"
log_info "Creating version manifest..."

cat > "$VERSION_FILE" <<EOF
# Ansible Core and Dependencies - Python Wheels
# Downloaded on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Python Versions: 
  - 3.6 (EL8): ansible 4.x package (includes ansible-core 2.11.x)
    Note: ansible-core 2.11.x was removed from PyPI, using 'ansible' package instead
  - 3.9 (EL9, AL2023, CI/CD): Ansible Core 2.14-2.15.x
Platform: manylinux2014_x86_64

Downloaded Packages
===================
EOF

# List all downloaded packages (wheels and source distributions) with sizes
log_debug "Listing downloaded packages..."
find "$TOOLS_DIR" \( -name "*.whl" -o -name "*.tar.gz" \) -type f | sort | while read -r package; do
    filename=$(basename "$package")
    size=$(du -h "$package" | awk '{print $1}')
    sha256=$(sha256sum "$package" | awk '{print $1}')
    
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

For EL8 (RHEL 8, Oracle Linux 8) - Python 3.6 with ansible 4.x:
   python3.6 --version
   python3.6 -m pip install --upgrade pip
   python3.6 -m pip install --no-index --find-links tools/python-deps/ "ansible>=4.0.0,<5.0.0"

For EL9, AL2023, CI/CD - Python 3.9 with Ansible 2.14-2.15.x:
   python3.9 --version
   python3.9 -m pip install --no-index --find-links tools/python-deps/ "ansible-core>=2.14.0,<2.16.0"

Verify installation:
   ansible --version
   ansible-galaxy --version

Test Ansible:
   ansible localhost -m ping

Notes
=====
- Wheels for both Python 3.6 and 3.9 are included
- Python 3.6: RHEL 8, Oracle Linux 8 (system default) - ansible 4.x package (includes ansible-core 2.11.x)
  * ansible-core 2.11.x was removed from PyPI, so we use the 'ansible' package instead
- Python 3.9: RHEL 9, Oracle Linux 9, Amazon Linux 2023, GitHub/GitLab CI - Ansible Core 2.14-2.15.x
- Ansible Core 2.12+ requires Python 3.8+, so EL8 uses ansible 4.x (last version supporting Python 3.6)
- Compatible with Linux x86_64 (manylinux2014)
- All dependencies included (pywinrm, requests, passlib, lxml, etc.)
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
log_info "Downloaded packages:"
find "$TOOLS_DIR" \( -name "*.whl" -o -name "*.tar.gz" \) -type f | sort | while read -r package; do
    filename=$(basename "$package")
    size=$(du -h "$package" | awk '{print $1}')
    printf "  %-60s %10s\n" "$filename" "$size"
done

log_info ""
log_info "Summary:"
log_info "  Wheels: ${WHEEL_COUNT}"
log_info "  Source distributions: ${SDIST_COUNT}"
log_info "  Total packages: ${TOTAL_PACKAGES}"
log_info "  Total size: ${TOTAL_SIZE}"
log_info "  Location: ${TOOLS_DIR}"
log_info "  Manifest: ${VERSION_FILE}"
log_info ""
log_info "Installation command for Offline:"
log_info "  EL8:  python3.6 -m pip install --no-index --find-links tools/python-deps/ \"ansible>=4.0.0,<5.0.0\""
log_info "  EL9+: python3.9 -m pip install --no-index --find-links tools/python-deps/ \"ansible-core>=2.14.0,<2.16.0\""
log_info "========================================="
