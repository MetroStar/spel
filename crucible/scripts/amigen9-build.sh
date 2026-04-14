#!/bin/bash
# shellcheck disable=SC2034,SC2046
#
# Execute AMIGen9 scripts to prepare an EC2 instance for the AMI Create Image
# task.
#
##############################################################################
PROGNAME="$(basename "$0")"
AMIGENBOOTSIZE="${CRUCIBLE_AMIGENBOOTDEVSZ:-768}"
AMIGENBOOTLABL="${CRUCIBLE_AMIGENBOOTDEVLBL:-boot_disk}"
AMIGENBRANCH="${CRUCIBLE_AMIGENBRANCH:-main}"
AMIGENCHROOT="${CRUCIBLE_AMIGENCHROOT:-/mnt/ec2-root}"
AMIGENCROSSDISTRO="${CRUCIBLE_AMIGENCROSSDISTRO:-false}"
AMIGENNOSIGNATURE="${CRUCIBLE_AMIGENNOSIGNATURE:-false}"
AMIGENFSTYPE="${CRUCIBLE_AMIGENFSTYPE:-xfs}"
AMIGENICNCTURL="${CRUCIBLE_AMIGENICNCTURL}"
AMIGENMANFST="${CRUCIBLE_AMIGENMANFST}"
AMIGENMANFSTAL2023="${CRUCIBLE_AMIGENMANFSTAL2023}"
AMIGENPKGGRP="${CRUCIBLE_AMIGENPKGGRP:-core}"
AMIGENREPOS="${CRUCIBLE_AMIGENREPOS}"
AMIGENREPOSRC="${CRUCIBLE_AMIGENREPOSRC}"
AMIGENROOTNM="${CRUCIBLE_AMIGENROOTNM}"
AMIGENSOURCE="${CRUCIBLE_AMIGEN9SOURCE:-file://$(dirname $(dirname $(dirname $(readlink -f "$0"))))/vendor/amigen9}"
AMIGENSSMAGENT="${CRUCIBLE_AMIGENSSMAGENT}"
AMIGENSTORLAY="${CRUCIBLE_AMIGENSTORLAY}"
AMIGENTIMEZONE="${CRUCIBLE_TIMEZONE:-UTC}"
AMIGENUEFISIZE="${CRUCIBLE_AMIGENUEFIDEVSZ:-128}"
AMIGENUEFILABL="${CRUCIBLE_AMIGENUEFIDEVLBL:-UEFI_DISK}"
AMIGENVGNAME="${CRUCIBLE_AMIGENVGNAME}"
AWSCFNBOOTSTRAP="${CRUCIBLE_AWSCFNBOOTSTRAP}"
AWSCLIV1SOURCE="${CRUCIBLE_AWSCLIV1SOURCE}"
AWSCLIV2SOURCE="${CRUCIBLE_AWSCLIV2SOURCE:-https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip}"
CLOUDPROVIDER="${CRUCIBLE_CLOUDPROVIDER:-aws}"
EXTRARPMS="${CRUCIBLE_EXTRARPMS}"
FIPSDISABLE="${CRUCIBLE_FIPSDISABLE}"
GRUBTMOUT="${CRUCIBLE_GRUBTMOUT:-5}"
HTTP_PROXY="${CRUCIBLE_HTTP_PROXY}"
USEDEFAULTREPOS="${CRUCIBLE_USEDEFAULTREPOS:-true}"
USEROOTDEVICE="${CRUCIBLE_USEROOTDEVICE:-true}"
AMIGENSSLVERIFY="${CRUCIBLE_AMIGENSSLVERIFY:-true}"


ELBUILD="/tmp/el-build"

# Debug: Show air-gapped build configuration
echo "=== Air-Gapped Build Configuration ==="
echo "CRUCIBLE_AMIGENCROSSDISTRO=${CRUCIBLE_AMIGENCROSSDISTRO:-not set}"
echo "AMIGENCROSSDISTRO=${AMIGENCROSSDISTRO}"
echo "CRUCIBLE_AMIGENNOSIGNATURE=${CRUCIBLE_AMIGENNOSIGNATURE:-not set}"
echo "AMIGENNOSIGNATURE=${AMIGENNOSIGNATURE}"
echo "CRUCIBLE_USEDEFAULTREPOS=${CRUCIBLE_USEDEFAULTREPOS:-not set}"
echo "CRUCIBLE_AMIGENREPOSRC=${CRUCIBLE_AMIGENREPOSRC:-not set}"
echo "CRUCIBLE_AMIGENREPOS=${CRUCIBLE_AMIGENREPOS:-not set}"
echo "CRUCIBLE_AMIGENSSLVERIFY=${CRUCIBLE_AMIGENSSLVERIFY:-not set}"
echo "AMIGENSSLVERIFY=${AMIGENSSLVERIFY}"
echo "======================================="

