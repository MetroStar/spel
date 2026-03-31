#!/bin/bash
set -eu -o pipefail

# internal vars
CLONE_DIR=/tmp/chimera

if [[ "${CHIMERA_CI:?}" = "true" ]]
then
    # CI build will skip vagrant-cloud post-provisioner
    EXCEPT_STEP="vagrant-cloud"
    export EXCEPT_STEP
fi

if [[ -z "${PACKER_VERSION:-}" ]]
then
    unset PACKER_VERSION
fi

# update PATH
export PATH="${HOME}/bin:${PATH}"

# update machine
/usr/bin/cloud-init status --wait
sudo apt-get update && sudo apt-get install -y \
    jq \
    vagrant \
    virtualbox \
    virtualbox-guest-additions-iso

# download chimera
git clone "${CHIMERA_REPO_URL:?}" "$CLONE_DIR"
cd "$CLONE_DIR"

if [[ -n "${CHIMERA_REPO_COMMIT:-}" ]] ; then
    # decide whether to switch to pull request or a branch
    echo "SOURCE_COMMIT = ${CHIMERA_REPO_COMMIT}"
    if [[ "$CHIMERA_REPO_COMMIT" =~ ^pr/[0-9]+$ ]]; then
        git fetch origin "pull/${CHIMERA_REPO_COMMIT#pr/}/head:${CHIMERA_REPO_COMMIT}"
    fi
    git checkout "$CHIMERA_REPO_COMMIT"
fi

# install packer
make packer/install

# build vagrant box
mkdir -p "${CLONE_DIR}/.chimera/${CHIMERA_VERSION:?}/"
export PACKER_LOG=1
export PACKER_LOG_PATH="${CLONE_DIR}/.chimera/${CHIMERA_VERSION:?}/packer.log"

packer init chimera/minimal.pkr.hcl

packer build \
    -var "virtualbox_iso_url_centos9stream=${VIRTUALBOX_ISO_URL_CENTOS9STREAM:?}" \
    -var "virtualbox_vagrantcloud_username=${VAGRANT_CLOUD_USER:?}" \
    -var "chimera_identifier=${CHIMERA_IDENTIFIER:?}" \
    -var "chimera_version=${CHIMERA_VERSION:?}" \
    -only "virtualbox-iso.minimal-centos-9stream" \
    -except "${EXCEPT_STEP:-}" \
    chimera/minimal.pkr.hcl

# remove subdirectories from the artifact location
find "${CLONE_DIR}/.chimera/${CHIMERA_VERSION:?}/" -maxdepth 1 -mindepth 1 -type d -print0 | xargs -0 rm -rf

# remove .ova and .box files from artifact location
find "${CLONE_DIR}/.chimera/${CHIMERA_VERSION:?}/" -type f \( -name '*.box' -o -name '*.ova' \) -print0 | xargs -0 rm -f
