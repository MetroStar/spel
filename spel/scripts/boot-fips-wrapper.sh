#!/usr/bin/env bash
# /tmp/boot-fips-wrapper.sh
# Strict, verbose wrapper to handle boot=UUID and dracut-fips related tasks.
# Usage: boot-fips-wrapper.sh pre|post
set -euo pipefail
shopt -s extglob

LOG() { printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
ERR() { LOG "ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage: $0 pre|post

pre  - attempt to install dracut-fips (idempotent), rebuild initramfs (with fips hooks if present),
       and insert boot=UUID into kernel args and /etc/default/grub ONLY if /boot is a separate device.
post - verify/repair any blank/malformed boot=UUID entries (or remove them if /boot is not separate),
       rebuild initramfs, and regenerate grub config.

This script is strict: it will exit non-zero if it detects missing kernel files when they are required.
EOF
  exit 2
}

if [[ ${#} -ne 1 ]]; then usage; fi
MODE="$1"
if [[ "$MODE" != "pre" && "$MODE" != "post" ]]; then usage; fi

# Helpers
backup_file() {
  local f="$1"; local ts
  ts=$(date +%s)
  if [[ -f "$f" ]]; then
    cp -a -- "$f" "${f}.bak.${ts}"
    LOG "Backed up $f -> ${f}.bak.${ts}"
  fi
}

is_efi() { [[ -d /sys/firmware/efi ]]; }

# Resolve /boot and /
BOOT_SRC="$(findmnt -n -o SOURCE --target /boot 2>/dev/null || true)"
ROOT_SRC="$(findmnt -n -o SOURCE --target / 2>/dev/null || true)"

LOG "Resolving /boot device and root device..."
LOG "/boot source : ${BOOT_SRC:-<none>}"
LOG "/ root source : ${ROOT_SRC:-<none>}"

# Only treat /boot as separate if BOOT_SRC != ROOT_SRC and both non-empty
BOOT_IS_SEPARATE="false"
if [[ -n "$BOOT_SRC" && -n "$ROOT_SRC" && "$BOOT_SRC" != "$ROOT_SRC" ]]; then
  BOOT_IS_SEPARATE="true"
fi

# Obtain actual boot UUID if separate
BOOT_UUID=""
if [[ "$BOOT_IS_SEPARATE" == "true" ]]; then
  BOOT_UUID="$(blkid -s UUID -o value "$BOOT_SRC" 2>/dev/null || true)"
  BOOT_UUID="${BOOT_UUID:-}"
  LOG "/boot is separate; UUID=${BOOT_UUID:-<none>}"
else
  LOG "/boot is NOT a separate device; the script will NOT insert boot=UUID"
fi

# kernel version we operate against
KVER="$(uname -r)"
LOG "Working kernel version: ${KVER}"

# Strict check: ensure kernel file exists where expected when needed
kernel_file_exists_on_boot() {
  local kver="$1"
  [[ -f "/boot/vmlinuz-${kver}" ]]
}

initramfs_exists_on_boot() {
  local kver="$1"
  [[ -f "/boot/initramfs-${kver}.img" ]]
}

# Rebuild initramfs (strict). Will error out if kernel file expected is missing.
rebuild_initramfs_for_kver() {
  local kver="$1"
  if [[ -z "$kver" ]]; then
    ERR "Empty kernel version passed to rebuild_initramfs_for_kver"
    return 1
  fi

  # If /boot is separate, ensure the kernel file exists on that /boot device before rebuilding;
  # dracut FIPS checks can require on-disk kernel presence.
  if [[ "$BOOT_IS_SEPARATE" == "true" ]]; then
    if ! kernel_file_exists_on_boot "$kver"; then
      ERR "Missing kernel file /boot/vmlinuz-${kver} on separate /boot. Aborting to avoid broken FIPS initramfs."
      exit 3
    fi
  else
    # If /boot is not separate, kernel file should still exist; but be a little lenient:
    if ! kernel_file_exists_on_boot "$kver"; then
      ERR "Kernel file /boot/vmlinuz-${kver} not found (root-managed /boot). Aborting."
      exit 4
    fi
  fi

  # backup initramfs if present
  if [[ -f "/boot/initramfs-${kver}.img" ]]; then
    backup_file "/boot/initramfs-${kver}.img"
  fi

  # decide whether to include fips add
  if rpm -q --quiet dracut-fips; then
    LOG "dracut-fips installed; rebuilding initramfs with --add fips for kernel ${kver}"
    dracut -f -v --add fips --kver "$kver"
  else
    LOG "dracut-fips NOT installed; rebuilding initramfs (no fips hooks) for kernel ${kver}"
    dracut -f -v --kver "$kver"
  fi
  LOG "Initramfs rebuilt for ${kver}"
}

regenerate_grub_cfg() {
  if is_efi; then
    mkdir -p /boot/efi/EFI/oracle
    LOG "Regenerating grub config at /boot/efi/EFI/oracle/grub.cfg"
    grub2-mkconfig -o /boot/efi/EFI/oracle/grub.cfg
  else
    LOG "Regenerating grub config at /boot/grub2/grub.cfg"
    grub2-mkconfig -o /boot/grub2/grub.cfg
  fi
}

# Insert boot=UUID into kernel args and /etc/default/grub (strict)
insert_boot_uuid() {
  local uuid="$1"
  if [[ -z "$uuid" ]]; then
    ERR "insert_boot_uuid called with empty UUID; aborting."
    exit 5
  fi

  LOG "Preparing to insert boot=UUID=${uuid} into kernel args (/etc/default/grub and grubby entries)."

  # Before editing, verify that the device actually contains the kernel file we need (strict)
  local dev_by_uuid
  dev_by_uuid="$(blkid -U "$uuid" 2>/dev/null || true)"
  if [[ -z "$dev_by_uuid" ]]; then
    ERR "UUID ${uuid} does not map to a device according to blkid; aborting insertion."
    exit 6
  fi

  # mountpoint check (best effort): check that /boot is actually backed by that UUID device
  if [[ "$BOOT_IS_SEPARATE" == "true" ]]; then
    if ! kernel_file_exists_on_boot "$KVER"; then
      ERR "Kernel file /boot/vmlinuz-${KVER} missing on device $dev_by_uuid; aborting insertion to prevent FIPS boot failures."
      exit 7
    fi
  fi

  # Update grubby kernel entries: remove any boot tokens (defensive), then add correct one
  LOG "Updating kernel args via grubby for all kernels"
  grubby --info=ALL | awk -F: '/kernel/ {print $2}' | sed 's/^[ \t]*//' | while read -r kernpath; do
    # defensive removals
    grubby --update-kernel="$kernpath" --remove-args="boot" || true
    grubby --update-kernel="$kernpath" --remove-args="boot=UUID=" || true
    # add desired token
    grubby --update-kernel="$kernpath" --args="boot=UUID=${uuid}" || true
  done

  # Now edit /etc/default/grub
  backup_file /etc/default/grub
  if grep -qP '^\s*GRUB_CMDLINE_LINUX=' /etc/default/grub; then
    # delete previous boot tokens, then append
    sed -ri 's/\bboot=UUID=[^" ]+ ?//g; s/\bboot=[^" ]+ ?//g' /etc/default/grub
    # append token just before closing quote (strict update)
    sed -ri -e '/^\s*GRUB_CMDLINE_LINUX="/ {
      s@"$@ boot=UUID='"${uuid}"'"@
    }' /etc/default/grub
  else
    printf 'GRUB_CMDLINE_LINUX="boot=UUID=%s"\n' "$uuid" >> /etc/default/grub
  fi

  LOG "Inserted boot=UUID=${uuid} into /etc/default/grub and kernel entries; regenerating grub.cfg"
  regenerate_grub_cfg
}

# Remove any boot= tokens (strict)
remove_boot_tokens() {
  LOG "Removing any boot= tokens from kernel args and /etc/default/grub"

  # Remove from kernels
  grubby --info=ALL | awk -F: '/kernel/ {print $2}' | sed 's/^[ \t]*//' | while read -r kernpath; do
    grubby --update-kernel="$kernpath" --remove-args="boot" || true
    grubby --update-kernel="$kernpath" --remove-args="boot=UUID=" || true
  done

  # Remove from /etc/default/grub (backup first)
  backup_file /etc/default/grub
  sed -ri 's/\bboot=UUID=[^" ]+ ?//g; s/\bboot=[^" ]+ ?//g' /etc/default/grub || true

  LOG "Removed boot= tokens and regenerating grub.cfg"
  regenerate_grub_cfg
}

# Main behavior
case "$MODE" in
  pre)
    LOG "=== PRE mode ==="
    # install dracut-fips idempotently if possible
    if ! rpm -q --quiet dracut-fips; then
      LOG "dracut-fips not installed; attempting install (if repo provides it)"
      if command -v dnf >/dev/null 2>&1; then
        if ! dnf -y install dracut-fips; then
          LOG "Warning: dracut-fips install failed or not available; continuing but initramfs won't include fips hooks."
        fi
      else
        if ! yum -y install dracut-fips; then
          LOG "Warning: dracut-fips install failed or not available; continuing but initramfs won't include fips hooks."
        fi
      fi
    else
      LOG "dracut-fips already installed"
    fi

    # Rebuild initramfs now (strict)
    LOG "Rebuilding initramfs for kernel ${KVER} (strict checks enabled)"
    rebuild_initramfs_for_kver "$KVER"

    # Insert boot=UUID only if /boot is separate and we have a UUID
    if [[ "$BOOT_IS_SEPARATE" == "true" && -n "$BOOT_UUID" ]]; then
      LOG "/boot is separate and UUID available; inserting boot=UUID"
      insert_boot_uuid "$BOOT_UUID"
    else
      LOG "Not inserting boot=UUID: /boot is not separate or UUID missing"
    fi

    LOG "=== PRE complete ==="
    ;;

  post)
    LOG "=== POST mode ==="

    # If /boot is not separate, ensure boot tokens are removed (they're harmful in that config)
    if [[ "$BOOT_IS_SEPARATE" != "true" ]]; then
      LOG "/boot is NOT separate -> ensure no boot= tokens remain"
      remove_boot_tokens
    else
      # /boot is separate: ensure boot token exists and refers to actual device containing kernel
      if grep -qP '^\s*GRUB_CMDLINE_LINUX=.*\bboot=UUID=' /etc/default/grub; then
        current="$(grep -Po '^\s*GRUB_CMDLINE_LINUX=\".*\bboot=UUID=\K[^\" ]*' /etc/default/grub || true)"
        LOG "Found boot=UUID='${current:-<empty>}' in /etc/default/grub"
        if [[ -z "$current" ]]; then
          ERR "boot=UUID present but blank in /etc/default/grub; repairing with detected /boot UUID"
          if [[ -n "$BOOT_UUID" ]]; then
            insert_boot_uuid "$BOOT_UUID"
          else
            ERR "No /boot UUID available to repair; aborting to avoid FIPS boot failure."
            exit 8
          fi
        else
          # verify mapping and kernel presence
          dev_by_uuid="$(blkid -U "$current" 2>/dev/null || true)"
          if [[ -z "$dev_by_uuid" ]]; then
            ERR "Configured boot=UUID=${current} does not map to a device; attempting to repair"
            if [[ -n "$BOOT_UUID" ]]; then
              insert_boot_uuid "$BOOT_UUID"
            else
              ERR "No fallback /boot UUID available; aborting to avoid broken boot."
              exit 9
            fi
          else
            # strict check: ensure kernel exists on target device
            if ! kernel_file_exists_on_boot "$KVER"; then
              ERR "Expected kernel /boot/vmlinuz-${KVER} missing on /boot device ${dev_by_uuid}; aborting to avoid FIPS boot failure."
              exit 10
            fi
            LOG "boot=UUID ${current} validated and kernel file present; leaving as-is"
          fi
        fi
      else
        LOG "No boot=UUID token found in /etc/default/grub"
        # If kernel entries lack boot= and /boot is separate, insert (but only if safe)
        has_boot_token_in_kernels=$(grubby --info=ALL | grep -cE 'args=.*\bboot=' || true)
        if [[ "$has_boot_token_in_kernels" -eq 0 && -n "$BOOT_UUID" ]]; then
          LOG "Kernel entries missing boot= and /boot is separate; inserting boot=UUID=${BOOT_UUID}"
          insert_boot_uuid "$BOOT_UUID"
        else
          LOG "No insertion required (either kernels already have boot= or no /boot UUID)"
        fi
      fi
    fi

    # Rebuild initramfs again (strict)
    LOG "Rebuilding initramfs for kernel ${KVER} (post changes)"
    rebuild_initramfs_for_kver "$KVER"

    LOG "=== POST complete ==="
    ;;

  *)
    usage
    ;;
esac

LOG "Done."
exit 0
