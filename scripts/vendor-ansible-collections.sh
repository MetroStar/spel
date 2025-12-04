#!/bin/bash
#
# Vendor Ansible collections for offline Offline builds
# Run this on a system with internet access before transferring to Offline
#
# This script downloads:
# - ansible.windows (latest version)
# - community.windows (latest version)
#
# Collections are kept as tarballs for smaller transfer size
# They will be extracted in Offline environment during archive extraction
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTIONS_DIR="${SCRIPT_DIR}/../spel/ansible/collections"

# Configuration
# Pin collections to specific versions compatible with Ansible Core 2.15
# Using exact version numbers to ensure ansible-galaxy downloads the correct versions
# - ansible.windows 1.14.0 is the last 1.x release (supports Ansible Core 2.14-2.15)
# - community.windows 1.13.0 is the last 1.x release (supports Ansible Core 2.14-2.15)
# - community.general 7.5.0 is a stable 7.x release (supports Ansible Core 2.14-2.15)
COLLECTIONS=(
    "ansible.windows:1.14.0"
    "community.windows:1.13.0"
    "community.general:7.5.0"
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
for cmd in ansible-galaxy; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is required but not installed"
        log_error "Please install Ansible first: pip install ansible-core"
        exit 1
    fi
done

log_info "Ansible collection download configuration:"
log_debug "  Target directory: ${COLLECTIONS_DIR}"
log_debug "  Collections: ${COLLECTIONS[*]}"
log_debug "  Format: Tarballs (not extracted)"

mkdir -p "$COLLECTIONS_DIR"

# Note about ANSIBLE_GALAXY_TOKEN
if [ -n "${ANSIBLE_GALAXY_TOKEN:-}" ]; then
    log_info "Using ANSIBLE_GALAXY_TOKEN for authentication"
    log_debug "  Token length: ${#ANSIBLE_GALAXY_TOKEN} characters"
else
    log_debug "No ANSIBLE_GALAXY_TOKEN set (not required for public collections)"
fi

# Download collections
log_info "Downloading Ansible collections..."
log_info "  Strategy: Always download latest versions for newest bug fixes and features"

for collection in "${COLLECTIONS[@]}"; do
    log_info "Downloading ${collection}..."
    
    if ansible-galaxy collection download \
        --download-path "$COLLECTIONS_DIR" \
        "$collection" 2>&1 | tee "/tmp/galaxy-${collection}.log"; then
        
        log_info "  ✓ ${collection} downloaded successfully"
    else
        log_error "  ✗ Failed to download ${collection}"
        log_error "Check /tmp/galaxy-${collection}.log for details"
        exit 1
    fi
done

# Find downloaded tarballs
log_info "Locating downloaded collection tarballs..."
TARBALLS=$(find "$COLLECTIONS_DIR" -name "*.tar.gz" -type f | sort)
TARBALL_COUNT=$(echo "$TARBALLS" | wc -l)

if [ $TARBALL_COUNT -eq 0 ]; then
    log_error "No collection tarballs found!"
    exit 1
fi

log_info "Found ${TARBALL_COUNT} collection tarball(s)"

# Create manifest
MANIFEST_FILE="${COLLECTIONS_DIR}/MANIFEST.txt"
log_info "Creating collection manifest..."

cat > "$MANIFEST_FILE" <<EOF
# Ansible Collections Manifest
# Downloaded on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Collections Downloaded
======================
EOF

echo "$TARBALLS" | while read -r tarball; do
    filename=$(basename "$tarball")
    size=$(du -h "$tarball" | awk '{print $1}')
    sha256=$(sha256sum "$tarball" | awk '{print $1}')
    
    # Extract namespace and collection name from tarball
    # Format: namespace-collection-version.tar.gz
    namespace=$(echo "$filename" | cut -d'-' -f1)
    collection=$(echo "$filename" | cut -d'-' -f2)
    version=$(echo "$filename" | sed 's/.*-\([0-9]\+\.[0-9]\+\.[0-9]\+\)\.tar\.gz/\1/')
    
    echo "${namespace}.${collection}" >> "$MANIFEST_FILE"
    echo "  Version: ${version}" >> "$MANIFEST_FILE"
    echo "  File: ${filename}" >> "$MANIFEST_FILE"
    echo "  Size: ${size}" >> "$MANIFEST_FILE"
    echo "  SHA256: ${sha256}" >> "$MANIFEST_FILE"
    echo "" >> "$MANIFEST_FILE"
done

# Calculate total size
TOTAL_SIZE=$(du -sh "$COLLECTIONS_DIR" | awk '{print $1}')

cat >> "$MANIFEST_FILE" <<EOF

Total Collections: ${TARBALL_COUNT}
Total Size: ${TOTAL_SIZE}

Extraction Instructions
=======================

Collections are stored as tarballs for smaller transfer size.
They will be automatically extracted during Offline archive extraction.

Manual extraction (if needed):

1. Create collections directory:
   mkdir -p spel/ansible/collections/ansible_collections

2. Extract each tarball:
   for tarball in spel/ansible/collections/*.tar.gz; do
       tar -xzf "\$tarball" -C spel/ansible/collections/ansible_collections/
   done

3. Verify installation:
   ansible-galaxy collection list

Installation from tarballs:
   ansible-galaxy collection install spel/ansible/collections/*.tar.gz -p spel/ansible/collections/

Version Information
===================

Collections are downloaded with latest available versions at workflow execution time.
This ensures you have the newest bug fixes and features available.

To pin specific versions, modify scripts/vendor-ansible-collections.sh:
  ansible-galaxy collection download ansible.windows:1.14.0

Collection Details
==================

ansible.windows:
  Purpose: Core Windows management modules
  Required for: Windows AMI builds, WinRM connectivity
  Key modules: win_command, win_shell, win_copy, win_feature

community.windows:
  Purpose: Community-contributed Windows modules
  Required for: Advanced Windows configuration, updates
  Key modules: win_domain, win_disk_facts, win_firewall_rule
EOF

# Create README
README_FILE="${COLLECTIONS_DIR}/README.txt"
log_info "Creating README..."

cat > "$README_FILE" <<EOF
# Ansible Collections for SPEL Offline Builds
# Downloaded: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

This directory contains Ansible collections required for offline Offline builds.

## Contents

- ansible.windows: Core Windows management modules
- community.windows: Community Windows modules

## Format

Collections are stored as compressed tarballs (.tar.gz) for efficient transfer.
They will be automatically extracted during Offline archive extraction.

## Authentication (Optional)

For private Ansible Galaxy collections, set the ANSIBLE_GALAXY_TOKEN environment
variable before running the download script:

  export ANSIBLE_GALAXY_TOKEN="your-token-here"
  ./scripts/vendor-ansible-collections.sh

Public collections (like ansible.windows and community.windows) do not require
authentication.

To obtain a token:
1. Log in to https://galaxy.ansible.com
2. Go to Preferences > API Key
3. Copy your token

## Version Strategy

Collections are always downloaded with the latest available version at workflow
execution time. This ensures you have the newest bug fixes, security patches,
and features.

Benefits:
- Latest security fixes
- Newest features and modules
- Bug fixes from community

If you need reproducible builds with specific versions, modify the download
script to pin versions:

  ansible-galaxy collection download ansible.windows:1.14.0

## Usage in Offline

After extraction, collections will be available at:
  spel/ansible/collections/ansible_collections/

Ansible will automatically find them when running playbooks from the spel/
directory, or you can specify the path explicitly:

  export ANSIBLE_COLLECTIONS_PATH="\${PWD}/spel/ansible/collections"

## Verification

To verify collections are properly installed:

  ansible-galaxy collection list

Expected output:
  # /path/to/spel/ansible/collections/ansible_collections
  Collection        Version
  ----------------- -------
  ansible.windows   X.Y.Z
  community.windows X.Y.Z

## Size Optimization

Collections are kept as tarballs during transfer:
- Smaller archive size (~30 MB vs ~50 MB extracted)
- Faster checksum verification
- Simpler archive management

Extraction happens automatically during ./scripts/extract-offline-archives.sh

## Support

For collection documentation:
- ansible.windows: https://docs.ansible.com/ansible/latest/collections/ansible/windows/
- community.windows: https://docs.ansible.com/ansible/latest/collections/community/windows/

For issues with collection downloads or authentication:
- Check Ansible Galaxy status: https://galaxy.ansible.com
- Verify network connectivity
- Confirm token validity (if using private collections)
EOF

log_info "README created: ${README_FILE}"

# Display summary
log_info ""
log_info "========================================="
log_info "Ansible Collections Download Complete!"
log_info "========================================="
log_info ""
log_info "Downloaded collections:"

echo "$TARBALLS" | while read -r tarball; do
    filename=$(basename "$tarball")
    size=$(du -h "$tarball" | awk '{print $1}')
    namespace=$(echo "$filename" | cut -d'-' -f1)
    collection=$(echo "$filename" | cut -d'-' -f2)
    version=$(echo "$filename" | sed 's/.*-\([0-9]\+\.[0-9]\+\.[0-9]\+\)\.tar\.gz/\1/')
    
    printf "  %-25s v%-10s %10s\n" "${namespace}.${collection}" "$version" "$size"
done

log_info ""
log_info "Summary:"
log_info "  Total collections: ${TARBALL_COUNT}"
log_info "  Total size: ${TOTAL_SIZE}"
log_info "  Location: ${COLLECTIONS_DIR}"
log_info "  Manifest: ${MANIFEST_FILE}"
log_info "  README: ${README_FILE}"
log_info ""
log_info "Collections are stored as tarballs for efficient transfer"
log_info "They will be extracted automatically in Offline environment"
log_info "========================================="
