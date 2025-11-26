#!/bin/bash
#
# Sync SPEL custom packages for NIPR offline builds
# Downloads only the latest spel-release RPMs and current package versions
# Run this on a system with internet access before transferring to NIPR
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR_BASE="${SCRIPT_DIR}/../mirrors/spel-packages"
SPEL_REPO_BASE="https://spel-packages.cloudarmor.io/spel-packages/repo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for required commands
for cmd in wget createrepo_c; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is required but not installed"
        exit 1
    fi
done

mkdir -p "$MIRROR_BASE"

log_info "Downloading SPEL release packages..."

# Download spel-release packages
wget -N -P "$MIRROR_BASE" \
    "${SPEL_REPO_BASE}/spel-release-latest-8.noarch.rpm" \
    "${SPEL_REPO_BASE}/spel-release-latest-9.noarch.rpm" \
    || log_warn "Failed to download some spel-release packages"

# Get list of packages from the repository
log_info "Fetching package list from SPEL repository..."

# Download repodata to discover available packages
mkdir -p "${MIRROR_BASE}/repodata"
wget -N -P "${MIRROR_BASE}/repodata" \
    "${SPEL_REPO_BASE}/repodata/repomd.xml" \
    || log_error "Failed to download repomd.xml"

# Extract primary.xml location from repomd.xml
PRIMARY_XML=$(grep -A2 'type="primary"' "${MIRROR_BASE}/repodata/repomd.xml" | \
    grep 'location href' | sed 's/.*href="//;s/".*//')

if [ -n "$PRIMARY_XML" ]; then
    log_info "Downloading primary package metadata..."
    wget -N -P "${MIRROR_BASE}" \
        "${SPEL_REPO_BASE}/${PRIMARY_XML}" \
        || log_warn "Failed to download primary.xml"
    
    # Extract package URLs from primary XML (simplified - adjust based on actual format)
    # This downloads all current packages - uncomment if you want full mirror
    # gunzip -c "${MIRROR_BASE}/${PRIMARY_XML}" | \
    #     grep -oP 'location href="\K[^"]+' | \
    #     while read -r pkg; do
    #         wget -N -P "$MIRROR_BASE" "${SPEL_REPO_BASE}/${pkg}"
    #     done
fi

log_info "Creating repository metadata..."
createrepo_c --update "$MIRROR_BASE" || log_error "Failed to create repository metadata"

# Calculate total size
TOTAL_SIZE=$(du -sh "$MIRROR_BASE" | awk '{print $1}')
log_info "Total SPEL packages mirror size: $TOTAL_SIZE"

log_info "SPEL packages sync complete!"
log_info "Mirror location: $MIRROR_BASE"
