# Dockerfile for SPEL build environment
# Base: Rocky Linux 9 Iron Bank (hardened, minimal image)
# Uses multi-stage build to keep final image small (~305 MB compressed)
#
# Build:
#   docker build -t spel-builder:$(date +%Y%m%d) .
#
# Run with bind-mounted repository:
#   docker run --rm \
#     -v $(pwd):/workspace \
#     -e AWS_ACCESS_KEY_ID \
#     -e AWS_SECRET_ACCESS_KEY \
#     -e AWS_SESSION_TOKEN \
#     -e AWS_DEFAULT_REGION=us-east-1 \
#     -e SPEL_BUILDERS=amazon-ebssurrogate.minimal-rhel-9-hvm \
#     -e SPEL_VERSION=2025.01.1 \
#     -e SPEL_IDENTIFIER=spel \
#     -e WINDOWS_BUILDERS="" \
#     spel-builder:$(date +%Y%m%d) make -f Makefile.spel build

# =============================================================================
# Stage 1: Builder - Install all dependencies
# =============================================================================
FROM registry1.dso.mil/ironbank/opensource/rockylinux/rockylinux9:9.7 AS builder

# Build arguments
ARG PACKER_VERSION=1.11.2
ARG ANSIBLE_VERSION=">=2.14.0,<2.19.0"

# Environment variables for build
ENV PACKER_VERSION=${PACKER_VERSION} \
    ANSIBLE_VERSION=${ANSIBLE_VERSION} \
    PACKER_PLUGIN_PATH=/opt/packer/plugins \
    ANSIBLE_COLLECTIONS_PATH=/opt/ansible/collections \
    ANSIBLE_ROLES_PATH=/opt/ansible/roles \
    SPEL_OFFLINE_PACKAGES=/opt/offline-packages \
    AMIGEN8_PATH=/opt/amigen8 \
    AMIGEN9_PATH=/opt/amigen9

# Install build dependencies
# Note: --allowerasing needed because Iron Bank image has curl-minimal which conflicts with curl
RUN dnf install -y --allowerasing \
        git \
        make \
        tar \
        gzip \
        unzip \
        curl \
        wget \
        findutils \
        which \
        jq \
        python3 \
        python3-pip \
        openssh-clients \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Set Python 3 as default (EL9 has python3.9 as system python)
RUN ln -sf /usr/bin/python3 /usr/bin/python \
    && python3 -m pip install --upgrade pip setuptools wheel

# =============================================================================
# Install Packer
# =============================================================================
RUN echo "=== Installing Packer ${PACKER_VERSION} ===" \
    && cd /tmp \
    && curl -fsSLO "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" \
    && curl -fsSLO "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_SHA256SUMS" \
    && grep "linux_amd64.zip" "packer_${PACKER_VERSION}_SHA256SUMS" | sha256sum -c - \
    && unzip -q "packer_${PACKER_VERSION}_linux_amd64.zip" -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/packer \
    && rm -f packer_${PACKER_VERSION}_* \
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
  }
}
EOF

RUN echo "=== Installing Packer plugins ===" \
    && packer init /tmp/plugins.pkr.hcl \
    && rm -f /tmp/plugins.pkr.hcl \
    && echo "Installed plugins:" \
    && find ${PACKER_PLUGIN_PATH} -type f -name "packer-plugin-*" 2>/dev/null | head -20 \
    && du -sh ${PACKER_PLUGIN_PATH}

