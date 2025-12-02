#!/bin/bash
#
# Extract and configure NIPR transfer archives
# Run this script on NIPR system after transferring archives
#
# This script:
# - Extracts compressed archives
# - Decompresses repository mirrors
# - Sets up directory structure
# - Validates extraction
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
ARCHIVE_DIR="${SPEL_ARCHIVE_DIR:-${REPO_ROOT}}"
VERIFY_CHECKSUMS="${SPEL_VERIFY_CHECKSUMS:-true}"
CLEANUP_ARCHIVES="${SPEL_CLEANUP_ARCHIVES:-false}"

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
for cmd in tar sha256sum; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is required but not installed"
        exit 1
    fi
done

cd "$REPO_ROOT"

log_info "NIPR archive extraction configuration:"
log_debug "  Repository root: $REPO_ROOT"
log_debug "  Archive directory: $ARCHIVE_DIR"
log_debug "  Verify checksums: $VERIFY_CHECKSUMS"
log_debug "  Cleanup archives after extraction: $CLEANUP_ARCHIVES"

# Find checksum file
CHECKSUM_FILE=$(ls "${ARCHIVE_DIR}"/spel-nipr-*-checksums.txt 2>/dev/null | head -1)

if [ -z "$CHECKSUM_FILE" ]; then
    log_warn "No checksum file found, skipping verification"
    VERIFY_CHECKSUMS=false
fi

# Verify checksums if enabled
if [ "$VERIFY_CHECKSUMS" = "true" ]; then
    log_info "Verifying archive checksums..."
    
    cd "$ARCHIVE_DIR"
    if sha256sum -c "$CHECKSUM_FILE"; then
        log_info "  ✓ All checksums verified successfully"
    else
        log_error "  ✗ Checksum verification failed!"
        log_error "Archives may be corrupted. Aborting extraction."
        exit 1
    fi
    cd "$REPO_ROOT"
fi

# Extract base archive
BASE_ARCHIVE=$(ls "${ARCHIVE_DIR}"/spel-base-*.tar.gz 2>/dev/null | head -1)
if [ -n "$BASE_ARCHIVE" ]; then
    log_info "Extracting base archive..."
    tar xzf "$BASE_ARCHIVE" -C "$REPO_ROOT"
    log_info "  ✓ Base archive extracted"
else
    log_warn "No base archive found (spel-base-*.tar.gz)"
fi

# Extract tools archive
TOOLS_ARCHIVE=$(ls "${ARCHIVE_DIR}"/spel-tools-*.tar.gz 2>/dev/null | head -1)
if [ -n "$TOOLS_ARCHIVE" ]; then
    log_info "Extracting tools archive..."
    tar xzf "$TOOLS_ARCHIVE" -C "$REPO_ROOT"
    
    # Extract nested compressed archives
    if [ -f "${REPO_ROOT}/ansible-roles.tar.gz" ]; then
        log_info "Extracting Ansible roles..."
        mkdir -p "${REPO_ROOT}/spel/ansible/roles"
        tar xzf "${REPO_ROOT}/ansible-roles.tar.gz" -C "${REPO_ROOT}/spel/ansible"
        
        if [ "$CLEANUP_ARCHIVES" = "true" ]; then
            rm "${REPO_ROOT}/ansible-roles.tar.gz"
        fi
    fi
    
    if [ -f "${REPO_ROOT}/offline-packages.tar.gz" ]; then
        log_info "Extracting offline packages..."
        tar xzf "${REPO_ROOT}/offline-packages.tar.gz" -C "$REPO_ROOT"
        
        if [ "$CLEANUP_ARCHIVES" = "true" ]; then
            rm "${REPO_ROOT}/offline-packages.tar.gz"
        fi
    fi
    
    # Extract Ansible collection tarballs if they exist
    # Note: Collections will be installed by ci-setup.sh, we just need to keep the tarballs
    if [ -d "${REPO_ROOT}/spel/ansible/collections" ]; then
        COLLECTION_TARBALLS=$(find "${REPO_ROOT}/spel/ansible/collections" -name "*.tar.gz" -type f 2>/dev/null || true)
        
        if [ -n "$COLLECTION_TARBALLS" ]; then
            log_info "Found Ansible collection tarballs"
            TARBALL_COUNT=$(echo "$COLLECTION_TARBALLS" | wc -l)
            log_debug "  Collection tarballs: ${TARBALL_COUNT}"
            log_info "  ✓ Collections will be installed by ci-setup.sh"
        fi
    fi
    
    log_info "  ✓ Tools archive extracted"
else
    log_warn "No tools archive found (spel-tools-*.tar.gz)"
fi

