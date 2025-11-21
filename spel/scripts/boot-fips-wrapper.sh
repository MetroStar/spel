#!/usr/bin/env bash
# boot-fips-wrapper.sh
#
# Usage:
#   sudo ./boot-fips-wrapper.sh pre    # run pre-Ansible preparation (Option A)
#   sudo ./boot-fips-wrapper.sh post   # run post-Ansible surgical fix (Option B)
#
# This script is idempotent and safe: it backs up /etc/default/grub and initramfs,
# never inserts blank boot=UUID=, and will not reboot the system.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: must run as root" >&2
  exit 2
fi

TIMESTAMP="$(date +%s)"
GRUB_DEFAULT_FILE="/etc/default/grub"

# --- helper functions -------------------------------------------------------
log() { printf '==> %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# Resolve /boot device (non-empty if /boot is a separate mount)
get_boot_device() {
  findmnt -n -o SOURCE --target /boot || true
}

get_boot_uuid() {
  local dev="$1"
  blkid -s UUID -o value "${dev}" 2>/dev/null || true
}

# Resolve grub cfg target in a portable way
resolve_grub_cfg_target() {
  if [[ -L /etc/grub2.cfg ]] && [[ -e "$(readlink -f /etc/grub2.cfg)" ]]; then
    readlink -f /etc/grub2.cfg
  elif [[ -d /sys/firmware/efi ]]; then
    vendor="$(ls /boot/efi/EFI 2>/dev/null | head -n1 || true)"
    if [[ -n "${vendor}" ]]; then
      echo "/boot/efi/EFI/${vendor}/grub.cfg"
    else
      echo "/boot/efi/EFI/oracle/grub.cfg"
    fi
  else
    echo "/boot/grub2/grub.cfg"
  fi
}

# --- Pre (Option A): prepare for Ansible STIG run ----------------------------
pre() {
  log "PRE: resolving /boot device"
  BOOT_DEV="$(get_boot_device)"
  if [[ -z "${BOOT_DEV}" ]]; then
    log "/boot is not a separate mount; nothing to do for boot=UUID. Exiting PRE."
    return 0
  fi
  log "/boot device: ${BOOT_DEV}"

  BOOT_UUID="$(get_boot_uuid "${BOOT_DEV}")"
  if [[ -z "${BOOT_UUID}" ]]; then
    err "Could not determine UUID for ${BOOT_DEV}; aborting PRE to avoid inserting blank value."
    return 1
  fi
  log "/boot UUID: ${BOOT_UUID}"

  # Ensure dracut-fips installed
  if rpm -q dracut-fips &>/dev/null; then
    log "dracut-fips already installed"
    DRACUT_INSTALLED=false
  else
    log "Installing dracut-fips"
    dnf -y install dracut-fips
    DRACUT_INSTALLED=true
  fi

  # Backup & rebuild initramfs for current kernel
  KVER="$(uname -r)"
  INITRD="/boot/initramfs-${KVER}.img"
  if [[ -f "${INITRD}" ]]; then
    cp -a "${INITRD}" "${INITRD}.bak.${TIMESTAMP}" || true
    log "Backed up ${INITRD} -> ${INITRD}.bak.${TIMESTAMP}"
  fi
  log "Rebuilding initramfs for ${KVER}"
  dracut -f "${INITRD}" "${KVER}"
  log "Initramfs rebuilt."

  # Backup /etc/default/grub safely
  if [[ -f "${GRUB_DEFAULT_FILE}" ]]; then
    cp -a "${GRUB_DEFAULT_FILE}" "${GRUB_DEFAULT_FILE}.bak.${TIMESTAMP}"
    log "Backed up ${GRUB_DEFAULT_FILE} -> ${GRUB_DEFAULT_FILE}.bak.${TIMESTAMP}"
  fi

  # Update kernel args (grubby) for all kernels, idempotent:
  log "Updating kernel args via grubby for all kernels"
  # list kernels
  kernels="$(grubby --info=ALL | awk -F: '/kernel/ {print $2}' | sed 's/^[ \t]*//')"
  for k in ${kernels}; do
    # defensively remove any existing boot tokens
    grubby --update-kernel="${k}" --remove-args="boot=UUID=" || true
    grubby --update-kernel="${k}" --remove-args="boot" || true
    grubby --update-kernel="${k}" --args="boot=UUID=${BOOT_UUID}"
  done
  log "grubby updated kernel args"

  # Safely update /etc/default/grub: replace or insert boot=UUID=...
  if grep -qP '^\s*GRUB_CMDLINE_LINUX=.*\bboot=UUID=' "${GRUB_DEFAULT_FILE}"; then
    sed -ri "s/(^\s*GRUB_CMDLINE_LINUX=.*)\bboot=UUID=[^\" ]*/\1boot=UUID=${BOOT_UUID}/" "${GRUB_DEFAULT_FILE}"
    log "Replaced existing boot=UUID in ${GRUB_DEFAULT_FILE}"
  else
    sed -ri "s/^(\\s*GRUB_CMDLINE_LINUX=\")/\\1boot=UUID=${BOOT_UUID} /" "${GRUB_DEFAULT_FILE}"
    log "Inserted boot=UUID into ${GRUB_DEFAULT_FILE}"
  fi

  # Regenerate grub config at target
  GRUB_CFG="$(resolve_grub_cfg_target)"
  log "Regenerating grub config at ${GRUB_CFG}"
  grub2-mkconfig -o "${GRUB_CFG}"
  log "PRE phase complete (no reboot performed)."
}

# --- Post (Option B): surgical repair ---------------------------------------
post() {
  log "POST: checking for blank or missing boot=UUID in ${GRUB_DEFAULT_FILE}"
  # Detect if boot=UUID= is present and possibly blank or wrong
  if ! grep -qP 'boot=UUID=' "${GRUB_DEFAULT_FILE}" 2>/dev/null; then
    log "No boot=UUID key in ${GRUB_DEFAULT_FILE}; nothing to do in POST."
    return 0
  fi

  # If UUID value is non-empty and looks correct, no repair necessary
  if grep -qP 'boot=UUID=[^\" ]+' "${GRUB_DEFAULT_FILE}" 2>/dev/null; then
    log "boot=UUID already present with a non-empty value; verifying target device matches /boot UUID."
    # Verify that the UUID present matches the /boot device's UUID (if /boot separate)
    BOOT_DEV="$(get_boot_device)"
    if [[ -z "${BOOT_DEV}" ]]; then
      log "/boot is not a separate mount; nothing to do."
      return 0
    fi
    CURRENT_UUID="$(get_boot_uuid "${BOOT_DEV}")"
    # Extract existing UUID from file (first occurrence)
    EXISTING_UUID="$(grep -oP 'boot=UUID=\K[^\" ]+' "${GRUB_DEFAULT_FILE}" | head -n1 || true)"
    if [[ "${EXISTING_UUID}" == "${CURRENT_UUID}" ]]; then
      log "Existing boot=UUID matches /boot UUID (${CURRENT_UUID}). Nothing to do."
      return 0
    else
      log "Existing boot=UUID (${EXISTING_UUID}) does NOT match /boot UUID (${CURRENT_UUID}). Will replace."
      # Replace with correct one
      cp -a "${GRUB_DEFAULT_FILE}" "${GRUB_DEFAULT_FILE}.bak.${TIMESTAMP}"
      sed -ri "s/\bboot=UUID=[^\" ]*/boot=UUID=${CURRENT_UUID}/g" "${GRUB_DEFAULT_FILE}"
      # Update grubby + grub.cfg too
      for k in $(grubby --info=ALL | awk -F: '/kernel/ {print $2}' | sed 's/^[ \t]*//'); do
        grubby --update-kernel="${k}" --remove-args="boot=UUID=" || true
        grubby --update-kernel="${k}" --args="boot=UUID=${CURRENT_UUID}"
      done
      GRUB_CFG="$(resolve_grub_cfg_target)"
      grub2-mkconfig -o "${GRUB_CFG}"
      log "POST repair: replaced boot=UUID and regenerated grub.cfg"
      return 0
    fi
  fi

  # At this point boot=UUID exists but with empty value (boot=UUID=) — fix it
  log "boot=UUID present but blank or malformed; attempting repair."

  BOOT_DEV="$(get_boot_device)"
  if [[ -z "${BOOT_DEV}" ]]; then
    err "No separate /boot mount found; aborting POST to avoid guessing UUID."
    return 1
  fi
  BOOT_UUID="$(get_boot_uuid "${BOOT_DEV}")"
  if [[ -z "${BOOT_UUID}" ]]; then
    err "Could not resolve UUID for ${BOOT_DEV}; aborting POST to avoid inserting blank value."
    return 1
  fi

  cp -a "${GRUB_DEFAULT_FILE}" "${GRUB_DEFAULT_FILE}.bak.${TIMESTAMP}"
  sed -ri "s/\bboot=UUID=[^\" ]*/boot=UUID=${BOOT_UUID}/g" "${GRUB_DEFAULT_FILE}"
  # Also apply to grubby and regenerate grub.cfg
  for k in $(grubby --info=ALL | awk -F: '/kernel/ {print $2}' | sed 's/^[ \t]*//'); do
    grubby --update-kernel="${k}" --remove-args="boot=UUID=" || true
    grubby --update-kernel="${k}" --args="boot=UUID=${BOOT_UUID}"
  done
  GRUB_CFG="$(resolve_grub_cfg_target)"
  grub2-mkconfig -o "${GRUB_CFG}"
  log "POST: repaired blank boot=UUID and updated kernel entries + grub.cfg"
}

# ---------------------------------------------------------------------------
# Main dispatch
if [[ $# -ne 1 ]]; then
  cat <<EOF
Usage: $0 <pre|post>

  pre  - prepare system for Ansible STIG run (install dracut-fips, rebuild initramfs,
         update /etc/default/grub and kernel args, regenerate grub.cfg)
  post - surgical repair after Ansible run (fix blank/incorrect boot=UUID entries,
         update grubby and regenerate grub.cfg)

EOF
  exit 2
fi

case "$1" in
  pre)  pre ;;
  post) post ;;
  *) err "unknown mode: $1"; exit 2 ;;
esac

exit 0