# =============================================================================
# Install Ansible and Python dependencies
# =============================================================================
RUN echo "=== Installing Ansible and dependencies ===" \
    && python3 -m pip install --no-cache-dir \
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
    # AWS STIG Script for Amazon Linux 2023 hardening
    # Base64 encoded for reliable transfer to EC2 instances
    && curl -fsSL -o LinuxAWSConfigureSTIG.tgz \
        "https://aws-windows-downloads-us-east-1.s3.amazonaws.com/STIG/Linux/Latest/LinuxAWSConfigureSTIG.tgz" \
    && gzip -t LinuxAWSConfigureSTIG.tgz \
    && echo "Downloaded AWS STIG Script ($(stat -c%s LinuxAWSConfigureSTIG.tgz) bytes)" \
    && base64 LinuxAWSConfigureSTIG.tgz > LinuxAWSConfigureSTIG.tgz.b64 \
    && echo "Base64 encoded AWS STIG Script ($(stat -c%s LinuxAWSConfigureSTIG.tgz.b64) bytes)" \
    && rm LinuxAWSConfigureSTIG.tgz \
    && echo "Offline packages:" \
    && ls -lh ${SPEL_OFFLINE_PACKAGES} \
    && du -sh ${SPEL_OFFLINE_PACKAGES}

# =============================================================================
# Download Python wheels for EC2 offline Ansible installation
# These wheels are uploaded to the EC2 instance and installed there
# (for STIG playbooks that run locally on the EC2 instance)
# =============================================================================
ENV PYTHON_DEPS_PATH=/opt/python-deps
RUN mkdir -p ${PYTHON_DEPS_PATH} \
    && echo "=== Downloading Python wheels for EC2 offline installation ===" \
    && python3 -m pip download \
        --dest ${PYTHON_DEPS_PATH} \
        --platform manylinux2014_x86_64 \
        --python-version 3.9 \
        --only-binary=:all: \
        ansible-core \
        pywinrm \
        requests \
        passlib \
        jmespath \
    && echo "Downloaded Python wheels:" \
    && ls -lh ${PYTHON_DEPS_PATH} \
    && du -sh ${PYTHON_DEPS_PATH}

# =============================================================================
# Download Python installer and wheels for Windows EC2 offline installation
# The Python installer + pip wheels are uploaded to the Windows EC2 instance
# and installed there (for STIG playbooks that run locally via SSM)
# =============================================================================
ENV PYTHON_WIN_DEPS_PATH=/opt/python-deps-win
RUN mkdir -p ${PYTHON_WIN_DEPS_PATH} \
    && echo "=== Downloading Python installer and wheels for Windows EC2 ===" \
    && curl -fsSL -o ${PYTHON_WIN_DEPS_PATH}/python-3.11.9-amd64.exe \
        "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" \
    && python3 -m pip download \
        --dest ${PYTHON_WIN_DEPS_PATH} \
        --platform win_amd64 \
        --python-version 3.11 \
        --only-binary=:all: \
        ansible-core \
        pywinrm \
        sspilib \
    && echo "Downloaded Windows Python deps:" \
    && ls -lh ${PYTHON_WIN_DEPS_PATH} \
    && du -sh ${PYTHON_WIN_DEPS_PATH}

# =============================================================================# Download Ansible collection tarballs for EC2 offline installation
# These are uploaded to EC2 and installed with ansible-galaxy
# =============================================================================
ENV ANSIBLE_COLLECTIONS_TARBALLS=/opt/ansible-collections-tarballs
RUN mkdir -p ${ANSIBLE_COLLECTIONS_TARBALLS} \
    && echo "=== Downloading Ansible collection tarballs for EC2 ===" \
    && ansible-galaxy collection download -p ${ANSIBLE_COLLECTIONS_TARBALLS} \
        ansible.posix:1.5.4 \
        community.general:7.5.0 \
        community.crypto:2.16.0 \
    && echo "Downloaded collection tarballs:" \
    && ls -lh ${ANSIBLE_COLLECTIONS_TARBALLS} \
    && du -sh ${ANSIBLE_COLLECTIONS_TARBALLS}

