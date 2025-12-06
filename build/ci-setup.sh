#!/bin/bash
#
# CI Setup Script for SPEL Builds
# Supports both online (GitHub Actions) and offline (Offline) modes
# Detects environment and installs Packer, Python, and Ansible dependencies
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

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

# Detect offline mode
detect_offline_mode() {
    if [ "${SPEL_OFFLINE_MODE:-}" = "true" ]; then
        log_info "SPEL_OFFLINE_MODE=true - using offline mode"
        return 0
    fi
    
    # Auto-detect based on presence of vendored tools
    if [ -f "${REPO_ROOT}/tools/packer/packer" ] || \
       [ -d "${REPO_ROOT}/tools/python-deps" ] || \
       [ -d "${REPO_ROOT}/mirrors/el9/baseos" ]; then
        log_info "Detected vendored tools - using offline mode"
        export SPEL_OFFLINE_MODE=true
        return 0
    fi
    
    log_info "No vendored tools detected - using online mode"
    export SPEL_OFFLINE_MODE=false
    return 1
}

# Install Packer
install_packer() {
    if command -v packer &> /dev/null; then
        log_info "Packer already installed: $(packer version)"
        return 0
    fi
    
    if detect_offline_mode; then
        # Offline mode - use vendored binary
        log_info "Installing Packer from vendored binary..."
        if [ -f "${REPO_ROOT}/tools/packer/packer" ]; then
            sudo install -m 755 "${REPO_ROOT}/tools/packer/packer" /usr/local/bin/packer
            log_info "Packer installed: $(packer version)"
        else
            log_error "Vendored Packer binary not found at ${REPO_ROOT}/tools/packer/packer"
            exit 1
        fi
    else
        # Online mode - download from HashiCorp
        log_info "Installing Packer from HashiCorp repository..."
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
        sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
        sudo apt-get update && sudo apt-get install -y packer
        log_info "Packer installed: $(packer version)"
    fi
}

