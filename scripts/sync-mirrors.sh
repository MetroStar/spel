#!/bin/bash
#
# Sync YUM/DNF repository mirrors for NIPR offline builds
# This script downloads the latest packages from public repositories
# Run this on a system with internet access before transferring to NIPR
#
# STORAGE OPTIMIZATION:
# - Uses --newest-only to keep only latest package versions
# - Excludes debuginfo/source packages by default
# - Supports compression to reduce transfer size
# - Can use hardlinks to deduplicate files
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR_BASE="${SCRIPT_DIR}/../mirrors"

# Configuration options
EXCLUDE_DEBUG="${SPEL_MIRROR_EXCLUDE_DEBUG:-true}"
EXCLUDE_SOURCE="${SPEL_MIRROR_EXCLUDE_SOURCE:-true}"
EXCLUDE_DEVEL="${SPEL_MIRROR_EXCLUDE_DEVEL:-false}"
COMPRESS_REPOS="${SPEL_MIRROR_COMPRESS:-false}"
USE_HARDLINKS="${SPEL_MIRROR_HARDLINK:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Display configuration
log_info "Mirror sync configuration:"
log_debug "  Base directory: $MIRROR_BASE"
log_debug "  Exclude debug packages: $EXCLUDE_DEBUG"
log_debug "  Exclude source packages: $EXCLUDE_SOURCE"
log_debug "  Exclude devel packages: $EXCLUDE_DEVEL"
log_debug "  Compress repositories: $COMPRESS_REPOS"
log_debug "  Use hardlinks: $USE_HARDLINKS"

# Check for required commands
# Note: reposync may be a dnf subcommand (dnf reposync) in newer systems
if command -v reposync &> /dev/null; then
    REPOSYNC_CMD="reposync"
elif dnf reposync --help &> /dev/null; then
    REPOSYNC_CMD="dnf reposync"
else
    log_error "reposync is required but not found (tried 'reposync' and 'dnf reposync')"
    exit 1
fi

for cmd in createrepo_c dnf; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is required but not installed"
        exit 1
    fi
done

log_debug "  Using reposync command: $REPOSYNC_CMD"

sync_repo() {
    local repo_name=$1
    local target_dir=$2
    local distro=$3
    
    log_info "Syncing repository: $repo_name to $target_dir"
    
    mkdir -p "$target_dir"
    
    # Build exclusion list for storage optimization
    local exclude_args=()
    if [ "$EXCLUDE_DEBUG" = "true" ]; then
        exclude_args+=(--exclude='*-debuginfo-*' --exclude='*-debugsource-*')
        log_debug "  Excluding debuginfo packages"
    fi
    if [ "$EXCLUDE_SOURCE" = "true" ]; then
        exclude_args+=(--exclude='*.src.rpm')
        log_debug "  Excluding source RPMs"
    fi
    if [ "$EXCLUDE_DEVEL" = "true" ]; then
        exclude_args+=(--exclude='*-devel-*')
        log_debug "  Excluding devel packages"
    fi
    
    # Sync only the newest packages with metadata
    if ! $REPOSYNC_CMD \
        --repoid="$repo_name" \
        --download-metadata \
        --newest-only \
        --delete \
        "${exclude_args[@]}" \
        --download-path="$target_dir" \
        --norepopath; then
        log_error "Failed to sync $repo_name"
        return 1
    fi
    
    # Create/update repository metadata
    log_info "Creating repository metadata for $repo_name"
    if ! createrepo_c --update "$target_dir"; then
        log_error "Failed to create metadata for $repo_name"
        return 1
    fi
    
    # Compress repository if requested
    if [ "$COMPRESS_REPOS" = "true" ]; then
        log_info "Compressing $repo_name..."
        local parent_dir=$(dirname "$target_dir")
        local repo_dir=$(basename "$target_dir")
        tar czf "${target_dir}.tar.gz" -C "$parent_dir" "$repo_dir"
        local orig_size=$(du -sh "$target_dir" | awk '{print $1}')
        local comp_size=$(du -sh "${target_dir}.tar.gz" | awk '{print $1}')
        log_info "Compressed: $orig_size -> $comp_size (${target_dir}.tar.gz)"
    fi
    
    log_info "Successfully synced $repo_name"
}

# Sync EL8 repositories
log_info "Starting EL8 repository sync..."

if dnf repolist --enabled | grep -q "baseos\|BaseOS"; then
    sync_repo "baseos" "${MIRROR_BASE}/el8/baseos" "el8" || log_warn "Failed to sync EL8 baseos"
fi

if dnf repolist --enabled | grep -q "appstream\|AppStream"; then
    sync_repo "appstream" "${MIRROR_BASE}/el8/appstream" "el8" || log_warn "Failed to sync EL8 appstream"
fi

if dnf repolist --enabled | grep -q "extras"; then
    sync_repo "extras" "${MIRROR_BASE}/el8/extras" "el8" || log_warn "Failed to sync EL8 extras"
fi

if dnf repolist --enabled | grep -q "epel"; then
    sync_repo "epel" "${MIRROR_BASE}/el8/epel" "el8" || log_warn "Failed to sync EL8 EPEL"
fi

# Sync EL9 repositories
log_info "Starting EL9 repository sync..."

if dnf repolist --enabled | grep -q "baseos\|BaseOS"; then
    sync_repo "baseos" "${MIRROR_BASE}/el9/baseos" "el9" || log_warn "Failed to sync EL9 baseos"
fi

if dnf repolist --enabled | grep -q "appstream\|AppStream"; then
    sync_repo "appstream" "${MIRROR_BASE}/el9/appstream" "el9" || log_warn "Failed to sync EL9 appstream"
fi

if dnf repolist --enabled | grep -q "extras"; then
    sync_repo "extras" "${MIRROR_BASE}/el9/extras" "el9" || log_warn "Failed to sync EL9 extras"
fi

if dnf repolist --enabled | grep -q "epel"; then
    sync_repo "epel" "${MIRROR_BASE}/el9/epel" "el9" || log_warn "Failed to sync EL9 EPEL"
fi

# Use hardlinks to deduplicate identical files across repositories
if [ "$USE_HARDLINKS" = "true" ] && command -v hardlink &> /dev/null; then
    log_info "Deduplicating files with hardlinks..."
    hardlink -v "$MIRROR_BASE" || log_warn "Hardlink deduplication had warnings"
elif [ "$USE_HARDLINKS" = "true" ]; then
    log_warn "hardlink command not found, skipping deduplication (install with: dnf install hardlink)"
fi

# Calculate total size
log_info "Calculating mirror size..."
TOTAL_SIZE=$(du -sh "$MIRROR_BASE" | awk '{print $1}')
log_info "Total mirror size: $TOTAL_SIZE"

if [ "$COMPRESS_REPOS" = "true" ]; then
    ARCHIVE_SIZE=$(du -ch "${MIRROR_BASE}"/*/*.tar.gz 2>/dev/null | tail -1 | awk '{print $1}')
    log_info "Total compressed archives: $ARCHIVE_SIZE"
fi

log_info "Mirror sync complete! Run sync-spel-packages.sh to sync SPEL packages."
log_info ""
log_info "Storage optimization tips:"
log_info "  - Set SPEL_MIRROR_COMPRESS=true to create compressed archives"
log_info "  - Set SPEL_MIRROR_EXCLUDE_DEVEL=true to exclude development packages"
log_info "  - Use hardlinks to save space (already applied if available)"
