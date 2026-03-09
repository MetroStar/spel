#!/bin/bash
set -eu -o pipefail

# internal vars
CLONE_DIR=/tmp/granite

if [[ "${GRANITE_CI:?}" = "true" ]]
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

# download granite
git clone "${GRANITE_REPO_URL:?}" "$CLONE_DIR"
cd "$CLONE_DIR"

if [[ -n "${GRANITE_REPO_COMMIT:-}" ]] ; then
    # decide whether to switch to pull request or a branch
    echo "SOURCE_COMMIT = ${GRANITE_REPO_COMMIT}"
    if [[ "$GRANITE_REPO_COMMIT" =~ ^pr/[0-9]+$ ]]; then
        git fetch origin "pull/${GRANITE_REPO_COMMIT#pr/}/head:${GRANITE_REPO_COMMIT}"
    fi
    git checkout "$GRANITE_REPO_COMMIT"
fi

# install packer
make packer/install

# build vagrant box
mkdir -p "${CLONE_DIR}/.granite/${GRANITE_VERSION:?}/"
export PACKER_LOG=1
export PACKER_LOG_PATH="${CLONE_DIR}/.granite/${GRANITE_VERSION:?}/packer.log"

packer init granite/minimal-linux.pkr.hcl

packer build \
    -var "virtualbox_iso_url_centos9stream=${VIRTUALBOX_ISO_URL_CENTOS9STREAM:?}" \
    -var "virtualbox_vagrantcloud_username=${VAGRANT_CLOUD_USER:?}" \
    -var "granite_identifier=${GRANITE_IDENTIFIER:?}" \
    -var "granite_version=${GRANITE_VERSION:?}" \
    -only "virtualbox-iso.minimal-centos-9stream" \
    -except "${EXCEPT_STEP:-}" \
    granite/minimal-linux.pkr.hcl

# remove subdirectories from the artifact location
find "${CLONE_DIR}/.granite/${GRANITE_VERSION:?}/" -maxdepth 1 -mindepth 1 -type d -print0 | xargs -0 rm -rf

# remove .ova and .box files from artifact location
find "${CLONE_DIR}/.granite/${GRANITE_VERSION:?}/" -type f \( -name '*.box' -o -name '*.ova' \) -print0 | xargs -0 rm -f