# Make interactive-execution more-verbose unless explicitly told not to
if [[ $( tty -s ) -eq 0 ]] && [[ -z ${DEBUG:-} ]]
then
    DEBUG="true"
fi


# Error handler function
function err_exit {
    local ERRSTR
    local ISNUM
    local SCRIPTEXIT

    ERRSTR="${1}"
    ISNUM='^[0-9]+$'
    SCRIPTEXIT="${2:-1}"

    if [[ ${DEBUG} == true ]]
    then
        # Our output channels
        logger -i -t "${PROGNAME}" -p kern.crit -s -- "${ERRSTR}"
    else
        logger -i -t "${PROGNAME}" -p kern.crit -- "${ERRSTR}"
    fi

    # Only exit if requested exit is numerical
    if [[ ${SCRIPTEXIT} =~ ${ISNUM} ]]
    then
        exit "${SCRIPTEXIT}"
    fi
}

# Setup per-builder values
case $( rpm -qf /etc/os-release --qf '%{name}' ) in
    almalinux-release)
        BUILDER=alma-9
        DEFAULTREPOS=(
            baseos
            appstream
            extras
        )
        ;;
    centos-linux-release | centos-stream-release )
        BUILDER=centos-9stream

        DEFAULTREPOS=(
            baseos
            appstream
            extras-common
        )
        ;;
    oraclelinux-release)
        BUILDER=ol-9

        DEFAULTREPOS=(
            ol9_UEKR7
            ol9_appstream
            ol9_baseos_latest
        )
        ;;
    redhat-release-server|redhat-release)
        BUILDER=rhel-9

        DEFAULTREPOS=(
            rhel-9-appstream-rhui-rpms
            rhel-9-baseos-rhui-rpms
            rhui-client-config-server-9
        )
        ;;
    rocky-release)
        BUILDER=rl-9

        DEFAULTREPOS=(
            baseos
            appstream
            extras
        )
        ;;

    system-release) # Amazon should be shot for this
        BUILDER=amzn-2023

        DEFAULTREPOS=(
            amazonlinux
            kernel-livepatch
        )
        ;;
    *)
        echo "Unknown OS. Aborting" >&2
        exit 1
        ;;
esac
DEFAULTREPOS+=()

# Default to enabling default repos
ENABLEDREPOS=$(IFS=,; echo "${DEFAULTREPOS[*]}")

if [[ "$USEDEFAULTREPOS" != "true" ]]
then
    # Enable AMIGENREPOS exclusively when instructed not to use default repos
    ENABLEDREPOS="${AMIGENREPOS}"
elif [[ -n "${AMIGENREPOS:-}" ]]
then
    # When using default repos, also enable AMIGENREPOS if present
    ENABLEDREPOS+=,"${AMIGENREPOS}"
fi

export FIPSDISABLE

# Export NOSIGNATURE for unsigned repo RPMs in air-gapped environments
if [[ "${AMIGENNOSIGNATURE}" == "true" ]]; then
    export NOSIGNATURE="true"
fi

# Export ISCROSSDISTRO for OSpackages.sh to skip auto-detecting RHUI packages
# from the builder host's /etc/yum.repos.d/* (required for air-gapped builds)
if [[ "${AMIGENCROSSDISTRO}" == "true" ]]; then
    export ISCROSSDISTRO="TRUE"
    echo "ISCROSSDISTRO exported as TRUE - will skip RHUI package auto-detection"
fi


