#!/bin/bash
# Package Ansible STIG playbooks for delivery via SSM from S3
# Usage: ./package-ansible-stig.sh [OPTIONS]
#
# Creates a tarball containing Ansible roles and a wrapper playbook suitable
# for delivery via AWS-ApplyAnsiblePlaybooks SSM document. The package can
# be uploaded to S3 and referenced in SSM State Manager associations for
# scheduled compliance checks (ansible-playbook --check mode).
#
# Options:
#   --output DIR     Output directory (default: ./dist)
#   --s3-bucket NAME Upload to S3 bucket after packaging
#   --s3-prefix KEY  S3 key prefix (default: ansible-stig)
#   --os-target OS   Target OS: rhel8, rhel9, al2023, all (default: all)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="./dist"
S3_BUCKET=""
S3_PREFIX="ansible-stig"
OS_TARGET="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)    OUTPUT_DIR="$2"; shift 2 ;;
    --s3-bucket) S3_BUCKET="$2"; shift 2 ;;
    --s3-prefix) S3_PREFIX="$2"; shift 2 ;;
    --os-target) OS_TARGET="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--output DIR] [--s3-bucket NAME] [--s3-prefix KEY] [--os-target OS]"
      echo "  --output DIR      Output directory (default: ./dist)"
      echo "  --s3-bucket NAME  Upload to S3 after packaging"
      echo "  --s3-prefix KEY   S3 key prefix (default: ansible-stig)"
      echo "  --os-target OS    rhel8, rhel9, al2023, all (default: all)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

ROLES_DIR="$REPO_ROOT/spel/ansible/roles"
COLLECTIONS_DIR="$REPO_ROOT/spel/ansible/collections"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$OUTPUT_DIR"

echo "=== Packaging Ansible STIG Playbooks ==="
echo "Repository root: $REPO_ROOT"
echo "Target OS: $OS_TARGET"
echo "Output: $OUTPUT_DIR"
echo ""

# Create temporary staging directory
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

# Determine which roles to include
declare -a ROLES_TO_INCLUDE=()
case "$OS_TARGET" in
  rhel8)
    ROLES_TO_INCLUDE=("RHEL8-STIG")
    ;;
  rhel9)
    ROLES_TO_INCLUDE=("RHEL9-STIG")
    ;;
  al2023)
    ROLES_TO_INCLUDE=("RHEL9-STIG")  # AL2023 uses RHEL9 STIG role
    ;;
  all)
    ROLES_TO_INCLUDE=("RHEL8-STIG" "RHEL9-STIG")
    ;;
  *)
    echo "ERROR: Unknown OS target: $OS_TARGET"
    exit 1
    ;;
esac

# Stage roles
echo "Staging roles..."
mkdir -p "$STAGING/roles"
for role in "${ROLES_TO_INCLUDE[@]}"; do
  if [[ -d "$ROLES_DIR/$role" ]]; then
    cp -a "$ROLES_DIR/$role" "$STAGING/roles/"
    echo "  [OK] $role"
  else
    echo "  [ERROR] Role not found: $ROLES_DIR/$role"
    exit 1
  fi
done

# Also include AL2023-STIG alias if it exists (it references RHEL9-STIG)
if [[ -d "$ROLES_DIR/AL2023-STIG" ]] && [[ "$OS_TARGET" == "all" || "$OS_TARGET" == "al2023" ]]; then
  cp -a "$ROLES_DIR/AL2023-STIG" "$STAGING/roles/"
  echo "  [OK] AL2023-STIG"
fi

# Stage boot-fips-wrapper.sh for EL8 FIPS boot repair
BOOT_FIPS_WRAPPER="$REPO_ROOT/spel/scripts/boot-fips-wrapper.sh"
if [[ -f "$BOOT_FIPS_WRAPPER" ]]; then
  cp "$BOOT_FIPS_WRAPPER" "$STAGING/boot-fips-wrapper.sh"
  chmod +x "$STAGING/boot-fips-wrapper.sh"
  echo "  [OK] boot-fips-wrapper.sh"
