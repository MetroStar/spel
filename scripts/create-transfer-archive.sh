#!/bin/bash
#
# Create optimized transfer archive for NIPR deployment
# This script creates separate archives for different components
# allowing selective transfer and partial updates
#
# STORAGE OPTIMIZATION:
# - Separate archives for base, mirrors, and tools
# - Excludes unnecessary files (.git, caches, etc.)
# - Includes only compressed mirrors if available
# - Generates SHA256 checksums for verification
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATE=$(date +%Y%m%d)
OUTPUT_DIR="${SPEL_ARCHIVE_OUTPUT:-${REPO_ROOT}}"

# Configuration
CREATE_SEPARATE="${SPEL_ARCHIVE_SEPARATE:-true}"
CREATE_COMBINED="${SPEL_ARCHIVE_COMBINED:-true}"
# Note: Mirrors are not synced for NIPR - NIPR has its own RPM repositories

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

log_info "Creating NIPR transfer archives..."
log_debug "  Repository root: $REPO_ROOT"
log_debug "  Output directory: $OUTPUT_DIR"
log_debug "  Create separate archives: $CREATE_SEPARATE"
log_debug "  Create combined archive: $CREATE_COMBINED"
log_debug "  Include mirrors: false (NIPR has its own RPM repositories)"

# Common exclusions
COMMON_EXCLUDES=(
    --exclude='.git'
    --exclude='.gitignore'
    --exclude='*.pyc'
    --exclude='__pycache__'
    --exclude='.DS_Store'
    --exclude='*.swp'
    --exclude='*.tmp'
)

# Function to create archive with progress
create_archive() {
    local archive_name=$1
    local description=$2
    shift 2
    local include_patterns=("$@")
    
    log_info "Creating $description..."
    
    # Create temporary directory for archive creation
    local temp_archive_dir=$(mktemp -d)
    local temp_archive="${temp_archive_dir}/${archive_name}"
    
    # Create archive in temp location to avoid "file changed as we read it" error
    if tar czf "${temp_archive}" \
        "${COMMON_EXCLUDES[@]}" \
        "${include_patterns[@]}"; then
        
        # Move archive to final destination
        mv "${temp_archive}" "${OUTPUT_DIR}/${archive_name}"
        rm -rf "$temp_archive_dir"
        
        local size=$(du -h "${OUTPUT_DIR}/${archive_name}" | awk '{print $1}')
        log_info "  Created: ${archive_name} ($size)"
        
        # Generate SHA256
        (cd "$OUTPUT_DIR" && sha256sum "${archive_name}" > "${archive_name}.sha256")
        log_debug "  Checksum: ${archive_name}.sha256"
        
        return 0
    else
        log_error "  Failed to create ${archive_name}"
        rm -rf "$temp_archive_dir"
        return 1
    fi
}

