# Dockerfile for SPEL build environment
# Base: Rocky Linux 8 UBI Micro (minimal image)
#
# Build:
#   docker build -t spel-builder .
#
# Run with bind-mounted repository:
#   docker run --rm \
#     -v $(pwd):/workspace \
#     -e AWS_ACCESS_KEY_ID \
#     -e AWS_SECRET_ACCESS_KEY \
#     -e AWS_SESSION_TOKEN \
#     -e AWS_REGION=us-east-1 \
#     -e SPEL_BUILDERS=amazon-ebssurrogate.minimal-rhel-9-hvm \
#     -e SPEL_VERSION=2025.01.1 \
#     -e SPEL_IDENTIFIER=spel \
#     spel-builder make -f Makefile.spel build

FROM rockylinux/rockylinux:8-ubi-micro

# Build arguments
ARG PACKER_VERSION=1.11.2
ARG ANSIBLE_VERSION=">=2.14.0,<2.19.0"

# Environment variables
ENV PACKER_VERSION=${PACKER_VERSION} \
    ANSIBLE_VERSION=${ANSIBLE_VERSION} \
    # Packer plugin path (baked into image)
    PACKER_PLUGIN_PATH=/opt/packer/plugins \
    # Ansible paths (baked into image)
    ANSIBLE_COLLECTIONS_PATH=/opt/ansible/collections \
    ANSIBLE_ROLES_PATH=/opt/ansible/roles \
    # Offline packages path
    SPEL_OFFLINE_PACKAGES=/opt/offline-packages \
    # Workspace for bind mount
    WORKSPACE=/workspace

# Install microdnf and dnf for full package management
RUN microdnf install -y \
        dnf \
        dnf-plugins-core \
    && microdnf clean all

# Install system dependencies
RUN dnf install -y \
        # Version control
        git \
        # Build tools
        make \
        gcc \
        gcc-c++ \
        # Archive and compression
        tar \
        gzip \
        xz \
        bzip2 \
        unzip \
        # Download tools
        curl \
        wget \
        # Utilities
        findutils \
        which \
        jq \
        vim-minimal \
        # Development libraries
        openssl-devel \
        zlib-devel \
        bzip2-devel \
        readline-devel \
        sqlite-devel \
        libffi-devel \
        xz-devel \
        ncurses-devel \
        libxml2-devel \
        libxslt-devel \
        # Python 3.9 (RHEL 8/9 compatible)
        python39 \
        python39-pip \
        python39-devel \
        python39-setuptools \
        python39-wheel \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Set Python 3.9 as default
RUN alternatives --set python3 /usr/bin/python3.9 \
    && ln -sf /usr/bin/python3.9 /usr/bin/python \
    && python3.9 -m pip install --upgrade pip setuptools wheel

# =============================================================================
# Install Packer
# =============================================================================
RUN echo "=== Installing Packer ${PACKER_VERSION} ===" \
    && curl -fsSL -o /tmp/packer.zip \
        "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" \
    && curl -fsSL -o /tmp/packer_SHA256SUMS \
        "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_SHA256SUMS" \
    && cd /tmp && grep "linux_amd64" packer_SHA256SUMS | sha256sum -c - \
    && unzip -q /tmp/packer.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/packer \
    && rm -f /tmp/packer.zip /tmp/packer_SHA256SUMS \
    && packer version

# =============================================================================
# Install Packer plugins (during build, not run)
# =============================================================================
RUN mkdir -p ${PACKER_PLUGIN_PATH} \
    && cat > /tmp/plugins.pkr.hcl << 'EOF'
packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.3"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
    azure = {
      version = "~> 1"
      source  = "github.com/hashicorp/azure"
    }
    openstack = {
      version = "~> 1"
      source  = "github.com/hashicorp/openstack"
    }
    vagrant = {
      version = "~> 1"
      source  = "github.com/hashicorp/vagrant"
    }
    virtualbox = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/virtualbox"
    }
    windows-update = {
      version = ">= 0.17.1"
      source  = "github.com/rgl/windows-update"
    }
  }
}
EOF
    && echo "=== Installing Packer plugins ===" \
    && packer init /tmp/plugins.pkr.hcl \
    && rm -f /tmp/plugins.pkr.hcl \
    && echo "Installed plugins:" \
    && find ${PACKER_PLUGIN_PATH} -type f -name "packer-plugin-*" 2>/dev/null | head -20 \
    && du -sh ${PACKER_PLUGIN_PATH}

# =============================================================================
# Install Ansible and Python dependencies
# =============================================================================
RUN echo "=== Installing Ansible and dependencies ===" \
    && python3.9 -m pip install --no-cache-dir \
        "ansible-core${ANSIBLE_VERSION}" \
        pywinrm \
        requests \
        requests-ntlm \
        passlib \
        lxml \
        xmltodict \
        jmespath \
    && ansible --version

# =============================================================================
# Install Ansible collections
# =============================================================================
RUN mkdir -p ${ANSIBLE_COLLECTIONS_PATH} \
    && echo "=== Installing Ansible collections ===" \
    && ansible-galaxy collection install -p ${ANSIBLE_COLLECTIONS_PATH} \
        ansible.windows:1.14.0 \
        community.windows:1.13.0 \
        community.general:7.5.0 \
        ansible.posix:1.5.4 \
        community.crypto:2.16.0 \
    && echo "Installed collections:" \
    && ls -la ${ANSIBLE_COLLECTIONS_PATH}/ansible_collections/ \
    && du -sh ${ANSIBLE_COLLECTIONS_PATH}