else
  echo "  [WARN] boot-fips-wrapper.sh not found at $BOOT_FIPS_WRAPPER — EL8 FIPS boot repair will not be available"
fi

# Stage collections if present
if [[ -d "$COLLECTIONS_DIR" ]]; then
  echo "Staging collections..."
  mkdir -p "$STAGING/collections"
  find "$COLLECTIONS_DIR" -name '*.tar.gz' -exec cp {} "$STAGING/collections/" \;
  echo "  [OK] $(find "$STAGING/collections" -name '*.tar.gz' | wc -l) collection tarballs"
fi

# Create the SSM-compatible wrapper playbook
# AWS-ApplyAnsiblePlaybooks expects a playbook at a known path
echo "Creating SSM wrapper playbook..."

cat > "$STAGING/site.yml" <<'PLAYBOOK_EOF'
---
# SSM-compatible STIG playbook with EL8 FIPS boot repair
# ======================================================
# This playbook is designed to be run via AWS-ApplyAnsiblePlaybooks.
# It supports both enforcement (Check=False) and compliance checking
# (Check=True / --check mode).
#
# The playbook auto-detects the OS and applies the correct STIG role.
#
# EL8 FIPS Boot Repair:
#   The upstream RHEL8-STIG role templates /etc/default/grub wholesale,
#   stripping the boot=UUID parameter needed for FIPS boot integrity.
#   pre_tasks runs boot-fips-wrapper.sh pre (installs dracut-fips, sets
#   boot=UUID) BEFORE the role, and post_tasks runs boot-fips-wrapper.sh
#   post (validates boot=UUID, checks kernel HMACs, rebuilds initramfs)
#   AFTER the role to repair the damage.
#
#   In --check mode, ansible.builtin.script is naturally skipped (the
#   script module does not support check_mode), so boot-fips-wrapper.sh
#   will NOT run during compliance-check-only scans.

- name: STIG Hardening
  hosts: localhost
  connection: local
  become: true

  pre_tasks:
    - name: Gather OS facts
      ansible.builtin.setup:
        gather_subset:
          - distribution

    - name: Set role name based on OS
      ansible.builtin.set_fact:
        stig_role: >-
          {%- if ansible_distribution == 'Amazon' and ansible_distribution_major_version == '2023' -%}
            AL2023-STIG
          {%- elif ansible_distribution == 'RedHat' and ansible_distribution_major_version == '9' -%}
            RHEL9-STIG
          {%- elif ansible_distribution == 'RedHat' and ansible_distribution_major_version == '8' -%}
            RHEL8-STIG
          {%- elif ansible_distribution == 'OracleLinux' and ansible_distribution_major_version == '9' -%}
            RHEL9-STIG
          {%- elif ansible_distribution == 'OracleLinux' and ansible_distribution_major_version == '8' -%}
            RHEL8-STIG
          {%- elif ansible_distribution == 'CentOS' and ansible_distribution_major_version == '8' -%}
            RHEL8-STIG
          {%- else -%}
            UNSUPPORTED
          {%- endif -%}

    - name: Fail on unsupported OS
      ansible.builtin.fail:
        msg: "Unsupported OS: {{ ansible_distribution }} {{ ansible_distribution_version }}"
      when: stig_role == 'UNSUPPORTED'

    # -----------------------------------------------------------------
    # EL8 FIPS boot repair — PRE step
    # Installs dracut-fips, rebuilds initramfs, inserts boot=UUID.
    # Skipped automatically in --check mode (script module limitation).
    # -----------------------------------------------------------------
    - name: "EL8 FIPS boot-repair pre (install dracut-fips, set boot=UUID)"
      ansible.builtin.script: boot-fips-wrapper.sh pre
      args:
        chdir: "{{ playbook_dir }}"
      when:
        - stig_role == 'RHEL8-STIG'
        - ansible_distribution_major_version == '8'

  roles:
    - role: "{{ stig_role }}"

  post_tasks:
    # -----------------------------------------------------------------
    # EL8 FIPS boot repair — POST step
    # Validates boot=UUID matches actual kernel device, checks HMAC
    # files, rebuilds initramfs. Repairs any GRUB damage from the
    # RHEL8-STIG role's etc_default_grub.j2 template.
    # Skipped automatically in --check mode.
    # -----------------------------------------------------------------
    - name: "EL8 FIPS boot-repair post (validate boot=UUID, rebuild initramfs)"
      ansible.builtin.script: boot-fips-wrapper.sh post
      args:
        chdir: "{{ playbook_dir }}"
      when:
        - stig_role == 'RHEL8-STIG'
        - ansible_distribution_major_version == '8'

  vars:
    system_is_ec2: true
    # SSM-specific exemptions
    rhel9stig_white_list_services:
      - ssh
      - https
    rhel9stig_sudoers_exclude_nopasswd_list:
      - ec2-user
      - maintuser
      - vagrant
      - ssm-user
    rhel9stig_faillock_exclude_users:
      - ec2-user
      - ssm-user
    rhel8stig_sudoers_exclude_nopasswd_list:
      - ec2-user
      - maintuser
      - vagrant
      - ssm-user
    rhel8stig_faillock_exclude_users:
      - ec2-user
      - ssm-user
    # Disable FIPS crypto-policy controls (managed separately)
    rhel_09_251010: false
    rhel_09_251015: false
    rhel_09_251020: false
    rhel_09_251025: false
    rhel_09_251030: false
    rhel_09_251035: false
    rhel_09_251040: false
    rhel_09_251045: false
    # Disable EL8 incompatible controls
    rhel8stig_copy_existing_zone: false
    rhel_08_040136: false
