#!/bin/bash
#
# Setup local repository configuration for NIPR offline builds
# This script creates .repo files pointing to local mirrors
# Run this script in the NIPR environment after mirrors are in place
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR_BASE="$(cd "${SCRIPT_DIR}/../mirrors" && pwd)"
REPO_DIR="/etc/yum.repos.d"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

echo "Setting up local repository configuration..."
echo "Mirror base: $MIRROR_BASE"

# Detect OS version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_VERSION_MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)
else
    echo "Cannot detect OS version"
    exit 1
fi

# Backup existing repo files
BACKUP_DIR="/etc/yum.repos.d.backup.$(date +%Y%m%d-%H%M%S)"
if [ -d "$REPO_DIR" ] && [ "$(ls -A $REPO_DIR/*.repo 2>/dev/null)" ]; then
    echo "Backing up existing repo files to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -a ${REPO_DIR}/*.repo "$BACKUP_DIR/" || true
fi

# Disable all existing repos
echo "Disabling existing repositories..."
if command -v dnf &> /dev/null; then
    dnf config-manager --disable \* || true
elif command -v yum-config-manager &> /dev/null; then
    yum-config-manager --disable \* || true
fi

# Create local repo files based on OS version
if [ "$OS_VERSION_MAJOR" = "8" ]; then
    echo "Configuring EL8 local repositories..."
    
    cat > ${REPO_DIR}/local-baseos.repo <<EOF
[local-baseos]
name=Local BaseOS Repository
baseurl=file://${MIRROR_BASE}/el8/baseos
enabled=1
gpgcheck=0
EOF

    cat > ${REPO_DIR}/local-appstream.repo <<EOF
[local-appstream]
name=Local AppStream Repository
baseurl=file://${MIRROR_BASE}/el8/appstream
enabled=1
gpgcheck=0
EOF

    if [ -d "${MIRROR_BASE}/el8/extras" ]; then
        cat > ${REPO_DIR}/local-extras.repo <<EOF
[local-extras]
name=Local Extras Repository
baseurl=file://${MIRROR_BASE}/el8/extras
enabled=1
gpgcheck=0
EOF
    fi

    if [ -d "${MIRROR_BASE}/el8/epel" ]; then
        cat > ${REPO_DIR}/local-epel.repo <<EOF
[local-epel]
name=Local EPEL Repository
baseurl=file://${MIRROR_BASE}/el8/epel
enabled=1
gpgcheck=0
EOF
    fi

elif [ "$OS_VERSION_MAJOR" = "9" ]; then
    echo "Configuring EL9 local repositories..."
    
    cat > ${REPO_DIR}/local-baseos.repo <<EOF
[local-baseos]
name=Local BaseOS Repository
baseurl=file://${MIRROR_BASE}/el9/baseos
enabled=1
gpgcheck=0
EOF

    cat > ${REPO_DIR}/local-appstream.repo <<EOF
[local-appstream]
name=Local AppStream Repository
baseurl=file://${MIRROR_BASE}/el9/appstream
enabled=1
gpgcheck=0
EOF

    if [ -d "${MIRROR_BASE}/el9/extras" ]; then
        cat > ${REPO_DIR}/local-extras.repo <<EOF
[local-extras]
name=Local Extras Repository
baseurl=file://${MIRROR_BASE}/el9/extras
enabled=1
gpgcheck=0
EOF
    fi

    if [ -d "${MIRROR_BASE}/el9/epel" ]; then
        cat > ${REPO_DIR}/local-epel.repo <<EOF
[local-epel]
name=Local EPEL Repository
baseurl=file://${MIRROR_BASE}/el9/epel
enabled=1
gpgcheck=0
EOF
    fi
fi

# Setup SPEL packages repository
if [ -d "${MIRROR_BASE}/spel-packages" ]; then
    cat > ${REPO_DIR}/local-spel.repo <<EOF
[local-spel]
name=Local SPEL Packages Repository
baseurl=file://${MIRROR_BASE}/spel-packages
enabled=1
gpgcheck=0
EOF
fi

# Clean cache
echo "Cleaning repository cache..."
if command -v dnf &> /dev/null; then
    dnf clean all
elif command -v yum &> /dev/null; then
    yum clean all
fi

echo "Local repository configuration complete!"
echo "Verifying repository setup..."
if command -v dnf &> /dev/null; then
    dnf repolist
elif command -v yum &> /dev/null; then
    yum repolist
fi