# =============================================================================
# Copy AMIgen scripts from vendor directory (for offline EC2 builds)
# These are uploaded to EC2 so it doesn't need to git clone from GitHub
# =============================================================================
COPY vendor/amigen8 ${AMIGEN8_PATH}
COPY vendor/amigen9 ${AMIGEN9_PATH}
RUN echo "=== Baked-in AMIgen scripts ===" \
    && echo "AMIgen8:" && ls -la ${AMIGEN8_PATH}/*.sh 2>/dev/null | head -5 \
    && echo "AMIgen9:" && ls -la ${AMIGEN9_PATH}/*.sh 2>/dev/null | head -5 \
    && du -sh ${AMIGEN8_PATH} ${AMIGEN9_PATH}

# =============================================================================
# Install AWS CLI v2 (for container use)
# =============================================================================
RUN echo "=== Installing AWS CLI v2 ===" \
    && cd /tmp \
    && unzip -q ${SPEL_OFFLINE_PACKAGES}/awscli-exe-linux-x86_64.zip \
    && ./aws/install --install-dir /opt/aws-cli --bin-dir /usr/local/bin \
    && rm -rf /tmp/aws \
    && aws --version

# Create entrypoint script in builder
RUN cat > /opt/entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "=== SPEL Build Container ==="
echo "Packer: $(packer version | head -1)"
echo "Ansible: $(ansible --version | head -1)"
echo "Python: $(python3 --version)"
echo ""

# =============================================================================
# Detect CI Environment and set workspace path accordingly
# =============================================================================
CI_ENVIRONMENT="local"
if [ "${GITHUB_ACTIONS}" = "true" ]; then
    CI_ENVIRONMENT="GitHub Actions"
    # GitHub Actions mounts to /github/workspace by default
    if [ -d "/github/workspace" ] && [ -f "/github/workspace/Makefile.spel" ]; then
        WORKSPACE="/github/workspace"
    fi
elif [ "${GITLAB_CI}" = "true" ]; then
    CI_ENVIRONMENT="GitLab CI"
    # GitLab CI uses CI_PROJECT_DIR
    if [ -n "${CI_PROJECT_DIR}" ] && [ -f "${CI_PROJECT_DIR}/Makefile.spel" ]; then
        WORKSPACE="${CI_PROJECT_DIR}"
    fi
elif [ -n "${JENKINS_URL}" ]; then
    CI_ENVIRONMENT="Jenkins"
fi

echo "CI Environment: ${CI_ENVIRONMENT}"
echo "Workspace: ${WORKSPACE}"
echo ""

# =============================================================================
# Set AWS region for Packer
# Makefile.spel expects PKR_VAR_aws_region or AWS_REGION (not AWS_DEFAULT_REGION)
# =============================================================================
if [ -z "${PKR_VAR_aws_region}" ]; then
    if [ -n "${AWS_REGION}" ]; then
        export PKR_VAR_aws_region="${AWS_REGION}"
    elif [ -n "${AWS_DEFAULT_REGION}" ]; then
        export PKR_VAR_aws_region="${AWS_DEFAULT_REGION}"
        export AWS_REGION="${AWS_DEFAULT_REGION}"
    fi
fi

# Show environment configuration
echo "Environment:"
echo "  SPEL_IDENTIFIER: ${SPEL_IDENTIFIER:-not set}"
echo "  SPEL_VERSION: ${SPEL_VERSION:-not set}"
echo "  SPEL_BUILDERS: ${SPEL_BUILDERS:-not set}"
echo "  WINDOWS_BUILDERS: ${WINDOWS_BUILDERS:-not set}"
echo "  AWS_REGION: ${AWS_REGION:-not set}"
echo "  AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION:-not set}"
echo "  PKR_VAR_aws_region: ${PKR_VAR_aws_region:-not set}"
echo ""

# Show baked-in paths
echo "Baked-in Dependencies:"
echo "  Packer plugins: ${PACKER_PLUGIN_PATH}"
echo "  Ansible collections: ${ANSIBLE_COLLECTIONS_PATH}"
echo "  Ansible roles: ${ANSIBLE_ROLES_PATH}"
echo "  Offline packages: ${SPEL_OFFLINE_PACKAGES}"
echo "  Python wheels (for EC2): ${PYTHON_DEPS_PATH}"
echo "  Collection tarballs (for EC2): ${ANSIBLE_COLLECTIONS_TARBALLS}"
echo "  AMIgen8 scripts: ${AMIGEN8_PATH}"
echo "  AMIgen9 scripts: ${AMIGEN9_PATH}"
echo ""

# =============================================================================
# Check if this is a simple command (version check, help, etc.)
# Skip workspace validation for these commands
# =============================================================================
FIRST_ARG="${1:-}"
SKIP_WORKSPACE_CHECK=false

# Detect version/help commands that don't need workspace
case "${FIRST_ARG}" in
    packer|ansible|ansible-playbook|python|python3|aws|pip|pip3)
        # Check if second arg is version/help related
        case "${2:-}" in
            version|--version|-v|-V|--help|-h|help)
                SKIP_WORKSPACE_CHECK=true
                ;;
        esac
        ;;
    --version|--help|-h|-v)
        SKIP_WORKSPACE_CHECK=true
        ;;
esac

# Check if workspace is mounted (skip for version/help commands)
if [ "${SKIP_WORKSPACE_CHECK}" = "false" ]; then
    if [ ! -f "${WORKSPACE}/Makefile.spel" ]; then
        echo "ERROR: Makefile.spel not found in ${WORKSPACE}"
        echo ""
        echo "Mount your repository to ${WORKSPACE}:"
        echo "  docker run -v \$(pwd):/workspace spel-builder make -f Makefile.spel build"
        exit 1
    fi

    # =============================================================================
    # Symlink baked-in Ansible roles to workspace location
    # Packer templates expect roles at spel/ansible/roles/<ROLE_NAME>
    # =============================================================================
    ROLES_DEST="${WORKSPACE}/spel/ansible/roles"
    if [ -d "${ANSIBLE_ROLES_PATH}" ] && [ -d "${ROLES_DEST}" ]; then
        echo "Symlinking baked-in Ansible roles to workspace..."
        for role in "${ANSIBLE_ROLES_PATH}"/*; do
            if [ -d "$role" ]; then
                role_name=$(basename "$role")
                target="${ROLES_DEST}/${role_name}"
                if [ ! -e "$target" ]; then
                    ln -sf "$role" "$target"
                    echo "  Linked: ${role_name}"
                fi
            fi
        done
        echo ""
    fi

    # =============================================================================
    # Symlink/copy baked-in Python wheels to workspace location
    # Packer file provisioner uploads tools/python-deps/ to EC2
    # =============================================================================
    PYTHON_DEPS_DEST="${WORKSPACE}/tools/python-deps"
    if [ -d "${PYTHON_DEPS_PATH}" ]; then
        echo "Populating Python wheels in workspace..."
        mkdir -p "${PYTHON_DEPS_DEST}"
        # Copy wheels (symlinks don't work well with Packer file provisioner)
        for whl in "${PYTHON_DEPS_PATH}"/*.whl; do
            if [ -f "$whl" ]; then
                whl_name=$(basename "$whl")
                target="${PYTHON_DEPS_DEST}/${whl_name}"
                if [ ! -e "$target" ]; then
                    cp "$whl" "$target"
                fi
            fi
        done
        echo "  Wheels available: $(ls ${PYTHON_DEPS_DEST}/*.whl 2>/dev/null | wc -l)"
        echo ""
    fi

    # =============================================================================
    # Copy baked-in Windows Python deps to workspace location
    # Packer file provisioner uploads tools/python-deps-win/ to Windows EC2
    # =============================================================================
    PYTHON_WIN_DEPS_DEST="${WORKSPACE}/tools/python-deps-win"
    if [ -d "${PYTHON_WIN_DEPS_PATH}" ]; then
        echo "Populating Windows Python deps in workspace..."
        mkdir -p "${PYTHON_WIN_DEPS_DEST}"
        for f in "${PYTHON_WIN_DEPS_PATH}"/*; do
            if [ -f "$f" ]; then
                fname=$(basename "$f")
                target="${PYTHON_WIN_DEPS_DEST}/${fname}"
                if [ ! -e "$target" ]; then
                    cp "$f" "$target"
                fi
            fi
        done
        echo "  Windows deps available: $(ls ${PYTHON_WIN_DEPS_DEST}/ 2>/dev/null | wc -l) files"
        echo ""
    fi

    # =============================================================================
    # Symlink/copy baked-in Ansible collection tarballs to workspace location
    # Packer file provisioner uploads spel/ansible/collections/ to EC2
    # =============================================================================
    COLLECTIONS_DEST="${WORKSPACE}/spel/ansible/collections"
    if [ -d "${ANSIBLE_COLLECTIONS_TARBALLS}" ]; then
        echo "Populating Ansible collection tarballs in workspace..."
        mkdir -p "${COLLECTIONS_DEST}"
        for tarball in "${ANSIBLE_COLLECTIONS_TARBALLS}"/*.tar.gz; do
            if [ -f "$tarball" ]; then
                tarball_name=$(basename "$tarball")
                target="${COLLECTIONS_DEST}/${tarball_name}"
                if [ ! -e "$target" ]; then
                    cp "$tarball" "$target"
                fi
            fi
        done
        echo "  Collections available: $(ls ${COLLECTIONS_DEST}/*.tar.gz 2>/dev/null | wc -l)"
        echo ""
    fi

    # =============================================================================
    # Copy baked-in AMIgen scripts to offline-packages for EC2 upload
    # Packer file provisioner uploads offline-packages/ to EC2
    # =============================================================================
    AMIGEN_DEST="${WORKSPACE}/offline-packages"
    if [ -d "${AMIGEN8_PATH}" ] || [ -d "${AMIGEN9_PATH}" ]; then
        echo "Populating AMIgen scripts in offline-packages..."
        mkdir -p "${AMIGEN_DEST}"
        if [ -d "${AMIGEN8_PATH}" ] && [ ! -d "${AMIGEN_DEST}/amigen8" ]; then
            cp -r "${AMIGEN8_PATH}" "${AMIGEN_DEST}/amigen8"
            echo "  Copied: amigen8"
        fi
        if [ -d "${AMIGEN9_PATH}" ] && [ ! -d "${AMIGEN_DEST}/amigen9" ]; then
            cp -r "${AMIGEN9_PATH}" "${AMIGEN_DEST}/amigen9"
            echo "  Copied: amigen9"
        fi
        echo ""
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
fi

# Execute command
exec "$@"
EOF

RUN chmod +x /opt/entrypoint.sh

# =============================================================================
# Stage 2: Final image - Rocky Linux 9 Iron Bank (minimal)
# =============================================================================
FROM registry1.dso.mil/ironbank/opensource/rockylinux/rockylinux9-minimal:9.7-minimal

# Environment variables
ENV PACKER_PLUGIN_PATH=/opt/packer/plugins \
    ANSIBLE_COLLECTIONS_PATH=/opt/ansible/collections \
    ANSIBLE_ROLES_PATH=/opt/ansible/roles \
    SPEL_OFFLINE_PACKAGES=/opt/offline-packages \
    PYTHON_DEPS_PATH=/opt/python-deps \
    PYTHON_WIN_DEPS_PATH=/opt/python-deps-win \
    ANSIBLE_COLLECTIONS_TARBALLS=/opt/ansible-collections-tarballs \
    AMIGEN8_PATH=/opt/amigen8 \
    AMIGEN9_PATH=/opt/amigen9 \
    WORKSPACE=/workspace \
    PATH="/usr/local/bin:/opt/python/bin:${PATH}" \
    PYTHONPATH="/opt/python/lib/python3.9/site-packages"

# Copy Packer binary
COPY --from=builder /usr/local/bin/packer /usr/local/bin/packer

# Copy AWS CLI v2 (entire install directory with bundled Python)
COPY --from=builder /opt/aws-cli /opt/aws-cli

# Copy Packer plugins
COPY --from=builder /opt/packer/plugins /opt/packer/plugins

# Copy Python 3.9 installation and site-packages
COPY --from=builder /usr/bin/python3 /usr/bin/python3
COPY --from=builder /usr/lib64/python3.9 /usr/lib64/python3.9
COPY --from=builder /usr/lib/python3.9 /usr/lib/python3.9
COPY --from=builder /usr/local/lib/python3.9 /usr/local/lib/python3.9
COPY --from=builder /usr/local/lib64/python3.9 /usr/local/lib64/python3.9
COPY --from=builder /usr/local/bin/ansible* /usr/local/bin/

# Copy required shared libraries for Python
COPY --from=builder /usr/lib64/libpython3.9.so* /usr/lib64/
COPY --from=builder /usr/lib64/libexpat.so* /usr/lib64/
COPY --from=builder /usr/lib64/libffi.so* /usr/lib64/
COPY --from=builder /usr/lib64/libsqlite3.so* /usr/lib64/
COPY --from=builder /usr/lib64/libcrypt.so* /usr/lib64/
COPY --from=builder /usr/lib64/libssl.so* /usr/lib64/
COPY --from=builder /usr/lib64/libcrypto.so* /usr/lib64/
COPY --from=builder /usr/lib64/libbz2.so* /usr/lib64/
COPY --from=builder /usr/lib64/liblzma.so* /usr/lib64/
COPY --from=builder /usr/lib64/libreadline.so* /usr/lib64/
COPY --from=builder /usr/lib64/libncurses*.so* /usr/lib64/
COPY --from=builder /usr/lib64/libtinfo.so* /usr/lib64/
COPY --from=builder /usr/lib64/libz.so* /usr/lib64/
# Libraries for curl
COPY --from=builder /usr/lib64/libcurl.so* /usr/lib64/
COPY --from=builder /usr/lib64/libnghttp2.so* /usr/lib64/
COPY --from=builder /usr/lib64/libidn2.so* /usr/lib64/
COPY --from=builder /usr/lib64/libssh.so* /usr/lib64/
COPY --from=builder /usr/lib64/libpsl.so* /usr/lib64/
COPY --from=builder /usr/lib64/libgssapi_krb5.so* /usr/lib64/
COPY --from=builder /usr/lib64/libkrb5.so* /usr/lib64/
COPY --from=builder /usr/lib64/libk5crypto.so* /usr/lib64/
COPY --from=builder /usr/lib64/libcom_err.so* /usr/lib64/
COPY --from=builder /usr/lib64/libkrb5support.so* /usr/lib64/
COPY --from=builder /usr/lib64/libldap*.so* /usr/lib64/
COPY --from=builder /usr/lib64/liblber*.so* /usr/lib64/
COPY --from=builder /usr/lib64/libbrotli*.so* /usr/lib64/
COPY --from=builder /usr/lib64/libunistring.so* /usr/lib64/
COPY --from=builder /usr/lib64/libsasl2.so* /usr/lib64/
COPY --from=builder /usr/lib64/libselinux.so* /usr/lib64/
COPY --from=builder /usr/lib64/libpcre*.so* /usr/lib64/
COPY --from=builder /usr/lib64/libkeyutils.so* /usr/lib64/
COPY --from=builder /usr/lib64/libresolv.so* /usr/lib64/
# Libraries for jq
COPY --from=builder /usr/lib64/libjq.so* /usr/lib64/
COPY --from=builder /usr/lib64/libonig.so* /usr/lib64/
# Libraries for gawk
COPY --from=builder /usr/lib64/libsigsegv.so* /usr/lib64/
COPY --from=builder /usr/lib64/libmpfr.so* /usr/lib64/
COPY --from=builder /usr/lib64/libgmp.so* /usr/lib64/

# Copy Ansible collections and roles
COPY --from=builder /opt/ansible/collections /opt/ansible/collections
COPY --from=builder /opt/ansible/roles /opt/ansible/roles

# Copy offline packages
COPY --from=builder /opt/offline-packages /opt/offline-packages

# Copy Python wheels for EC2 offline installation (Linux)
COPY --from=builder /opt/python-deps /opt/python-deps

# Copy Python installer and wheels for Windows EC2 offline installation
COPY --from=builder /opt/python-deps-win /opt/python-deps-win

# Copy Ansible collection tarballs for EC2 offline installation
COPY --from=builder /opt/ansible-collections-tarballs /opt/ansible-collections-tarballs

# Copy AMIgen scripts for EC2 offline builds
COPY --from=builder /opt/amigen8 /opt/amigen8
COPY --from=builder /opt/amigen9 /opt/amigen9

# Copy entrypoint script
COPY --from=builder /opt/entrypoint.sh /entrypoint.sh

# Copy essential binaries from builder
COPY --from=builder /usr/bin/make /usr/bin/make
COPY --from=builder /usr/bin/git /usr/bin/git
COPY --from=builder /usr/bin/curl /usr/bin/curl
COPY --from=builder /usr/bin/jq /usr/bin/jq
COPY --from=builder /usr/bin/unzip /usr/bin/unzip
COPY --from=builder /usr/bin/find /usr/bin/find
COPY --from=builder /usr/bin/xargs /usr/bin/xargs
COPY --from=builder /usr/bin/which /usr/bin/which
COPY --from=builder /usr/bin/tar /usr/bin/tar
COPY --from=builder /usr/bin/gzip /usr/bin/gzip
COPY --from=builder /usr/bin/gunzip /usr/bin/gunzip
COPY --from=builder /usr/bin/grep /usr/bin/grep
COPY --from=builder /usr/bin/awk /usr/bin/awk
COPY --from=builder /usr/bin/sed /usr/bin/sed

# Copy SSH client (required for Ansible to connect to EC2 instances)
COPY --from=builder /usr/bin/ssh /usr/bin/ssh
COPY --from=builder /usr/bin/ssh-keygen /usr/bin/ssh-keygen
COPY --from=builder /usr/bin/ssh-keyscan /usr/bin/ssh-keyscan
COPY --from=builder /usr/bin/scp /usr/bin/scp
COPY --from=builder /usr/bin/sftp /usr/bin/sftp
COPY --from=builder /etc/ssh/ssh_config /etc/ssh/ssh_config
COPY --from=builder /etc/crypto-policies /etc/crypto-policies

# Copy CA certificates for SSL/TLS
COPY --from=builder /etc/pki/tls/certs /etc/pki/tls/certs
COPY --from=builder /etc/pki/ca-trust /etc/pki/ca-trust
COPY --from=builder /etc/ssl/certs /etc/ssl/certs

# Create symlinks
RUN ln -sf /usr/bin/python3 /usr/bin/python \
    && ln -sf /opt/aws-cli/v2/current/bin/aws /usr/local/bin/aws \
    && ln -sf /opt/aws-cli/v2/current/bin/aws_completer /usr/local/bin/aws_completer

# Create workspace directory
WORKDIR ${WORKSPACE}

ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["make", "-f", "Makefile.spel", "build"]

# Labels
LABEL org.opencontainers.image.title="SPEL Builder" \
      org.opencontainers.image.description="Build environment for SPEL AMIs with offline dependencies" \
      org.opencontainers.image.source="https://github.com/MetroStar/spel"
