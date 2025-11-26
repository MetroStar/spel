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
INCLUDE_MIRRORS="${SPEL_ARCHIVE_MIRRORS:-true}"

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
log_debug "  Include mirrors: $INCLUDE_MIRRORS"

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
    
    if tar czf "${OUTPUT_DIR}/${archive_name}" \
        "${COMMON_EXCLUDES[@]}" \
        "${include_patterns[@]}"; then
        
        local size=$(du -h "${OUTPUT_DIR}/${archive_name}" | awk '{print $1}')
        log_info "  Created: ${archive_name} ($size)"
        
        # Generate SHA256
        (cd "$OUTPUT_DIR" && sha256sum "${archive_name}" > "${archive_name}.sha256")
        log_debug "  Checksum: ${archive_name}.sha256"
        
        return 0
    else
        log_error "  Failed to create ${archive_name}"
        return 1
    fi
}

# Create separate component archives
if [ "$CREATE_SEPARATE" = "true" ]; then
    log_info "Creating separate component archives..."
    
    # 1. Base archive (code, scripts, configs)
    create_archive "spel-base-${DATE}.tar.gz" "base archive" \
        --exclude='mirrors' \
        --exclude='offline-packages/*.zip' \
        --exclude='offline-packages/*.tar.gz' \
        --exclude='offline-packages/*.rpm' \
        --exclude='tools/packer/packer' \
        --exclude='tools/packer/plugins' \
        --exclude='tools/python-deps/*.whl' \
        --exclude='spel/ansible/roles/*/.git' \
        --exclude='vendor/*/.git' \
        .
    
    # 2. Mirrors archive (if mirrors exist and include is enabled)
    if [ "$INCLUDE_MIRRORS" = "true" ] && [ -d "mirrors" ]; then
        # Check if compressed mirrors exist
        if ls mirrors/*/*.tar.gz &>/dev/null; then
            log_info "Using compressed mirror archives..."
            create_archive "spel-mirrors-compressed-${DATE}.tar.gz" "compressed mirrors" \
                --exclude='mirrors/*/baseos' \
                --exclude='mirrors/*/appstream' \
                --exclude='mirrors/*/extras' \
                --exclude='mirrors/*/epel' \
                --exclude='mirrors/spel-packages/*.rpm' \
                mirrors
        else
            log_warn "No compressed mirrors found, creating from raw directories..."
            create_archive "spel-mirrors-${DATE}.tar.gz" "mirrors archive" \
                mirrors
        fi
    else
        log_warn "Skipping mirrors (not found or disabled)"
    fi
    
    # 3. Tools archive (if tools exist)
    if [ -d "tools" ] || [ -d "offline-packages" ]; then
        log_info "Creating tools and offline packages archive..."
        
        # Create temporary staging for tools
        TEMP_TOOLS=$(mktemp -d)
        trap "rm -rf $TEMP_TOOLS" EXIT
        
        # Copy tools if they exist
        if [ -d "tools" ]; then
            cp -r tools "$TEMP_TOOLS/"
        fi
        
        # Copy offline packages if they exist
        if [ -d "offline-packages" ]; then
            cp -r offline-packages "$TEMP_TOOLS/"
        fi
        
        # Copy compressed archives if they exist
        [ -f "ansible-roles.tar.gz" ] && cp ansible-roles.tar.gz "$TEMP_TOOLS/"
        [ -f "offline-packages.tar.gz" ] && cp offline-packages.tar.gz "$TEMP_TOOLS/"
        
        create_archive "spel-tools-${DATE}.tar.gz" "tools archive" \
            -C "$TEMP_TOOLS" .
    fi
fi

# Create combined archive
if [ "$CREATE_COMBINED" = "true" ]; then
    log_info "Creating combined archive..."
    
    COMBINED_EXCLUDES=("${COMMON_EXCLUDES[@]}")
    
    # Exclude uncompressed mirrors if compressed versions exist
    if ls mirrors/*/*.tar.gz &>/dev/null 2>&1; then
        COMBINED_EXCLUDES+=(
            --exclude='mirrors/*/baseos'
            --exclude='mirrors/*/appstream'
            --exclude='mirrors/*/extras'
            --exclude='mirrors/*/epel'
        )
        log_debug "  Using compressed mirrors in combined archive"
    fi
    
    # Exclude large binary files if not needed
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
log_info "  2. Transfer archives to NIPR using approved method"
log_info "  3. Verify checksums on NIPR side"
log_info "  4. Extract using scripts/extract-nipr-archives.sh"
