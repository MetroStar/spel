#!/bin/bash
# Do not use `set -e`, as we handle the errexit in the script
set -u -o pipefail

echo "==========STARTING BUILD=========="

ANSIBLE_LOCKDOWNS=""

if [[ -n "$CHIMERA_BUILDERS" ]]; then
    FAILED_BUILDS=()
    SUCCESS_BUILDS=()

    packer init chimera/minimal.pkr.hcl

    packer validate \
        -only "${CHIMERA_BUILDERS:?}" \
        -var "chimera_identifier=${CHIMERA_IDENTIFIER:?}" \
        -var "chimera_version=${CHIMERA_VERSION:?}" \
        chimera/minimal.pkr.hcl

    packer build \
        -only "${CHIMERA_BUILDERS:?}" \
        -var "chimera_identifier=${CHIMERA_IDENTIFIER:?}" \
        -var "chimera_version=${CHIMERA_VERSION:?}" \
        -var "aws_ami_groups=[]" \
        chimera/minimal.pkr.hcl

    BUILDEXIT=$?

    for BUILDER in ${CHIMERA_BUILDERS//,/ }; do
        BUILD_NAME="${BUILDER//*./}"
        AMI_NAME="${CHIMERA_IDENTIFIER}-${BUILD_NAME}-${CHIMERA_VERSION}.x86_64-gp3"
        BUILDER_ENV="${BUILDER//[.-]/_}"
        BUILDER_AMI=$(aws ec2 describe-images --filters Name=name,Values="$AMI_NAME" Name=creation-date,Values=$(date +%Y-%m-%dT*) --owners self --query 'Images[0].ImageId' --out text)
        if [[ "$BUILDER_AMI" == "None" ]]
        then
            FAILED_BUILDS+=("$BUILDER")
        else
            SUCCESS_BUILDS+=("$BUILDER")
            export "$BUILDER_ENV"="$BUILDER_AMI"
        fi
    done

    SUCCESS_BUILDERS=$(IFS=, ; echo "${SUCCESS_BUILDS[*]}")
    ANSIBLE_LOCKDOWNS=${SUCCESS_BUILDERS//amazon-ebssurrogate.minimal/amazon-ebs.hardened}

    if [[ $BUILDEXIT -ne 0 ]]; then
        FAILED_BUILDERS=$(IFS=, ; echo "${FAILED_BUILDS[*]}")
        echo "ERROR: Failed builds: ${FAILED_BUILDERS}"
        echo "ERROR: Minimal build failed. Scroll up past the test to see the packer error and review the build logs."
        exit $BUILDEXIT
    fi
fi

if [[ -n "$WINDOWS_BUILDERS" ]]; then
    if [[ -n "$ANSIBLE_LOCKDOWNS" ]]; then
        ANSIBLE_LOCKDOWNS="${ANSIBLE_LOCKDOWNS},${WINDOWS_BUILDERS}"
    else
        ANSIBLE_LOCKDOWNS="${WINDOWS_BUILDERS}"
    fi
fi

packer init chimera/hardened.pkr.hcl

packer validate \
    -only "${ANSIBLE_LOCKDOWNS}" \
    -var "chimera_identifier=${CHIMERA_IDENTIFIER:?}" \
    -var "chimera_version=${CHIMERA_VERSION:?}" \
    chimera/hardened.pkr.hcl

packer build \
    -only "${ANSIBLE_LOCKDOWNS}" \
    -var "chimera_identifier=${CHIMERA_IDENTIFIER:?}" \
    -var "chimera_version=${CHIMERA_VERSION:?}" \
    chimera/hardened.pkr.hcl

LOCKEXIT=$?

if [[ $LOCKEXIT -ne 0 ]]; then
    echo "ERROR: Lockdown build failed. Scroll up past the test to see the packer error and review the build logs."
    exit $LOCKEXIT
fi