retry()
{
    # Make an arbitrary number of attempts to execute an arbitrary command,
    # passing it arbitrary parameters. Convenient for working around
    # intermittent errors (which occur often with poor repo mirrors).
    #
    # Returns the exit code of the command.
    local n=0
    local try=$1
    local cmd="${*: 2}"
    local result=1
    [[ $# -le 1 ]] && {
        echo "Usage $0 <number_of_retry_attempts> <Command>"
        exit $result
    }

    echo "Will try $try time(s) :: $cmd"

    if [[ "${SHELLOPTS}" == *":errexit:"* ]]
    then
        set +e
        local ERREXIT=1
    fi

    until [[ $n -ge $try ]]
    do
        sleep $n
        $cmd
        result=$?
        if [[ $result -eq 0 ]]
        then
            break
        else
            ((n++))
            echo "Attempt $n, command failed :: $cmd"
        fi
    done

    if [[ "${ERREXIT}" == "1" ]]
    then
        set -e
    fi

    return $result
}  # ----------  end of function retry  ----------

# Run the builder-scripts
function BuildChroot {
    local STATUS_MSG

    # Prepare the build device
    PrepBuildDevice

    # Invoke disk-partitioner
    bash -euxo pipefail "${ELBUILD}"/$( ComposeDiskSetupString ) || \
        err_exit "Failure encountered with DiskSetup.sh"

    # Invoke chroot-env disk-mounter
    bash -euxo pipefail "${ELBUILD}"/$( ComposeChrootMountString ) || \
        err_exit "Failure encountered with MkChrootTree.sh"

    # Disable SSL verification in chroot for air-gapped builds with self-signed certs
    if [[ "${AMIGENSSLVERIFY}" == "false" ]]
    then
        echo "Disabling SSL verification in chroot for air-gapped builds..."
        # Configure dnf.conf in chroot
        if [[ -f "${AMIGENCHROOT}/etc/dnf/dnf.conf" ]]
        then
            if ! grep -q "^sslverify" "${AMIGENCHROOT}/etc/dnf/dnf.conf"
            then
                echo "sslverify=0" >> "${AMIGENCHROOT}/etc/dnf/dnf.conf"
                echo "Added sslverify=0 to ${AMIGENCHROOT}/etc/dnf/dnf.conf"
            fi
        fi
        # Also set for any repo files that might exist
        for REPOFILE in "${AMIGENCHROOT}"/etc/yum.repos.d/*.repo
        do
            if [[ -f "${REPOFILE}" ]] && ! grep -q "^sslverify" "${REPOFILE}"
            then
                # Add sslverify=0 after each [reponame] section
                sed -i '/^\[.*\]$/a sslverify=0' "${REPOFILE}"
                echo "Added sslverify=0 to ${REPOFILE}"
            fi
        done
    fi

    # Bind-mount offline-packages into chroot for offline/air-gapped builds
    if [[ -d /tmp/offline-packages ]]
    then
        echo "Setting up offline-packages in chroot..."
        mkdir -p "${AMIGENCHROOT}/tmp/offline-packages" || \
            err_exit "Failed creating ${AMIGENCHROOT}/tmp/offline-packages"
        mount --bind /tmp/offline-packages "${AMIGENCHROOT}/tmp/offline-packages" || \
            err_exit "Failed bind-mounting offline-packages into chroot"
        echo "Offline packages mounted at ${AMIGENCHROOT}/tmp/offline-packages:"
        ls -lh /tmp/offline-packages/ | head -20 || true
    else
        echo "No offline-packages directory found (online mode)"
    fi

    # Invoke OS software installer
    bash -euxo pipefail "${ELBUILD}"/$( ComposeOSpkgString ) || \
        err_exit "Failure encountered with OSpackages.sh"

    # Invoke CSP-specific utilities scripts
    case "${CLOUDPROVIDER}" in
        # Invoke AWSutils installer
        aws)
            bash -euxo pipefail "${ELBUILD}"/$( ComposeAWSutilsString ) || \
                err_exit "Failure encountered with AWSutils.sh"
            ;;
        *)
            # Concat exit-message string
            STATUS_MSG="Unsupported value [${CLOUDPROVIDER}] for CLOUDPROVIDER."
            STATUS_MSG="${STATUS_MSG} No provider-specific utilities"
            STATUS_MSG="${STATUS_MSG} will be installed"

            # Log but do not fail-out
            err_exit "${STATUS_MSG}" NONE
            ;;
    esac

    # Unmount offline-packages bind-mount before PostBuild to prevent fstab entry
    if [[ -d "${AMIGENCHROOT}/tmp/offline-packages" ]]
    then
        echo "Checking offline-packages mount status..."
        if mountpoint "${AMIGENCHROOT}/tmp/offline-packages" > /dev/null 2>&1
        then
            echo "Unmounting offline-packages bind-mount before PostBuild..."
            umount "${AMIGENCHROOT}/tmp/offline-packages" || \
                err_exit "Failed unmounting offline-packages bind-mount"
            echo "Successfully unmounted offline-packages"
        else
            echo "offline-packages directory exists but is not mounted"
        fi
        rm -rf "${AMIGENCHROOT}/tmp/offline-packages" || true
        echo "Cleaned up offline-packages directory in chroot"
    else
        echo "No offline-packages directory found in chroot (online mode or already cleaned)"
    fi

    # Post-installation configurator
    bash -euxo pipefail "${ELBUILD}"/$( PostBuildString ) || \
        err_exit "Failure encountered with PostBuild.sh"

    # Collect insallation-manifest
    CollectManifest

    # Invoke unmounter
    bash -euxo pipefail "${ELBUILD}"/Umount.sh -c "${AMIGENCHROOT}" || \
        err_exit "Failure encountered with Umount.sh"
}

# Create a record of the build
function CollectManifest {
    echo "Saving the release info to the manifest"
    grep "PRETTY_NAME=" "${AMIGENCHROOT}/etc/os-release" | \
        cut --delimiter '"' -f2 > /tmp/manifest.txt

    if [[ "${CLOUDPROVIDER}" == "aws" ]]
    then
        if [[ -n "$AWSCLIV1SOURCE" ]]
        then
            echo "Saving the aws-cli-v1 version to the manifest"
            [[ -o xtrace ]] && XTRACE='set -x' || XTRACE='set +x'
            set +x
            (chroot "${AMIGENCHROOT}" /usr/local/bin/aws1 --version) 2>&1 | \
                tee -a /tmp/manifest.txt
            eval "$XTRACE"
        fi
        if [[ -n "$AWSCLIV2SOURCE" ]]
        then
            echo "Saving the aws-cli-v2 version to the manifest"
            [[ -o xtrace ]] && XTRACE='set -x' || XTRACE='set +x'
            set +x
            (chroot "${AMIGENCHROOT}" /usr/local/bin/aws2 --version) 2>&1 | \
                tee -a /tmp/manifest.txt
            eval "$XTRACE"
        fi
        if [[ -n "$AWSCFNBOOTSTRAP" ]]
        then
            echo "Saving the cfn bootstrap version to the manifest"
            [[ -o xtrace ]] && XTRACE='set -x' || XTRACE='set +x'
            set +x
            (chroot "${AMIGENCHROOT}" python3 -m pip list) | \
                grep aws-cfn-bootstrap | tee -a /tmp/manifest.txt
            eval "$XTRACE"
        fi
    fi

    echo "Saving the RPM manifest"
    rpm --root "${AMIGENCHROOT}" -qa | sort -u >> /tmp/manifest.txt
}

# Pick options for the AWSutils install command
function ComposeAWSutilsString {
    local AWSUTILSSTRING

    AWSUTILSSTRING="AWSutils.sh "

    # Set services to enable
    AWSUTILSSTRING+="-t amazon-ssm-agent "

    # Set location for chroot-env
    if [[ ${AMIGENCHROOT} == "/mnt/ec2-root" ]]
    then
        err_exit "Using default chroot-env location [${AMIGENCHROOT}]" NONE
    else
        AWSUTILSSTRING+="-m ${AMIGENCHROOT} "
    fi

    # Whether to install AWS CLIv1
    if [[ -n "${AWSCLIV1SOURCE}" ]]
    then
        AWSUTILSSTRING+="-C ${AWSCLIV1SOURCE} "
    fi

    # Whether to install AWS CLIv2
    if [[ -n "${AWSCLIV2SOURCE}" ]]
    then
        AWSUTILSSTRING+="-c ${AWSCLIV2SOURCE} "
    fi

    # Whether to install AWS SSM-agent
    if [[ -z ${AMIGENSSMAGENT:-} ]]
    then
        err_exit "Skipping install of AWS SSM-agent" NONE
    else
        AWSUTILSSTRING+="-s ${AMIGENSSMAGENT} "
    fi

    # Whether to install AWS InstanceConnect
    if [[ -z ${AMIGENICNCTURL:-} ]]
    then
        err_exit "Skipping install of AWS SSM-agent" NONE
    else
        AWSUTILSSTRING+="-i ${AMIGENICNCTURL} "
    fi

    # Whether to install cfnbootstrap
    if [[ -z "${AWSCFNBOOTSTRAP:-}" ]]
    then
        err_exit "Skipping install of AWS CFN Bootstrap" NONE
    else
        AWSUTILSSTRING+="-n ${AWSCFNBOOTSTRAP} "
    fi

    # Return command-string for AWSutils-script
    echo "${AWSUTILSSTRING}"
}

# Pick options for chroot-mount command
function ComposeChrootMountString {
    local MOUNTCHROOTCMD

    MOUNTCHROOTCMD="MkChrootTree.sh "

    # Set location for chroot-env
    if [[ ${AMIGENCHROOT} == "/mnt/ec2-root" ]]
    then
        err_exit "Using default chroot-env location [${AMIGENCHROOT}]" NONE
    else
        MOUNTCHROOTCMD+="-m ${AMIGENCHROOT} "
    fi

    # Set the filesystem-type to use for OS filesystems
    if [[ ${AMIGENFSTYPE} == "xfs" ]]
    then
        err_exit "Using default fstype [xfs] for boot filesysems" NONE
    else
        MOUNTCHROOTCMD+="-f ${AMIGENFSTYPE} "
    fi

    # Set requested custom storage layout as necessary
    if [[ -z ${AMIGENSTORLAY:-} ]]
    then
        err_exit "Using script-default for boot-volume layout" NONE
    else
        MOUNTCHROOTCMD+="-p ${AMIGENSTORLAY} "
    fi

    # Set device to mount
    if [[ -z ${AMIGENBUILDDEV:-} ]]
    then
        err_exit "Failed to define device to partition"
    else
        MOUNTCHROOTCMD+="-d ${AMIGENBUILDDEV}"
    fi

    # Return command-string for mount-script
    echo "${MOUNTCHROOTCMD}"
}

## # Pick options for disk-setup command
function ComposeDiskSetupString {
    local DISKSETUPCMD

    DISKSETUPCMD="DiskSetup.sh "

    # Set the size for the /boot partition
    if [[ -z ${AMIGENBOOTSIZE:-} ]]
    then
        err_exit "Setting /boot size to 512MiB" NONE
        DISKSETUPCMD+="-B 512 "
    else
        DISKSETUPCMD+="-B ${AMIGENBOOTSIZE} "
    fi

    # Set the value of the fs-label for the /boot partition
    if [[ -z ${AMIGENBOOTLABL:-} ]]
    then
        err_exit "Setting /boot fs-label to 'boot_disk'." NONE
        DISKSETUPCMD+="-l boot_disk "
    else
        DISKSETUPCMD+="-l ${AMIGENBOOTLABL} "
    fi

    # Set the size for the /boot/efi partition
    if [[ -z ${AMIGENUEFISIZE:-} ]]
    then
        err_exit "Setting /boot/efi size to 256MiB" NONE
        DISKSETUPCMD+="-U 256 "
    else
        DISKSETUPCMD+="-U ${AMIGENUEFISIZE} "
    fi

    # Set the value of the fs-label for the /boot partition
    if [[ -z ${AMIGENUEFILABL:-} ]]
    then
        err_exit "Setting /boot/efi fs-label to 'UEFI_DISK'." NONE
        DISKSETUPCMD+="-L UEFI_DISK "
    else
        DISKSETUPCMD+="-L ${AMIGENUEFILABL} "
    fi

    # Set the filesystem-type to use for OS filesystems
    if [[ ${AMIGENFSTYPE} == "xfs" ]]
    then
        err_exit "Using default fstype [xfs] for boot filesysems" NONE
    fi
    DISKSETUPCMD+="-f ${AMIGENFSTYPE} "

    # Set requested custom storage layout as necessary
    if [[ -z ${AMIGENSTORLAY:-} ]]
    then
        err_exit "Using script-default for boot-volume layout" NONE
    else
        DISKSETUPCMD+="-p ${AMIGENSTORLAY} "
    fi

    # Set LVM2 or bare disk-formatting
    if [[ -n ${AMIGENVGNAME:-} ]]
    then
        DISKSETUPCMD+="-v ${AMIGENVGNAME} "
    elif [[ -n ${AMIGENROOTNM:-} ]]
    then
        DISKSETUPCMD+="-r ${AMIGENROOTNM} "
    fi

    # Set device to carve
    if [[ -z ${AMIGENBUILDDEV:-} ]]
    then
        err_exit "Failed to define device to partition"
    else
        DISKSETUPCMD+="-d ${AMIGENBUILDDEV}"
    fi

    # Return command-string for disk-setup script
    echo "${DISKSETUPCMD}"
}

# Pick options for the OS-install command
function ComposeOSpkgString {
    local OSPACKAGESTRING

    OSPACKAGESTRING="OSpackages.sh "

    # Set location for chroot-env
    if [[ ${AMIGENCHROOT} == "/mnt/ec2-root" ]]
    then
        err_exit "Using default chroot-env location [${AMIGENCHROOT}]" NONE
    else
        OSPACKAGESTRING+="-m ${AMIGENCHROOT} "
    fi

    # Pick custom yum repos
    if [[ -z ${ENABLEDREPOS:-} ]]
    then
        err_exit "Using script-default yum repos" NONE
    else
        OSPACKAGESTRING+="-a ${ENABLEDREPOS} "
    fi

    # Custom repo-def RPMs to install
    if [[ -z ${AMIGENREPOSRC:-} ]]
    then
        err_exit "Installing no custom repo-config RPMs" NONE
    else
        OSPACKAGESTRING+="-r ${AMIGENREPOSRC} "
    fi

    # Add custom manifest file
    if [[ "$BUILDER" == "amzn-2023" ]] && [[ -n ${AMIGENMANFSTAL2023:-} ]]
    then
        # Use custom manifest env for Amazon Linux 2023
        OSPACKAGESTRING+="-M ${AMIGENMANFSTAL2023} "
    elif [[ -n ${AMIGENMANFST:-} ]]
    then
        OSPACKAGESTRING+="-M ${AMIGENMANFST} "
    else
        err_exit "Installing no custom manifest" NONE
    fi

    # Add custom pkg group
    if [[ -z ${AMIGENPKGGRP:-} ]]
    then
        err_exit "Installing no custom package group" NONE
    else
        OSPACKAGESTRING+="-g ${AMIGENPKGGRP} "
    fi

    # Add extra rpms
    if [[ -z ${EXTRARPMS:-} ]]
    then
        err_exit "Installing no extra rpms" NONE
    else
        OSPACKAGESTRING+="-e ${EXTRARPMS} "
    fi

    # Customization for Oracle Linux
    if [[ $BUILDER == "ol-9" ]]
    then
        # Exclude Unbreakable Enterprise Kernel
        OSPACKAGESTRING+="-x kernel-uek,redhat*,*rhn*,*spacewalk*,*ulninfo* "

        # DNF hack
        OSPACKAGESTRING+="--setup-dnf ociregion=,ocidomain=oracle.com "
    fi

    # Use cross-distro mode to skip RHUI package auto-detection (for air-gapped builds)
    if [[ ${AMIGENCROSSDISTRO} == "true" ]]
    then
        OSPACKAGESTRING+="-X "
        echo "DEBUG: Cross-distro mode ENABLED (-X flag added)" >&2
    else
        echo "DEBUG: Cross-distro mode DISABLED (AMIGENCROSSDISTRO=${AMIGENCROSSDISTRO})" >&2
    fi

    # Debug: Show the full command string
    echo "DEBUG: Full OSpackages command: ${OSPACKAGESTRING}" >&2

    # Return command-string for OS-script
    echo "${OSPACKAGESTRING}"
}

function PostBuildString {
    local POSTBUILDCMD

    POSTBUILDCMD="PostBuild.sh "

    # Set the filesystem-type to use for OS filesystems
    if [[ ${AMIGENFSTYPE} == "xfs" ]]
    then
        err_exit "Using default fstype [xfs] for boot filesysems" NONE
    fi
    POSTBUILDCMD+="-f ${AMIGENFSTYPE} "

    # Set location for chroot-env
    if [[ ${AMIGENCHROOT} == "/mnt/ec2-root" ]]
    then
        err_exit "Using default chroot-env location [${AMIGENCHROOT}]" NONE
    else
        POSTBUILDCMD+="-m ${AMIGENCHROOT} "
    fi

    # Set AMI starting time-zone
    if [[ ${AMIGENTIMEZONE} == "UTC" ]]
    then
        err_exit "Using default AMI timezone [${AMIGENCHROOT}]" NONE
    else
        POSTBUILDCMD+="-z ${AMIGENTIMEZONE} "
    fi

    # Set image GRUB_TIMEOUT value
    POSTBUILDCMD+="--grub-timeout ${GRUBTMOUT}"

    # Return command-string for OS-script
    echo "${POSTBUILDCMD}"
}

function PrepBuildDevice {
    local -a DISKS
    local    ROOT_DEV
    local    ROOT_DISK

    # Select the disk to use for the build
    err_exit "Detecting the root device..." NONE
    ROOT_DEV="$( grep ' / ' /proc/mounts | cut -d " " -f 1 )"

    # Use alternate method to find ROOT_DEV (mostly for Azure)
    if [[ ${ROOT_DEV} == "none" ]]
    then
      ROOT_DEV="$(
        blkid | grep "$(
          awk '/\s\s*\/\s\s*/{ print $1 }' /etc/fstab | cut -d '=' -f 2
        )" | sed -e 's/:.*$//'
      )"
    fi

    # Check if root-dev type is supported
    if [[ ${ROOT_DEV} == /dev/nvme* ]]
    then
      ROOT_DISK="${ROOT_DEV//p*/}"
      mapfile -t DISKS < <( echo /dev/nvme*n1 )
    elif [[ ${ROOT_DEV} == /dev/sd* ]]
    then
      ROOT_DISK="${ROOT_DEV%?}"
      mapfile -t DISKS < <( echo /dev/sd[a-z] )
    else
      err_exit "ERROR: This script supports sd or nvme device naming, only. Could not determine root disk from device name: ${ROOT_DEV}"
    fi

    if [[ "$USEROOTDEVICE" = "true" ]]
    then
      AMIGENBUILDDEV="${ROOT_DISK}"
    elif [[ ${#DISKS[@]} -gt 2 ]]
    then
      err_exit "ERROR: This script supports at most 2 attached disks. Detected ${#DISKS[*]} disks"
    else
      AMIGENBUILDDEV="$(echo "${DISKS[@]/$ROOT_DISK}" | tr -d '[:space:]')"
    fi
    err_exit "Using ${AMIGENBUILDDEV} as the build device." NONE

    # Make sure the disk has a GPT label
    err_exit "Checking ${AMIGENBUILDDEV} for a GPT label..." NONE
    if ! blkid "$AMIGENBUILDDEV"
    then
        err_exit "No label detected. Creating GPT label on ${AMIGENBUILDDEV}..." NONE
        parted -s "$AMIGENBUILDDEV" -- mklabel gpt
        blkid "$AMIGENBUILDDEV"
        err_exit "Created empty GPT configuration on ${AMIGENBUILDDEV}" NONE
    else
        err_exit "GPT label detected on ${AMIGENBUILDDEV}" NONE
    fi
}

##########################
## Main program section ##
##########################

set -x
set -e
set -o pipefail

# Ensure build-tools directory exists
if [[ ! -d ${ELBUILD} ]]
then
    err_exit "Creating build-tools directory [${ELBUILD}]..." NONE
    install -dDm 000755 "${ELBUILD}" || \
        err_exit "Failed creating build-tools directory"
fi

# Pull build-tools from git clone-source or copy from local vendor
if [[ "${AMIGENSOURCE}" == file://* ]]; then
    AMIGEN_LOCAL_PATH="${AMIGENSOURCE#file://}"
    err_exit "Copying build-tools from local source [${AMIGEN_LOCAL_PATH}]..." NONE
    cp -r "${AMIGEN_LOCAL_PATH}/." "${ELBUILD}" || \
        err_exit "Failed copying build-tools from local source"
else
    git clone --branch "${AMIGENBRANCH}" "${AMIGENSOURCE}" "${ELBUILD}"
fi

# Patch OSpackages.sh to support unsigned repo RPMs (air-gapped environments)
if [[ "${AMIGENNOSIGNATURE}" == "true" ]]; then
    err_exit "Patching OSpackages.sh for unsigned RPM support..." NONE
    sed -i 's/rpm --force --root "${CHROOTMNT}" -ivh --nodeps --nopre \/tmp\/\*\.rpm/rpm --force --root "${CHROOTMNT}" -ivh --nodeps --nopre --nosignature \/tmp\/*.rpm/' "${ELBUILD}/OSpackages.sh" || \
        err_exit "Failed patching OSpackages.sh"
fi

# Execute build-tools
BuildChroot
