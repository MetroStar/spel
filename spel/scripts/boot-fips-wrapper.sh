#!/usr/bin/env bash
# /tmp/boot-fips-wrapper.sh
# Robust + strict wrapper: ensures boot=UUID points to the partition that actually
# contains /boot/vmlinuz-$KVER and enforces presence of the kernel HMAC needed
# by dracut-fips. Exits non-zero with clear logs on any fatal mismatch.
set -euo pipefail
shopt -s extglob

LOG() { printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
ERR() { LOG "ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage: $0 pre|post

pre  - prepare: install dracut-fips if possible, rebuild initramfs (strict),
       and insert boot=UUID that points to the device actually holding /boot/vmlinuz-$KVER.
post - verify & repair boot=UUID if it doesn't point at the kernel-containing device,
       ensure HMACs are present, rebuild initramfs (strict) and regen grub.cfg.

This script is strict: it will exit non-zero if required kernel files or HMACs are missing.
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

# Find mount sources
BOOT_SRC="$(findmnt -n -o SOURCE --target /boot 2>/dev/null || true)"
ROOT_SRC="$(findmnt -n -o SOURCE --target / 2>/dev/null || true)"

LOG "Resolving /boot device and root device..."
LOG "/boot source : ${BOOT_SRC:-<none>}"
LOG "/ root source : ${ROOT_SRC:-<none>}"

# Determine if /boot is a separate device
BOOT_IS_SEPARATE="false"
if [[ -n "$BOOT_SRC" && -n "$ROOT_SRC" && "$BOOT_SRC" != "$ROOT_SRC" ]]; then
  BOOT_IS_SEPARATE="true"
fi

# Kernel version to operate on
KVER="$(uname -r)"
LOG "Working kernel version: ${KVER}"

# convenience tests
kernel_file_exists_on_path() {
  local kpath="$1"
  [[ -f "$kpath" ]]
}

# Determine the device that actually contains the kernel files:
# prefer the mounted /boot that contains vmlinuz-$KVER; fallback to search.
detect_device_holding_kernel() {
  local kver="$1"

  # first, prefer the currently mounted /boot (if it contains vmlinuz-$kver)
  if [[ -n "$BOOT_SRC" ]]; then
    if kernel_file_exists_on_path "/boot/vmlinuz-${kver}"; then
      echo "$BOOT_SRC"
      return 0
    fi
  fi

  # fallback: search all mounted filesystems for the kernel path
  while read -r mp src; do
    if [[ -f "${mp}/vmlinuz-${kver}" ]]; then
      echo "$src"
      return 0
    fi
  done < <(findmnt -rn -o TARGET,SOURCE)

  # final fallback: try scanning blkid devices for a vmlinuz file (rare)
  # (search common device mounts under /run/media, /mnt, etc.)
  for d in /mnt /run/media /media; do
    if [[ -d "$d" ]]; then
      while read -r mp src; do
        if [[ -f "${mp}/vmlinuz-${kver}" ]]; then
          echo "$src"
          return 0
        fi
      done < <(findmnt -rn -o TARGET,SOURCE "$d" 2>/dev/null || true)
    fi
  done

  return 1
}

# Get UUID for a block device path (source from findmnt e.g. /dev/nvme0n1p3 or /dev/mapper/...)
device_uuid() {
  local src="$1"
  # If source is a mapper name (/dev/mapper/...), blkid works; handle LVM devices too.
  blkid -s UUID -o value "$src" 2>/dev/null || true
}

# Strict: check hmac presence for kernel (dracut-fips expects /boot/.vmlinuz-<kver>.hmac)
hmac_path_for_kver() {
  local kver="$1"
  # many distros create a hidden .vmlinuz-<kver>.hmac in /boot
  echo "/boot/.vmlinuz-${kver}.hmac"
}

# Rebuild initramfs (strict); exit if expected files missing
rebuild_initramfs_for_kver() {
  local kver="$1"
  if [[ -z "$kver" ]]; then
    ERR "Empty kernel version passed to rebuild_initramfs_for_kver"
    return 1
  fi

  # Ensure kernel file is present on the device that will be used by boot=UUID
  if ! kernel_file_exists_on_path "/boot/vmlinuz-${kver}"; then
    ERR "Missing kernel file /boot/vmlinuz-${kver} on the mounted /boot. Aborting to avoid broken initramfs."
    exit 3
  fi

  # backup initramfs if present
  if [[ -f "/boot/initramfs-${kver}.img" ]]; then
    backup_file "/boot/initramfs-${kver}.img"
  fi

  # choose dracut invocation: try to include fips if available
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
    LOG "Regenerating grub config at /boot/efi/EFI/redhat/grub.cfg (or distro-specific path)"
    # prefer redhat path on RHEL; if missing create directory fallback to oracle to avoid mkconfig failure
    if [[ -d /boot/efi/EFI/redhat || ! -d /boot/efi/EFI/oracle ]]; then
      grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
    else
      mkdir -p /boot/efi/EFI/oracle
      grub2-mkconfig -o /boot/efi/EFI/oracle/grub.cfg
    fi
  else
    LOG "Regenerating grub config at /boot/grub2/grub.cfg"
    grub2-mkconfig -o /boot/grub2/grub.cfg
  fi
}

# Insert or replace boot=UUID ensuring it points at the device that contains vmlinuz/$KVER
insert_or_replace_boot_uuid_with_kernel_device() {
  local want_dev="$1"   # device path, e.g. /dev/nvme0n1p3
  local want_uuid
  want_uuid="$(device_uuid "$want_dev" || true)"
  if [[ -z "$want_uuid" ]]; then
    ERR "Could not determine UUID for device $want_dev; aborting insertion."
    exit 6
  fi

  LOG "Will ensure boot=UUID=${want_uuid} (device ${want_dev}) is set in kernel args and /etc/default/grub"

  # Update grubby kernel entries defensively: remove any boot= tokens and add correct one
  LOG "Updating kernel args via grubby for all kernels (defensively removing prior boot tokens)"
  # iterate kernels known to grubby
  mapfile -t KERNEL_PATHS < <(grubby --info=ALL 2>/dev/null | awk -F: '/kernel/ {print $2}' | sed 's/^[ \t]*//' || true)
  if [[ ${#KERNEL_PATHS[@]} -eq 0 ]]; then
    LOG "No kernel paths returned by grubby --info=ALL; skipping grubby updates"
  else
    for kernpath in "${KERNEL_PATHS[@]}"; do
      LOG "Updating kernel entry ${kernpath}"
      grubby --update-kernel="$kernpath" --remove-args="boot" || true
      grubby --update-kernel="$kernpath" --remove-args="boot=UUID=" || true
      grubby --update-kernel="$kernpath" --args="boot=UUID=${want_uuid}" || true
    done
  fi

  # Edit /etc/default/grub: remove previous boot tokens and set to the correct UUID
  backup_file /etc/default/grub
  if grep -qP '^\s*GRUB_CMDLINE_LINUX=' /etc/default/grub; then
    # remove any existing boot= tokens (basic, conservative regex)
    sed -ri 's/\bboot=UUID=[^" ]+ ?//g; s/\bboot=[^" ]+ ?//g' /etc/default/grub
    # append the desired token inside the quoted cmdline
    sed -ri -e '/^\s*GRUB_CMDLINE_LINUX="/ {
      s@"$@ boot=UUID='"${want_uuid}"'"@
    }' /etc/default/grub
  else
    printf 'GRUB_CMDLINE_LINUX="boot=UUID=%s"\n' "$want_uuid" >> /etc/default/grub
  fi

  LOG "Inserted/updated boot=UUID=${want_uuid} into /etc/default/grub; regenerating grub.cfg"
  regenerate_grub_cfg
}

# Remove any boot= tokens (strict)
remove_boot_tokens() {
  LOG "Removing any boot= tokens from kernel args and /etc/default/grub"

  # Remove from kernels
  mapfile -t KERNEL_PATHS < <(grubby --info=ALL 2>/dev/null | awk -F: '/kernel/ {print $2}' | sed 's/^[ \t]*//' || true)
  for kernpath in "${KERNEL_PATHS[@]:-}"; do
    grubby --update-kernel="$kernpath" --remove-args="boot" || true
    grubby --update-kernel="$kernpath" --remove-args="boot=UUID=" || true
  done

  # Remove from /etc/default/grub (backup first)
  backup_file /etc/default/grub
  sed -ri 's/\bboot=UUID=[^" ]+ ?//g; s/\bboot=[^" ]+ ?//g' /etc/default/grub || true

  LOG "Removed boot= tokens and regenerating grub.cfg"
  regenerate_grub_cfg
}

# MAIN
case "$MODE" in
  pre)
    LOG "=== PRE mode ==="

    # Ensure dracut-fips if desired (best-effort)
    if ! rpm -q --quiet dracut-fips; then
      LOG "dracut-fips not installed; attempting install (if repo provides it)"
      if command -v dnf >/dev/null 2>&1; then
        if ! dnf -y install dracut-fips; then
          LOG "Warning: dracut-fips install failed or not available; continuing but initramfs may not include fips hooks."
        fi
      else
        if ! yum -y install dracut-fips; then
          LOG "Warning: dracut-fips install failed or not available; continuing but initramfs may not include fips hooks."
        fi
      fi
    else
      LOG "dracut-fips already installed"
    fi

    # Rebuild initramfs now (strict)
    LOG "Rebuilding initramfs for kernel ${KVER} (strict checks enabled)"
    rebuild_initramfs_for_kver "$KVER"

    # Determine which device actually contains the kernel files, prefer the mounted /boot
    if ! kernel_device=$(detect_device_holding_kernel "$KVER"); then
      ERR "Could not detect any device that contains /boot/vmlinuz-${KVER}. Aborting."
      exit 11
    fi
    LOG "Detected kernel-containing device: ${kernel_device}"

    # If /boot is separate, insert boot=UUID for the device that actually holds the kernel
    if [[ "$BOOT_IS_SEPARATE" == "true" ]]; then
      device_uuid_val="$(device_uuid "$kernel_device" || true)"
      if [[ -z "$device_uuid_val" ]]; then
        ERR "Kernel device ${kernel_device} has no UUID according to blkid; aborting to avoid creating broken boot entry."
        exit 12
      fi
      LOG "/boot is separate; ensuring boot=UUID=${device_uuid_val} (device ${kernel_device})"
      insert_or_replace_boot_uuid_with_kernel_device "$kernel_device"
    else
      LOG "/boot is NOT a separate device; not inserting boot=UUID (removing any existing ones for safety)"
      remove_boot_tokens
    fi

    LOG "=== PRE complete ==="
    ;;

  post)
    LOG "=== POST mode ==="

    # figure out device that actually contains kernel files
    if ! kernel_device=$(detect_device_holding_kernel "$KVER"); then
      ERR "Could not detect device containing /boot/vmlinuz-${KVER}; aborting."
      exit 13
    fi
    kernel_uuid="$(device_uuid "$kernel_device" || true)"
    LOG "Kernel files detected on device ${kernel_device} (UUID=${kernel_uuid:-<none>})"

    # If /boot is not separate ensure tokens are removed
    if [[ "$BOOT_IS_SEPARATE" != "true" ]]; then
      LOG "/boot is not separate; ensure no boot= tokens remain"
      remove_boot_tokens
    else
      # Check GRUB_CMDLINE_LINUX for boot=UUID
      if grep -qP '^\s*GRUB_CMDLINE_LINUX=.*\bboot=UUID=' /etc/default/grub; then
        current="$(grep -Po '^\s*GRUB_CMDLINE_LINUX=\".*\bboot=UUID=\K[^\" ]*' /etc/default/grub || true)"
        LOG "Found boot=UUID='${current:-<empty>}' in /etc/default/grub"

        if [[ -z "$current" ]]; then
          ERR "boot=UUID present but blank in /etc/default/grub; repairing to kernel's device"
          insert_or_replace_boot_uuid_with_kernel_device "$kernel_device"
        else
          # Map the configured UUID to a device and ensure it actually contains the kernel
          configured_dev="$(blkid -U "$current" 2>/dev/null || true)"
          if [[ -z "$configured_dev" ]]; then
            ERR "Configured boot=UUID=${current} does not map to a device via blkid; replacing with kernel device UUID ${kernel_uuid}"
            insert_or_replace_boot_uuid_with_kernel_device "$kernel_device"
          else
            LOG "Configured boot=UUID ${current} maps to device ${configured_dev}"
            # verify that the configured device is the same as the kernel device
            if [[ "$configured_dev" != "$kernel_device" ]]; then
              ERR "Configured boot=UUID ${current} does not point at the device that contains vmlinuz-${KVER} (${kernel_device}). Replacing it."
              insert_or_replace_boot_uuid_with_kernel_device "$kernel_device"
            else
              LOG "boot=UUID matches the actual kernel device; leaving as-is"
            fi
          fi
        fi
      else
        # No boot token found; if /boot is separate, set it to the kernel device UUID
        if [[ -n "$kernel_uuid" ]]; then
          LOG "No boot= token found in /etc/default/grub but /boot is separate -> inserting boot=UUID=${kernel_uuid}"
          insert_or_replace_boot_uuid_with_kernel_device "$kernel_device"
        else
          LOG "No boot= token and could not determine kernel device UUID; leaving unchanged"
        fi
      fi
    fi

    # Now check presence of the kernel HMAC expected by dracut-fips
    HMAC_PATH="$(hmac_path_for_kver "$KVER")"
    if [[ -f "$HMAC_PATH" ]]; then
      LOG "Found kernel HMAC at ${HMAC_PATH}"
    else
      ERR "Missing kernel HMAC file ${HMAC_PATH}. dracut-FIPS will refuse to boot without that HMAC present."
      LOG "Suggested remediation (pick one):"
      LOG "  * Ensure dracut-fips (or the distro mechanism that generates HMACs) is installed and that kernel packaging hooks created the HMAC."
      LOG "  * Rebuild initramfs and ensure any distro kernel-install hooks run. Example:"
      LOG "      # dnf install dracut-fips   # (if available)"
      LOG "      # dracut -f -v --add fips --kver ${KVER}"
      LOG "  After creating the HMAC (usually created by the kernel packaging hooks), rerun this script."
      exit 14
    fi

    # Rebuild initramfs again (post changes)
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