# =============================================================================
# Install Ansible roles (STIG/CIS hardening roles)
# =============================================================================
RUN mkdir -p ${ANSIBLE_ROLES_PATH} \
    && echo "=== Vendoring Ansible roles ===" \
    && cd ${ANSIBLE_ROLES_PATH} \
    # RHEL 8 STIG
    && git clone --depth 1 https://github.com/ansible-lockdown/RHEL8-STIG.git \
    && rm -rf RHEL8-STIG/.git \
    # RHEL 9 STIG
    && git clone --depth 1 https://github.com/ansible-lockdown/RHEL9-STIG.git \
    && rm -rf RHEL9-STIG/.git \
    # Amazon Linux 2023 CIS
    && git clone --depth 1 https://github.com/ansible-lockdown/AMAZON2023-CIS.git \
    && rm -rf AMAZON2023-CIS/.git \
    # Windows Server STIG roles
    && git clone --depth 1 https://github.com/ansible-lockdown/Windows-2016-STIG.git \
    && rm -rf Windows-2016-STIG/.git \
    && git clone --depth 1 https://github.com/ansible-lockdown/Windows-2019-STIG.git \
    && rm -rf Windows-2019-STIG/.git \
    && git clone --depth 1 https://github.com/ansible-lockdown/Windows-2022-STIG.git \
    && rm -rf Windows-2022-STIG/.git \
    && echo "Vendored roles:" \
    && ls -la ${ANSIBLE_ROLES_PATH} \
    && du -sh ${ANSIBLE_ROLES_PATH}

# =============================================================================
# Download offline packages
# =============================================================================
RUN mkdir -p ${SPEL_OFFLINE_PACKAGES} \
    && echo "=== Downloading offline packages ===" \
    && cd ${SPEL_OFFLINE_PACKAGES} \
    # AWS CLI v2
    && curl -fsSL -o awscli-exe-linux-x86_64.zip \
        "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    && echo "Downloaded AWS CLI v2" \
    # CloudFormation Bootstrap
    && curl -fsSL -o aws-cfn-bootstrap-py3-latest.tar.gz \
        "https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz" \
    && echo "Downloaded CFN Bootstrap" \
    # SSM Agent (EL8/EL9 compatible)
    && curl -fsSL -o amazon-ssm-agent.rpm \
        "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm" \
    && echo "Downloaded SSM Agent" \
    && echo "Offline packages:" \
    && ls -lh ${SPEL_OFFLINE_PACKAGES} \
    && du -sh ${SPEL_OFFLINE_PACKAGES}

# =============================================================================
# Create workspace directory
# =============================================================================
WORKDIR ${WORKSPACE}

# Create entrypoint script
RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "=== SPEL Build Container ==="
echo "Packer: $(packer version | head -1)"
echo "Ansible: $(ansible --version | head -1)"
echo "Python: $(python3 --version)"
echo ""

# Show environment configuration
echo "Environment:"
echo "  SPEL_IDENTIFIER: ${SPEL_IDENTIFIER:-not set}"
echo "  SPEL_VERSION: ${SPEL_VERSION:-not set}"
echo "  SPEL_BUILDERS: ${SPEL_BUILDERS:-not set}"
echo "  WINDOWS_BUILDERS: ${WINDOWS_BUILDERS:-not set}"
echo "  AWS_REGION: ${AWS_REGION:-not set}"
echo "  PKR_VAR_aws_region: ${PKR_VAR_aws_region:-not set}"
echo ""

# Show baked-in paths
echo "Baked-in Dependencies:"
echo "  Packer plugins: ${PACKER_PLUGIN_PATH}"
echo "  Ansible collections: ${ANSIBLE_COLLECTIONS_PATH}"
echo "  Ansible roles: ${ANSIBLE_ROLES_PATH}"
echo "  Offline packages: ${SPEL_OFFLINE_PACKAGES}"
echo ""

# Check if workspace is mounted
if [ ! -f "${WORKSPACE}/Makefile.spel" ]; then
    echo "ERROR: Makefile.spel not found in ${WORKSPACE}"
    echo ""
    echo "Mount your repository to ${WORKSPACE}:"
    echo "  docker run -v \$(pwd):/workspace spel-builder make -f Makefile.spel build"
    exit 1
fi

# Check AWS credentials
if [ -z "${AWS_ACCESS_KEY_ID}" ] && [ -z "${AWS_SESSION_TOKEN}" ] && [ ! -d "/root/.aws" ]; then
    echo "WARNING: AWS credentials not detected"
    echo "  Pass credentials via environment variables:"
    echo "    -e AWS_ACCESS_KEY_ID"
    echo "    -e AWS_SECRET_ACCESS_KEY"
    echo "    -e AWS_SESSION_TOKEN (optional)"
    echo "  Or mount AWS config:"
    echo "    -v ~/.aws:/root/.aws:ro"
    echo ""
fi

# Execute command
exec "$@"
EOF
    && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["make", "-f", "Makefile.spel", "build"]

# Labels
LABEL org.opencontainers.image.title="SPEL Builder" \
      org.opencontainers.image.description="Build environment for SPEL AMIs with offline dependencies" \
      org.opencontainers.image.source="https://github.com/MetroStar/spel"
