#!/bin/bash
#
# Download Packer binaries for offline Offline builds (multi-platform support)
# Run this on a system with internet access before transferring to Offline
#
# Supports downloading multiple platforms: linux_amd64, windows_amd64, etc.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/../tools/packer"

# Configuration
PACKER_VERSION="${SPEL_PACKER_VERSION:-1.11.2}"
PACKER_PLATFORMS="${SPEL_PACKER_PLATFORMS:-linux_amd64 windows_amd64}"

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
for cmd in wget unzip; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is required but not installed"
        exit 1
    fi
done

log_info "Packer download configuration:"
log_debug "  Version: $PACKER_VERSION"
log_debug "  Platforms: $PACKER_PLATFORMS"
log_debug "  Target directory: $TOOLS_DIR"

mkdir -p "$TOOLS_DIR"

# Download checksums once for all platforms
CHECKSUM_URL="https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_SHA256SUMS"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log_info "Downloading SHA256 checksums..."
if wget -O "${TEMP_DIR}/SHA256SUMS" "$CHECKSUM_URL"; then
    log_debug "  ✓ Downloaded checksums"
else
    log_warn "  ⚠ Could not download checksums, skipping verification"
    SKIP_CHECKSUM=true
fi

# Summary table header
log_info ""
log_info "Downloading Packer ${PACKER_VERSION} for multiple platforms..."
log_info ""
printf "%-20s %-15s %-50s %s\n" "Platform" "Status" "Binary Path" "Size"
printf "%-20s %-15s %-50s %s\n" "--------" "------" "-----------" "----"

# Download each platform
declare -a PLATFORM_INFO
for platform in $PACKER_PLATFORMS; do
    # Extract OS and architecture from platform (e.g., linux_amd64)
    PACKER_OS=$(echo "$platform" | cut -d'_' -f1)
    PACKER_ARCH=$(echo "$platform" | cut -d'_' -f2)
    
    PLATFORM_DIR="${TOOLS_DIR}/${platform}"
    mkdir -p "$PLATFORM_DIR"
    
    # Construct download URL and filenames
    PACKER_ZIP="packer_${PACKER_VERSION}_${PACKER_OS}_${PACKER_ARCH}.zip"
    PACKER_URL="https://releases.hashicorp.com/packer/${PACKER_VERSION}/${PACKER_ZIP}"
    
    # Determine binary name (packer or packer.exe)
    if [ "$PACKER_OS" = "windows" ]; then
        BINARY_NAME="packer.exe"
    else
        BINARY_NAME="packer"
    fi
    
    # Download platform binary
    if wget -q -O "${TEMP_DIR}/${PACKER_ZIP}" "$PACKER_URL"; then
        # Verify checksum if available
        if [ "${SKIP_CHECKSUM:-false}" = "false" ]; then
            cd "$TEMP_DIR"
            if grep "${PACKER_ZIP}" SHA256SUMS | sha256sum -c - > /dev/null 2>&1; then
                CHECKSUM_STATUS="✓"
            else
                CHECKSUM_STATUS="✗"
                log_error "Checksum verification failed for ${platform}"
                exit 1
            fi
            cd - > /dev/null
        else
            CHECKSUM_STATUS="-"
        fi
        
        # Extract binary
        if unzip -q -o "${TEMP_DIR}/${PACKER_ZIP}" -d "$PLATFORM_DIR"; then
            # Make executable (for non-Windows)
            if [ "$PACKER_OS" != "windows" ]; then
                chmod +x "${PLATFORM_DIR}/${BINARY_NAME}"
            fi
            
            BINARY_SIZE=$(du -h "${PLATFORM_DIR}/${BINARY_NAME}" | awk '{print $1}')
            STATUS="✓ ${CHECKSUM_STATUS}"
            
            # Store platform info for summary
            PLATFORM_INFO+=("${platform}|${STATUS}|${PLATFORM_DIR}/${BINARY_NAME}|${BINARY_SIZE}")
            
            printf "%-20s %-15s %-50s %s\n" "$platform" "$STATUS" "${PLATFORM_DIR}/${BINARY_NAME}" "$BINARY_SIZE"
        else
            printf "%-20s %-15s %-50s %s\n" "$platform" "✗ Extract" "Failed" "-"
            log_error "Failed to extract ${platform}"
            exit 1
        fi
    else
        printf "%-20s %-15s %-50s %s\n" "$platform" "✗ Download" "Failed" "-"
        log_error "Failed to download ${platform}"
        exit 1
    fi
    
    # Create platform-specific VERSION.txt
    VERSION_FILE="${PLATFORM_DIR}/VERSION.txt"
    cat > "$VERSION_FILE" <<EOF
# Packer Version Information
# Downloaded on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Platform: ${platform}
Version: $PACKER_VERSION
OS: $PACKER_OS
Architecture: $PACKER_ARCH
Download URL: $PACKER_URL
Binary: ${BINARY_NAME}
Size: ${BINARY_SIZE}
SHA256: $(sha256sum "${PLATFORM_DIR}/${BINARY_NAME}" | awk '{print $1}')

Installation Instructions
=========================

EOF
    
    if [ "$PACKER_OS" = "windows" ]; then
        cat >> "$VERSION_FILE" <<EOF
Windows:
  1. Copy packer.exe to a directory in your PATH
     Example: C:\\Windows\\System32\\packer.exe
     
  2. Or add current directory to PATH:
     set PATH=%PATH%;C:\\path\\to\\tools\\packer\\${platform}
     
  3. Verify installation:
     packer.exe version

Linux (for development/testing):
  wine ${PLATFORM_DIR}/${BINARY_NAME} version
EOF
    else
        cat >> "$VERSION_FILE" <<EOF
Linux:
  1. Install to system:
     sudo install -m 755 ${PLATFORM_DIR}/${BINARY_NAME} /usr/local/bin/packer
     
  2. Or use directly:
     ${PLATFORM_DIR}/${BINARY_NAME} version
     
  3. Verify installation:
     packer version
EOF
    fi
    
    # Cleanup downloaded zip
    rm -f "${TEMP_DIR}/${PACKER_ZIP}"
done

log_info ""
log_info "All platforms downloaded successfully!"
log_info ""
log_info "Summary:"
log_info "  Total platforms: $(echo $PACKER_PLATFORMS | wc -w)"
log_info "  Total size: $(du -sh "$TOOLS_DIR" | awk '{print $1}')"
log_info "  Location: ${TOOLS_DIR}"
log_info ""
log_info "Platform directories:"
for platform in $PACKER_PLATFORMS; do
    log_info "  ${platform}: ${TOOLS_DIR}/${platform}/"
done
log_info ""
log_info "Offline Usage:"
log_info "  Linux:   ${TOOLS_DIR}/linux_amd64/packer"
log_info "  Windows: ${TOOLS_DIR}/windows_amd64/packer.exe"
log_info ""
log_info "Packer download complete!"