# Create separate component archives
if [ "$CREATE_SEPARATE" = "true" ]; then
    log_info "Creating separate component archives..."
    
    # 1. Base archive (code, scripts, configs)
    log_info "Creating base archive..."
    create_archive "spel-base-${DATE}.tar.gz" "base archive" \
        --exclude='offline-packages/*.zip' \
        --exclude='offline-packages/*.tar.gz' \
        --exclude='offline-packages/*.rpm' \
        --exclude='spel/ansible/roles/*/.git' \
        --exclude='vendor/*/.git' \
        --exclude='spel-*.tar.gz' \
        --exclude='spel-*.tar.gz.sha256' \
        --exclude='*.tar.gz' \
        --exclude='*.tar.gz.sha256' \
        .
    
    # 2. Tools archive (if tools exist)
    if [ -d "tools" ] || [ -d "offline-packages" ] || [ -d "mirrors/spel-packages" ] || [ -d "spel/ansible/collections" ]; then
        log_info "Creating tools, SPEL packages, offline packages, and collections archive..."
        
        # Create temporary staging for tools
        TEMP_TOOLS=$(mktemp -d)
        trap "rm -rf $TEMP_TOOLS" EXIT
        
        # Copy tools if they exist (includes Python deps, Packer binaries, and plugins)
        if [ -d "tools" ]; then
            log_debug "  Copying tools directory (Python deps, Packer binaries, plugins)..."
            # Use --dereference to follow symlinks in Packer plugins
            cp -rL tools "$TEMP_TOOLS/"
        fi
        
        # Copy offline packages if they exist
        if [ -d "offline-packages" ]; then
            log_debug "  Copying offline packages..."
            cp -r offline-packages "$TEMP_TOOLS/"
        fi
        
        # Copy SPEL packages if they exist
        if [ -d "mirrors/spel-packages" ]; then
            log_debug "  Copying SPEL packages..."
            mkdir -p "$TEMP_TOOLS/mirrors"
            cp -r mirrors/spel-packages "$TEMP_TOOLS/mirrors/"
        fi
        
        # Copy Ansible collections if they exist (tarballs)
        if [ -d "spel/ansible/collections" ]; then
            log_debug "  Copying Ansible collections..."
            mkdir -p "$TEMP_TOOLS/spel/ansible"
            cp -r spel/ansible/collections "$TEMP_TOOLS/spel/ansible/"
        fi
        
        # Copy compressed archives if they exist
        [ -f "ansible-roles.tar.gz" ] && cp ansible-roles.tar.gz "$TEMP_TOOLS/"
        [ -f "offline-packages.tar.gz" ] && cp offline-packages.tar.gz "$TEMP_TOOLS/"
        
        create_archive "spel-tools-${DATE}.tar.gz" "tools archive" \
            -p -C "$TEMP_TOOLS" .
    fi
fi

# Create combined archive
if [ "$CREATE_COMBINED" = "true" ]; then
    log_info "Creating combined archive..."
    
    COMBINED_EXCLUDES=("${COMMON_EXCLUDES[@]}")
    
    # Exclude unnecessary files
    COMBINED_EXCLUDES+=(
        --exclude='spel/ansible/roles/*/.git'
        --exclude='vendor/*/.git'
    )
    
    create_archive "spel-nipr-complete-${DATE}.tar.gz" "combined archive" \
        "${COMBINED_EXCLUDES[@]}" \
        .
fi

# Generate master checksum file
log_info "Generating master checksum file..."
CHECKSUM_FILE="${OUTPUT_DIR}/spel-nipr-${DATE}-checksums.txt"

cat > "$CHECKSUM_FILE" <<EOF
# SPEL NIPR Transfer Archives - SHA256 Checksums
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# 
# Verify with: sha256sum -c spel-nipr-${DATE}-checksums.txt
#

EOF

cd "$OUTPUT_DIR"
for archive in spel-*-${DATE}.tar.gz; do
    if [ -f "$archive" ]; then
        sha256sum "$archive" >> "$CHECKSUM_FILE"
    fi
done

log_info "Master checksum file created: spel-nipr-${DATE}-checksums.txt"

# Display summary
log_info ""
log_info "Transfer archives created successfully!"
log_info ""
log_info "Archives:"

cd "$OUTPUT_DIR"
for archive in spel-*-${DATE}.tar.gz; do
    if [ -f "$archive" ]; then
        size=$(du -h "$archive" | awk '{print $1}')
        printf "  %-45s %8s\n" "$archive" "$size"
    fi
done

TOTAL_SIZE=$(du -ch spel-*-${DATE}.tar.gz 2>/dev/null | tail -1 | awk '{print $1}')
log_info ""
log_info "Total size: $TOTAL_SIZE"
log_info ""
log_info "Next steps:"
log_info "  1. Verify checksums: sha256sum -c spel-nipr-${DATE}-checksums.txt"
log_info "  2. Transfer to NIPR (Note: Mirrors NOT included - use NIPR RPM repos)"
log_info "  3. Verify checksums on NIPR side"
log_info "  4. Extract using scripts/extract-nipr-archives.sh"