# Extract combined archive if separate archives weren't found
COMBINED_ARCHIVE=$(ls "${ARCHIVE_DIR}"/spel-nipr-complete-*.tar.gz 2>/dev/null | head -1)
if [ -z "$BASE_ARCHIVE" ] && [ -z "$MIRRORS_ARCHIVE" ] && [ -n "$COMBINED_ARCHIVE" ]; then
    log_info "Extracting combined archive..."
    tar xzf "$COMBINED_ARCHIVE" -C "$REPO_ROOT"
    log_info "  ✓ Combined archive extracted"
fi

# Initialize git submodules
if [ -f "${REPO_ROOT}/.gitmodules" ]; then
    log_info "Initializing git submodules..."
    
    if git submodule init && git submodule update; then
        log_info "  ✓ Git submodules initialized"
    else
        log_warn "  ⚠ Git submodule initialization had warnings (this may be expected)"
    fi
fi

# Validation
log_info "Validating extraction..."

ERRORS=0

# Check key directories
for dir in spel offline-packages tools; do
    if [ -d "${REPO_ROOT}/${dir}" ]; then
        log_debug "  ✓ ${dir}/ exists"
    else
        log_warn "  ⚠ ${dir}/ not found (may not be required)"
    fi
done

# Check new component directories
if [ -d "${REPO_ROOT}/tools/python-deps" ]; then
    log_debug "  ✓ Python dependencies found"
    wheel_count=$(find "${REPO_ROOT}/tools/python-deps" -name "*.whl" 2>/dev/null | wc -l)
    log_debug "    Wheel files: ${wheel_count}"
fi

if [ -d "${REPO_ROOT}/spel/ansible/collections/ansible_collections" ]; then
    log_debug "  ✓ Ansible collections extracted"
    collection_count=$(find "${REPO_ROOT}/spel/ansible/collections/ansible_collections" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l)
    log_debug "    Collections: ${collection_count}"
fi

if [ -d "${REPO_ROOT}/tools/packer/linux_amd64" ]; then
    log_debug "  ✓ Packer Linux binary found"
fi

if [ -d "${REPO_ROOT}/tools/packer/windows_amd64" ]; then
    log_debug "  ✓ Packer Windows binary found"
fi

if [ -d "${REPO_ROOT}/tools/packer/plugins" ]; then
    log_debug "  ✓ Packer plugins found"
    plugin_count=$(find "${REPO_ROOT}/tools/packer/plugins" -name "packer-plugin-*" -type f 2>/dev/null | wc -l)
    log_debug "    Plugin files: ${plugin_count}"
fi

# Check for Packer templates
if [ -f "${REPO_ROOT}/spel/minimal-linux.pkr.hcl" ]; then
    log_debug "  ✓ Packer templates found"
else
    log_error "  ✗ Packer templates missing!"
    ((ERRORS++))
fi

# Check for scripts (sync-mirrors.sh was removed - NIPR has its own repos)
if [ -f "${REPO_ROOT}/scripts/extract-nipr-archives.sh" ]; then
    log_debug "  ✓ Scripts found"
else
    log_error "  ✗ Scripts missing!"
    ((ERRORS++))
fi

# Display summary
log_info ""
log_info "Extraction complete!"

if [ $ERRORS -eq 0 ]; then
    log_info "✓ All validations passed"
else
    log_error "✗ $ERRORS validation error(s) found"
fi

log_info ""
log_info "Directory structure:"
du -sh "${REPO_ROOT}"/{spel,offline-packages,tools,vendor} 2>/dev/null | \
    awk '{printf "  %-20s %8s\n", $2, $1}' || true

log_info ""
log_info "Next steps:"
log_info "  1. Install Ansible Core (if extracted):"
log_info "     pip install --no-index --find-links tools/python-deps/ 'ansible-core>=2.16.0,<2.19.0'"
log_info "  2. Install Packer (Linux):"
log_info "     sudo install -m 755 tools/packer/linux_amd64/packer /usr/local/bin/packer"
log_info "  3. Set Packer plugin path:"
log_info "     export PACKER_PLUGIN_PATH=\"\${PWD}/tools/packer/plugins\""
log_info "  4. Configure to use NIPR RPM repositories (no local mirrors needed)"
log_info "  5. Set GitLab CI variables (see docs/CI-CD-Setup.md)"
log_info "  6. Test environment: ./build/ci-setup.sh"
log_info "  7. Validate Packer: packer validate spel/minimal-linux.pkr.hcl"

if [ "$CLEANUP_ARCHIVES" = "true" ]; then
    log_info ""
    log_warn "Archive cleanup is enabled - original archives have been removed"
fi
