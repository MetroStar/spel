#!/bin/bash
#
# Download Packer plugins for offline NIPR builds
# Run this on a system with internet access before transferring to NIPR
#
# This script:
# - Runs 'packer init' on all .pkr.hcl files to download required plugins
# - Copies plugins from ~/.config/packer/plugins/ to tools/packer/plugins/
# - Preserves the full nested directory structure (github.com/hashicorp/...)
# - Creates manifest with plugin versions and checksums
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGINS_DIR="${REPO_ROOT}/tools/packer/plugins"
PACKER_CONFIG_DIR="${HOME}/.config/packer/plugins"

# Configuration
PACKER_TEMPLATES=(
    "${REPO_ROOT}/spel/minimal-linux.pkr.hcl"
    "${REPO_ROOT}/spel/hardened-linux.pkr.hcl"
)

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
for cmd in packer; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is required but not installed"
        log_error "Run ./scripts/download-packer.sh first"
        exit 1
    fi
done

log_info "Packer plugins download configuration:"
log_debug "  Packer version: $(packer version | head -1)"
log_debug "  Templates to process: ${#PACKER_TEMPLATES[@]}"
log_debug "  Source: ${PACKER_CONFIG_DIR}"
log_debug "  Target: ${PLUGINS_DIR}"

# Initialize plugins for each template
log_info "Initializing Packer plugins from templates..."

for template in "${PACKER_TEMPLATES[@]}"; do
    if [ ! -f "$template" ]; then
        log_warn "Template not found: $template"
        continue
    fi
    
    template_name=$(basename "$template")
    log_info "Processing ${template_name}..."
    
    if packer init "$template" 2>&1 | tee "/tmp/packer-init-${template_name}.log"; then
        log_info "  ✓ Plugins initialized for ${template_name}"
    else
        log_error "  ✗ Failed to initialize plugins for ${template_name}"
        log_error "Check /tmp/packer-init-${template_name}.log for details"
        exit 1
    fi
done

# Check if plugins were downloaded
if [ ! -d "$PACKER_CONFIG_DIR" ]; then
    log_error "Packer plugin directory not found: ${PACKER_CONFIG_DIR}"
    log_error "No plugins were downloaded. Check Packer templates for plugin requirements."
    exit 1
fi

# Copy plugins to tools directory
log_info "Copying plugins to tools directory..."
log_debug "  Preserving full directory structure"

mkdir -p "$PLUGINS_DIR"

# Use cp -a to preserve symlinks and directory structure
if cp -a "$PACKER_CONFIG_DIR"/* "$PLUGINS_DIR"/; then
    log_info "  ✓ Plugins copied successfully"
else
    log_error "  ✗ Failed to copy plugins"
    exit 1
fi

# Count plugins
PLUGIN_COUNT=$(find "$PLUGINS_DIR" -type f -name "packer-plugin-*" | wc -l)
log_info "Copied ${PLUGIN_COUNT} plugin file(s)"

# Calculate total size
TOTAL_SIZE=$(du -sh "$PLUGINS_DIR" | awk '{print $1}')
log_info "Total size: ${TOTAL_SIZE}"

# Create plugins manifest
MANIFEST_FILE="${PLUGINS_DIR}/PLUGINS.txt"
log_info "Creating plugins manifest..."

cat > "$MANIFEST_FILE" <<EOF
# Packer Plugins Manifest
# Downloaded on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Packer Version: $(packer version | head -1)

Plugin Directory Structure
==========================

Plugins are organized in the standard Packer plugin cache structure:
  github.com/{organization}/{plugin-name}/{version}/{os}_{arch}/

This preserves compatibility with Packer's plugin loading mechanism.

Downloaded Plugins
==================
EOF

# Find and list all plugin binaries
find "$PLUGINS_DIR" -type f -name "packer-plugin-*" | sort | while read -r plugin; do
    # Extract plugin information from path
    # Path format: github.com/hashicorp/amazon/packer-plugin-amazon_v1.3.3_x5.0_linux_amd64
    rel_path="${plugin#${PLUGINS_DIR}/}"
    filename=$(basename "$plugin")
    size=$(du -h "$plugin" | awk '{print $1}')
    sha256=$(sha256sum "$plugin" | awk '{print $1}')
    
    # Extract organization and plugin name from path
    org=$(echo "$rel_path" | cut -d'/' -f2)
    plugin_name=$(echo "$rel_path" | cut -d'/' -f3)
    
    # Extract version from filename (format: packer-plugin-NAME_vVERSION_xAPI_OS_ARCH)
    version=$(echo "$filename" | sed -n 's/.*_v\([0-9.]*\)_x.*/\1/p')
    
    echo "${org}/${plugin_name}" >> "$MANIFEST_FILE"
    echo "  Version: ${version}" >> "$MANIFEST_FILE"
    echo "  File: ${filename}" >> "$MANIFEST_FILE"
    echo "  Path: ${rel_path}" >> "$MANIFEST_FILE"
    echo "  Size: ${size}" >> "$MANIFEST_FILE"
    echo "  SHA256: ${sha256}" >> "$MANIFEST_FILE"
    echo "" >> "$MANIFEST_FILE"
