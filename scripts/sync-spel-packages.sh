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
DOWNLOAD_SUCCESS=0
for rpm in "spel-release-latest-8.noarch.rpm" "spel-release-latest-9.noarch.rpm"; do
    if wget -nv -N -P "$MIRROR_BASE" "${SPEL_REPO_BASE}/${rpm}"; then
        log_info "Downloaded: $rpm"
        DOWNLOAD_SUCCESS=1
    else
        log_warn "Failed to download: $rpm"
    fi
done

if [ $DOWNLOAD_SUCCESS -eq 0 ]; then
    log_error "Failed to download any SPEL release packages"
    log_error "This may indicate the repository is unavailable or the URL has changed"
    log_error "Repository: $SPEL_REPO_BASE"
    exit 1
fi

# Create local repository metadata from downloaded packages
log_info "Creating repository metadata..."
if ! createrepo_c "$MIRROR_BASE"; then
    log_error "Failed to create repository metadata"
    exit 1
fi

# Calculate total size
TOTAL_SIZE=$(du -sh "$MIRROR_BASE" | awk '{print $1}')
log_info "Total SPEL packages mirror size: $TOTAL_SIZE"

log_info "SPEL packages sync complete!"
log_info "Mirror location: $MIRROR_BASE"
