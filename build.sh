#!/bin/bash
# Do not use `set -e`, as we handle the errexit in the script
set -u -o pipefail

echo "==========STARTING BUILD=========="

CRUCIBLE_BUILDERS="${CRUCIBLE_BUILDERS:-}"
WINDOWS_BUILDERS="${WINDOWS_BUILDERS:-}"
ANSIBLE_LOCKDOWNS=""
MINIMAL_AMIS=()

if [[ -n "$CRUCIBLE_BUILDERS" ]]; then
    FAILED_BUILDS=()
    SUCCESS_BUILDS=()

    packer init crucible/minimal.pkr.hcl

    packer validate \
        -only "${CRUCIBLE_BUILDERS}" \
        -var "crucible_identifier=${CRUCIBLE_IDENTIFIER:?}" \
        -var "crucible_version=${CRUCIBLE_VERSION:?}" \
        crucible/minimal.pkr.hcl

    packer build \
        -only "${CRUCIBLE_BUILDERS}" \
        -var "crucible_identifier=${CRUCIBLE_IDENTIFIER:?}" \
        -var "crucible_version=${CRUCIBLE_VERSION:?}" \
        -var "aws_ami_groups=[]" \
        crucible/minimal.pkr.hcl

    BUILDEXIT=$?

    for BUILDER in ${CRUCIBLE_BUILDERS//,/ }; do
        BUILD_NAME="${BUILDER//*./}"
        AMI_NAME="${CRUCIBLE_IDENTIFIER}-${BUILD_NAME}-${CRUCIBLE_VERSION}.x86_64-gp3"
        BUILDER_AMI=$(aws ec2 describe-images \
            --filters Name=name,Values="$AMI_NAME" \
            --owners self \
            --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
            --output text)
        if [[ "$BUILDER_AMI" == "None" || -z "$BUILDER_AMI" ]]; then
            FAILED_BUILDS+=("$BUILDER")
        else
            SUCCESS_BUILDS+=("$BUILDER")
            MINIMAL_AMIS+=("$BUILDER_AMI")
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

if [[ -z "$ANSIBLE_LOCKDOWNS" ]]; then
    echo "ERROR: No builders specified. Set CRUCIBLE_BUILDERS and/or WINDOWS_BUILDERS."
    exit 1
fi

packer init crucible/hardened.pkr.hcl

packer validate \
    -only "${ANSIBLE_LOCKDOWNS}" \
    -var "crucible_identifier=${CRUCIBLE_IDENTIFIER:?}" \
    -var "crucible_version=${CRUCIBLE_VERSION:?}" \
    crucible/hardened.pkr.hcl

packer build \
    -only "${ANSIBLE_LOCKDOWNS}" \
    -var "crucible_identifier=${CRUCIBLE_IDENTIFIER:?}" \
    -var "crucible_version=${CRUCIBLE_VERSION:?}" \
    crucible/hardened.pkr.hcl

LOCKEXIT=$?

if [[ $LOCKEXIT -ne 0 ]]; then
    echo "ERROR: Lockdown build failed. Scroll up past the test to see the packer error and review the build logs."
    exit $LOCKEXIT
fi

# Clean up intermediate minimal AMIs (only after successful hardened build)
if [[ ${#MINIMAL_AMIS[@]} -gt 0 ]]; then
    echo "==========CLEANING UP MINIMAL AMIs=========="
    for AMI_ID in "${MINIMAL_AMIS[@]}"; do
        echo "Deregistering minimal AMI: ${AMI_ID}"
        SNAPSHOTS=$(aws ec2 describe-images --image-ids "$AMI_ID" --query 'Images[0].BlockDeviceMappings[*].Ebs.SnapshotId' --output text 2>/dev/null || true)
        aws ec2 deregister-image --image-id "$AMI_ID" 2>/dev/null || true
        for SNAP_ID in $SNAPSHOTS; do
            [[ "$SNAP_ID" == "None" ]] && continue
            echo "  Deleting snapshot: ${SNAP_ID}"
            aws ec2 delete-snapshot --snapshot-id "$SNAP_ID" 2>/dev/null || true
        done
    done
    echo "==========CLEANUP COMPLETE=========="
fi

# Print summary of hardened AMIs
echo "==========BUILD SUMMARY=========="
for BUILDER in ${ANSIBLE_LOCKDOWNS//,/ }; do
    BUILD_NAME="${BUILDER//*./}"
    AMI_NAME="${CRUCIBLE_IDENTIFIER}-${BUILD_NAME}-${CRUCIBLE_VERSION}.x86_64-gp3"
    AMI_ID=$(aws ec2 describe-images \
        --filters Name=name,Values="$AMI_NAME" \
        --owners self \
        --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
        --output text 2>/dev/null || echo "UNKNOWN")
    echo "  ${AMI_NAME}: ${AMI_ID}"
done
echo "================================="
