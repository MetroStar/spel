#!/bin/bash
#
# Vendor Ansible roles from GitHub with storage optimization
# This script clones only the latest version without git history
# Run this on a system with internet access before transferring to NIPR
#
# STORAGE OPTIMIZATION:
# - Uses --depth 1 for shallow clone (no git history)
# - Optionally removes .git directories to save ~50% space
# - Supports specific tag/branch checkout
# - Creates compressed archive for transfer
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLES_DIR="${SCRIPT_DIR}/../spel/ansible/roles"

# Configuration
REMOVE_GIT="${SPEL_ROLES_REMOVE_GIT:-true}"
COMPRESS="${SPEL_ROLES_COMPRESS:-true}"
SPECIFIC_TAG="${SPEL_ROLES_TAG:-}"  # Set to specific tag/version if needed

# Handle "latest" keyword - empty string means latest default branch
if [ "$SPECIFIC_TAG" = "latest" ]; then
    SPECIFIC_TAG=""
fi

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

# Check for git
if ! command -v git &> /dev/null; then
    log_error "git is required but not installed"
    exit 1
fi

log_info "Ansible roles vendoring configuration:"
log_debug "  Roles directory: $ROLES_DIR"
log_debug "  Remove .git directories: $REMOVE_GIT"
log_debug "  Create compressed archive: $COMPRESS"
log_debug "  Specific tag: ${SPECIFIC_TAG:-latest}"

log_debug "Creating roles directory: $ROLES_DIR"
mkdir -p "$ROLES_DIR" || {
    log_error "Failed to create roles directory: $ROLES_DIR"
    exit 1
}
log_debug "✓ Roles directory created successfully"

# Check bash version (associative arrays require bash 4.0+)
log_debug "Bash version: ${BASH_VERSION}"
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    log_error "This script requires bash 4.0 or higher (found ${BASH_VERSION})"
    exit 1
fi

# Define roles to vendor
log_debug "Defining roles to vendor..."
declare -A ROLES
ROLES["RHEL8-STIG"]="https://github.com/ansible-lockdown/RHEL8-STIG.git"
ROLES["RHEL9-STIG"]="https://github.com/ansible-lockdown/RHEL9-STIG.git"
ROLES["AMAZON2023-CIS"]="https://github.com/ansible-lockdown/AMAZON2023-CIS.git"
ROLES["Windows-2016-STIG"]="https://github.com/ansible-lockdown/Windows-2016-STIG.git"
ROLES["Windows-2019-STIG"]="https://github.com/ansible-lockdown/Windows-2019-STIG.git"
ROLES["Windows-2022-STIG"]="https://github.com/ansible-lockdown/Windows-2022-STIG.git"
log_debug "✓ Defined ${#ROLES[@]} roles"

TOTAL_ROLES=${#ROLES[@]}
CURRENT=0

for role_name in "${!ROLES[@]}"; do
    ((CURRENT++))
    role_url="${ROLES[$role_name]}"
    role_path="${ROLES_DIR}/${role_name}"
    
    log_info "[$CURRENT/$TOTAL_ROLES] Vendoring $role_name..."
    
    # Remove existing role if present
    if [ -d "$role_path" ]; then
        log_warn "  Removing existing role at $role_path"
        rm -rf "$role_path"
    fi
    
    # Clone with shallow depth
    log_debug "  Cloning from $role_url"
    
    if [ -n "$SPECIFIC_TAG" ]; then
        # Clone specific tag/branch
        log_debug "  Using specific tag/branch: $SPECIFIC_TAG"
        if ! git clone --depth 1 --branch "$SPECIFIC_TAG" --single-branch \
            "$role_url" "$role_path" 2>&1; then
            log_warn "  Failed to clone tag $SPECIFIC_TAG, trying latest..."
            if ! git clone --depth 1 "$role_url" "$role_path" 2>&1; then
                log_error "  Failed to clone $role_name from $role_url"
                continue
            fi
        fi
    else
        # Clone latest
        log_debug "  Cloning latest default branch"
        if ! git clone --depth 1 "$role_url" "$role_path" 2>&1; then
            log_error "  Failed to clone $role_name from $role_url"
            continue
        fi
    fi
    
    # Get size before optimization
    SIZE_BEFORE=$(du -sh "$role_path" | awk '{print $1}')
    
    # Remove .git directory if configured
    if [ "$REMOVE_GIT" = "true" ]; then
        log_debug "  Removing .git directory to save space"
        rm -rf "${role_path}/.git"
        SIZE_AFTER=$(du -sh "$role_path" | awk '{print $1}')
        log_info "  Size: $SIZE_BEFORE -> $SIZE_AFTER"
    else
        log_info "  Size: $SIZE_BEFORE (with git history)"
    fi
done

# Calculate total size
TOTAL_SIZE=$(du -sh "$ROLES_DIR" | awk '{print $1}')
log_info "Total vendored roles size: $TOTAL_SIZE"

# Create compressed archive
if [ "$COMPRESS" = "true" ]; then
    ARCHIVE_PATH="${SCRIPT_DIR}/../ansible-roles.tar.gz"
    log_info "Creating compressed archive..."
    
    tar czf "$ARCHIVE_PATH" \
        -C "$(dirname "$ROLES_DIR")" \
        "$(basename "$ROLES_DIR")"
    
    ARCHIVE_SIZE=$(du -sh "$ARCHIVE_PATH" | awk '{print $1}')
    log_info "Created: ansible-roles.tar.gz ($ARCHIVE_SIZE)"
    log_info "Archive location: $ARCHIVE_PATH"
fi

log_info "Ansible roles vendoring complete!"
log_info ""
log_info "Vendored roles:"
for role_name in "${!ROLES[@]}"; do
    if [ -d "${ROLES_DIR}/${role_name}" ]; then
        role_size=$(du -sh "${ROLES_DIR}/${role_name}" | awk '{print $1}')
        echo "  ✓ $role_name ($role_size)"
    else
        echo "  ✗ $role_name (failed)"
    fi
done