done

cat >> "$MANIFEST_FILE" <<EOF

Total Plugin Files: ${PLUGIN_COUNT}
Total Size: ${TOTAL_SIZE}

Directory Structure
===================
EOF

# Show directory tree
find "$PLUGINS_DIR" -type d | sort | while read -r dir; do
    rel_path="${dir#${PLUGINS_DIR}/}"
    if [ -n "$rel_path" ]; then
        depth=$(echo "$rel_path" | tr -cd '/' | wc -c)
        indent=$(printf '%*s' $((depth * 2)) '')
        dirname=$(basename "$dir")
        echo "${indent}${dirname}/" >> "$MANIFEST_FILE"
    fi
done

cat >> "$MANIFEST_FILE" <<EOF

Usage in NIPR Environment
==========================

After extraction, set the PACKER_PLUGIN_PATH environment variable:

  export PACKER_PLUGIN_PATH="\${PWD}/tools/packer/plugins"

Or create a Packer configuration file (.packerconfig) in your home directory:

  cat > ~/.packerconfig <<'PACKEREOF'
  plugin_directory = "/path/to/spel/tools/packer/plugins"
  PACKEREOF

Verification:

  # Set plugin path
  export PACKER_PLUGIN_PATH="\${PWD}/tools/packer/plugins"
  
  # Validate template (will use offline plugins)
  packer validate spel/minimal-linux.pkr.hcl
  
  # Check if plugins are loaded
  packer plugins installed

Plugin Requirements
===================

These plugins are required by SPEL Packer templates:

hashicorp/amazon (>= 1.3.3):
  - Purpose: Build Amazon Machine Images (AMIs)
  - Used by: All AWS builds
  - Builders: amazon-ebs, amazon-ebssurrogate, amazon-instance

hashicorp/ansible (>= 1.1.0):
  - Purpose: Run Ansible provisioners
  - Used by: Hardened Linux builds with STIG/CIS roles
  - Provisioner: ansible

rgl/windows-update (>= 0.17.1):
  - Purpose: Install Windows updates
  - Used by: Windows AMI builds
  - Provisioner: windows-update

hashicorp/azure (~> 1):
  - Purpose: Build Azure VM images
  - Used by: Azure builds
  - Builder: azure-arm

hashicorp/openstack (~> 1):
  - Purpose: Build OpenStack images
  - Used by: OpenStack builds
  - Builder: openstack

hashicorp/vagrant (~> 1):
  - Purpose: Build Vagrant boxes
  - Used by: Vagrant builds
  - Builder: vagrant

hashicorp/virtualbox (>= 1.1.1):
  - Purpose: Build VirtualBox images
  - Used by: Local testing builds
  - Builder: virtualbox-iso

Notes
=====

- Plugins are platform-specific (linux_amd64)
- Full directory structure is preserved for compatibility
- Symlinks are dereferenced (converted to regular files) during archive creation
- Plugin versions are determined by Packer templates at download time
- API versions (x5.0, etc.) are Packer's internal plugin API compatibility markers

Troubleshooting
===============

If Packer cannot find plugins:

1. Verify PACKER_PLUGIN_PATH is set:
   echo \$PACKER_PLUGIN_PATH

2. Check plugin directory exists:
   ls -la tools/packer/plugins/

3. Verify plugin structure:
   find tools/packer/plugins/ -name "packer-plugin-*"

4. Check Packer configuration:
   packer plugins installed

5. Try explicit plugin path in template:
   packer build -var="plugin_path=\${PWD}/tools/packer/plugins" spel/minimal-linux.pkr.hcl
EOF

log_info "Manifest created: ${MANIFEST_FILE}"

# Display summary
log_info ""
log_info "========================================="
log_info "Packer Plugins Download Complete!"
log_info "========================================="
log_info ""
log_info "Downloaded plugins:"

# Group plugins by organization/name
find "$PLUGINS_DIR" -type f -name "packer-plugin-*" | sort | while read -r plugin; do
    rel_path="${plugin#${PLUGINS_DIR}/}"
    filename=$(basename "$plugin")
    size=$(du -h "$plugin" | awk '{print $1}')
    
    org=$(echo "$rel_path" | cut -d'/' -f2)
    plugin_name=$(echo "$rel_path" | cut -d'/' -f3)
    version=$(echo "$filename" | sed -n 's/.*_v\([0-9.]*\)_x.*/\1/p')
    
    printf "  %-30s v%-10s %10s\n" "${org}/${plugin_name}" "$version" "$size"
done

log_info ""
log_info "Summary:"
log_info "  Total plugins: ${PLUGIN_COUNT}"
log_info "  Total size: ${TOTAL_SIZE}"
log_info "  Location: ${PLUGINS_DIR}"
log_info "  Manifest: ${MANIFEST_FILE}"
log_info ""
log_info "NIPR Usage:"
log_info "  export PACKER_PLUGIN_PATH=\"\${PWD}/tools/packer/plugins\""
log_info "  packer validate spel/minimal-linux.pkr.hcl"
log_info "========================================="