PLAYBOOK_EOF

echo "  [OK] site.yml"

# Create requirements file for collections
if [[ -d "$STAGING/collections" ]]; then
  cat > "$STAGING/requirements.yml" <<'REQ_EOF'
---
collections: []
# Collections are pre-packaged as tarballs in the collections/ directory
# Install with: for f in collections/*.tar.gz; do ansible-galaxy collection install "$f" --force; done
REQ_EOF
  echo "  [OK] requirements.yml"
fi

# Create the zip archive (AWS-ApplyAnsiblePlaybooks only supports .zip)
ARCHIVE_NAME="ansible-stig-${OS_TARGET}-${TIMESTAMP}.zip"
echo ""
echo "Creating archive: $ARCHIVE_NAME"
(cd "$STAGING" && zip -qr "$OUTPUT_DIR/$ARCHIVE_NAME" .)
echo "  [OK] $(du -h "$OUTPUT_DIR/$ARCHIVE_NAME" | cut -f1)"

# Also create a 'latest' symlink
LATEST_NAME="ansible-stig-${OS_TARGET}-latest.zip"
ln -sf "$ARCHIVE_NAME" "$OUTPUT_DIR/$LATEST_NAME"
echo "  [OK] $LATEST_NAME -> $ARCHIVE_NAME"

# Upload to S3 if requested
if [[ -n "$S3_BUCKET" ]]; then
  echo ""
  echo "Uploading to s3://$S3_BUCKET/$S3_PREFIX/..."
  aws s3 cp "$OUTPUT_DIR/$ARCHIVE_NAME" "s3://$S3_BUCKET/$S3_PREFIX/$ARCHIVE_NAME"
  aws s3 cp "$OUTPUT_DIR/$ARCHIVE_NAME" "s3://$S3_BUCKET/$S3_PREFIX/$LATEST_NAME"
  echo "  [OK] Uploaded to S3"
  echo ""
  echo "SSM association source URL:"
  echo "  s3://$S3_BUCKET/$S3_PREFIX/$LATEST_NAME"
fi

echo ""
echo "=== Packaging Complete ==="
echo "Archive: $OUTPUT_DIR/$ARCHIVE_NAME"
echo ""
echo "To use with SSM State Manager (AWS-ApplyAnsiblePlaybooks):"
echo "  PlaybookFile: site.yml"
echo "  SourceType:   S3"
echo "  Check:        True  (compliance check, no changes)"