# Install Python dependencies
install_python_deps() {
    # Find Python executable
    PLAYBOOK=$(command -v ansible-playbook 2>/dev/null || true)
    if [ -n "$PLAYBOOK" ]; then
        SHEBANG=$(head -1 "$PLAYBOOK")
        PY_EXEC=$(echo "$SHEBANG" | awk 'NR==1{if($0 ~ /^#!/){sub("^#!","",$0); print $0}}')
        if echo "$PY_EXEC" | grep -q "env "; then 
            PY_EXEC=$(command -v python3)
        fi
    else
        PY_EXEC=$(command -v python3 2>/dev/null || echo "/usr/bin/python3")
    fi
    
    log_info "Using Python: $PY_EXEC"
    
    if detect_offline_mode; then
        # Offline mode - install from vendored wheels matching Python version
        log_info "Installing Python packages from vendored wheels..."
        
        # Detect Python version (e.g., "3.9", "3.12")
        PY_VERSION=$("$PY_EXEC" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        log_info "Detected Python version: $PY_VERSION"
        
        if [ -d "${REPO_ROOT}/tools/python-deps" ]; then
            # Check if we have wheels compatible with this Python version
            # Wheels can be: cp39 (Python 3.9 specific), cp312 (Python 3.12 specific), 
            # py3 (any Python 3), or abi3 (stable ABI, forward compatible)
            PY_MAJOR_MINOR=$(echo "$PY_VERSION" | tr -d '.')  # e.g., "39" or "312"
            
            # Count compatible wheels (cp39, cp312, py3, abi3, none-any)
            COMPAT_WHEELS=$(find "${REPO_ROOT}/tools/python-deps" -name "*.whl" \
                \( -name "*cp${PY_MAJOR_MINOR}*" -o -name "*py3*" -o -name "*abi3*" -o -name "*none-any*" \) \
                2>/dev/null | wc -l)
            
            if [ "$COMPAT_WHEELS" -gt 0 ]; then
                log_info "Found $COMPAT_WHEELS compatible wheels for Python $PY_VERSION"
                sudo "$PY_EXEC" -m pip install --no-index \
                    --find-links="${REPO_ROOT}/tools/python-deps/" \
                    "ansible-core<2.19" \
                    pywinrm requests requests-ntlm \
                    passlib lxml xmltodict jmespath \
                    distro pytest pytest-logger pytest-testinfra
                log_info "Python packages installed from vendored wheels"
            else
                log_error "No compatible wheels found for Python $PY_VERSION in ${REPO_ROOT}/tools/python-deps/"
                log_error "Available wheels:"
                ls -1 "${REPO_ROOT}/tools/python-deps/"*.whl 2>/dev/null | head -5 || echo "  (none found)"
                exit 1
            fi
        else
            log_error "Vendored Python wheels not found at ${REPO_ROOT}/tools/python-deps/"
            exit 1
        fi
    else
        # Online mode - download from PyPI
        log_info "Installing Python packages from PyPI..."
        sudo "$PY_EXEC" -m pip install --upgrade pip
        sudo "$PY_EXEC" -m pip install --upgrade --force-reinstall "ansible-core<2.19"
        sudo "$PY_EXEC" -m pip install --upgrade \
            pywinrm requests requests-ntlm \
            passlib lxml xmltodict jmespath
        log_info "Python packages installed from PyPI"
    fi
    
    # Verify ansible installation
    if command -v ansible &> /dev/null; then
        log_info "Ansible version: $(ansible --version | head -1)"
    else
        log_warn "Ansible not found in PATH after installation"
    fi
}

# Install Ansible collections
install_ansible_collections() {
    if detect_offline_mode; then
        # Offline mode - install from vendored tarballs
        log_info "Installing Ansible collections from vendored tarballs..."
        if [ -d "${REPO_ROOT}/spel/ansible/collections" ] && ls "${REPO_ROOT}"/spel/ansible/collections/*.tar.gz 1> /dev/null 2>&1; then
            for tarball in "${REPO_ROOT}"/spel/ansible/collections/*.tar.gz; do
                log_info "Installing $(basename "$tarball")..."
                # Filter out dependency version warnings - we only need the collections we're explicitly installing
                ansible-galaxy collection install "$tarball" --force 2>&1 | grep -vE "(does not support Ansible version|^[0-9]+\.[0-9]+\.[0-9]+$|^Warning: : Collection)" || true
            done
            log_info "Ansible collections installed from vendored tarballs"
        else
            log_warn "Vendored Ansible collection tarballs not found - builds may fail for Windows"
            log_warn "Expected location: ${REPO_ROOT}/spel/ansible/collections/*.tar.gz"
        fi
    else
        # Online mode - download specific versions from Galaxy
        log_info "Installing Ansible collections from Galaxy..."
        ansible-galaxy collection install ansible.windows:1.14.0 --force 2>&1 | grep -vE "(does not support Ansible version|^[0-9]+\.[0-9]+\.[0-9]+$|^Warning: : Collection)" || true
        ansible-galaxy collection install community.windows:1.13.0 --force 2>&1 | grep -vE "(does not support Ansible version|^[0-9]+\.[0-9]+\.[0-9]+$|^Warning: : Collection)" || true
        ansible-galaxy collection install community.general:7.5.0 --force 2>&1 | grep -vE "(does not support Ansible version|^[0-9]+\.[0-9]+\.[0-9]+$|^Warning: : Collection)" || true
        log_info "Ansible collections installed from Galaxy"
    fi
}

# Setup Packer plugins
setup_packer_plugins() {
    if detect_offline_mode; then
        # Offline mode - use vendored plugins
        log_info "Setting up Packer plugins from vendored path..."
        if [ -d "${REPO_ROOT}/tools/packer/plugins" ]; then
            export PACKER_PLUGIN_PATH="${REPO_ROOT}/tools/packer/plugins"
            log_info "PACKER_PLUGIN_PATH set to ${PACKER_PLUGIN_PATH}"
        else
            log_warn "Vendored Packer plugins not found at ${REPO_ROOT}/tools/packer/plugins"
        fi
    else
        # Online mode - let Packer download plugins
        log_info "Packer will download plugins as needed"
    fi
}

# Install necessary system packages
install_system_packages() {
    if detect_offline_mode; then
        log_info "Skipping system package installation in offline mode"
        log_warn "Ensure all required packages are pre-installed"
    else
        log_info "Installing necessary system packages..."
        sudo apt-get update -y && sudo apt-get install -y \
            xz-utils curl jq unzip make vim \
            build-essential libssl-dev zlib1g-dev libbz2-dev \
            libreadline-dev libsqlite3-dev llvm libncursesw5-dev \
            tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
        log_info "System packages installed"
    fi
}

# Main execution
main() {
    log_info "Starting SPEL CI environment setup..."
    log_info "Repository root: $REPO_ROOT"
    
    detect_offline_mode
    
    # Ensure offline-packages directory exists (required by Packer file provisioner)
    # In online mode: creates empty directory (uploaded to EC2, no impact)
    # In offline mode: directory should already be populated by extract-offline-archives.sh
    if [ ! -d "${REPO_ROOT}/offline-packages" ]; then
        log_info "Creating offline-packages directory (required by Packer)"
        mkdir -p "${REPO_ROOT}/offline-packages"
    else
        log_info "Offline-packages directory exists"
        du -sh "${REPO_ROOT}/offline-packages" || true
    fi
    
    install_system_packages
    install_packer
    install_python_deps
    install_ansible_collections
    setup_packer_plugins
    
    log_info "CI environment setup complete!"
    
    # Export environment variables for subsequent steps
    echo "SPEL_OFFLINE_MODE=${SPEL_OFFLINE_MODE}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    
    if [ "${SPEL_OFFLINE_MODE}" = "true" ] && [ -d "${REPO_ROOT}/tools/packer/plugins" ]; then
        echo "PACKER_PLUGIN_PATH=${REPO_ROOT}/tools/packer/plugins" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    fi
}

main "$@"
