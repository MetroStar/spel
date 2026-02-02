#!/bin/bash
# Do not use `set -e`, as we handle the errexit in the script
set -u -o pipefail

# Default PUBLIC to false - AMIs are private by default
PUBLIC="${PUBLIC:-false}"

# Verify AWS credentials are available (via environment variables)
# AWS SDK automatically uses AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    echo "ERROR: AWS credentials must be provided via environment variables"
    echo "  Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    echo "  Optional: AWS_SESSION_TOKEN (for OIDC/STS credentials)"
    exit 1
fi

# Determine AWS region (default based on partition detection)
if [[ -z "${AWS_DEFAULT_REGION:-}" ]] && [[ -z "${AWS_REGION:-}" ]]; then
    echo "WARNING: No AWS region set, defaulting to us-east-1"
    export AWS_DEFAULT_REGION="us-east-1"
fi

# Function to check and manage AMI quotas in the current region
# Uses default credentials from environment variables
# Makes old AMIs private to maintain headroom for concurrent builds
check_and_manage_ami_quotas() {
    local REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}"
    local HEADROOM=3  # Keep at least 3 slots available for concurrent builds
    
    echo "=== AMI Quota Management ==="
    echo "Region: $REGION"

    # Get the service quota limit for public AMIs
    QUOTA_LIMIT=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-0E3CBAB9 \
        --region "$REGION" \
        --query 'Quota.Value' \
        --output text 2>/dev/null) || {
        echo "WARNING: Could not retrieve quota limit (may lack servicequotas permissions)"
        echo "==========================="
        return 0
    }

    # Convert QUOTA_LIMIT to an integer
    QUOTA_LIMIT=${QUOTA_LIMIT%.*}

    # Get the current public AMIs with their creation dates
    PUBLIC_AMI_INFO=$(aws ec2 describe-images \
        --owners self \
        --filters Name=is-public,Values=true \
        --region "$REGION" \
        --query 'Images[*].[ImageId,CreationDate,Name]' \
        --output text 2>/dev/null) || {
        echo "WARNING: Could not list public AMIs"
        echo "==========================="
        return 0
    }
    
    CURRENT_PUBLIC_AMIS=$(echo "$PUBLIC_AMI_INFO" | grep -c . || echo "0")

    # Calculate available slots
    AVAILABLE_SLOTS=$((QUOTA_LIMIT - CURRENT_PUBLIC_AMIS))

    echo "Quota limit: $QUOTA_LIMIT"
    echo "Current public AMIs: $CURRENT_PUBLIC_AMIS"
    echo "Available slots: $AVAILABLE_SLOTS"
    echo "Required headroom: $HEADROOM"

    # If we don't have enough headroom, make old AMIs private
    if [ "$AVAILABLE_SLOTS" -lt "$HEADROOM" ]; then
        # Calculate how many AMIs to make private to restore headroom
        AMIS_TO_MAKE_PRIVATE=$((HEADROOM - AVAILABLE_SLOTS + 2))  # +2 extra buffer
        
        echo ""
        echo "Insufficient headroom. Making $AMIS_TO_MAKE_PRIVATE oldest AMIs private..."
        
        OLDEST_AMIS=$(aws ec2 describe-images \
            --owners self \
            --filters Name=is-public,Values=true \
            --region "$REGION" \
            --query "Images | sort_by(@, &CreationDate)[:${AMIS_TO_MAKE_PRIVATE}].ImageId" \
            --output text 2>/dev/null)
        
        for AMI_ID in $OLDEST_AMIS; do
            echo "  Making AMI $AMI_ID private..."
            if aws ec2 modify-image-attribute \
                --image-id "$AMI_ID" \
                --launch-permission '{"Remove": [{"Group":"all"}]}' \
                --region "$REGION" 2>/dev/null; then
                echo "  ✓ $AMI_ID is now private"
            else
                echo "  ⚠ Failed to modify $AMI_ID"
            fi
        done
        
        # Re-check available slots
        NEW_PUBLIC_COUNT=$(aws ec2 describe-images \
            --owners self \
            --filters Name=is-public,Values=true \
            --region "$REGION" \
            --query 'Images[*].ImageId' \
            --output text 2>/dev/null | wc -w)
        echo ""
        echo "After cleanup: $NEW_PUBLIC_COUNT public AMIs, $((QUOTA_LIMIT - NEW_PUBLIC_COUNT)) slots available"
    else
        echo "✓ Sufficient headroom available"
    fi
    
    echo "==========================="
}

if [ $PUBLIC = "true" ]; then
  # Check and manage AMI quotas before starting the build
  check_and_manage_ami_quotas
fi

echo "==========STARTING BUILD=========="

ANSIBLE_LOCKDOWNS=""

if [[ -n "$SPEL_BUILDERS" ]]; then
    FAILED_BUILDS=()
    SUCCESS_BUILDS=()

    packer init spel/minimal-linux.pkr.hcl

    packer validate \
        -only "${SPEL_BUILDERS:?}" \
        -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
        -var "spel_version=${SPEL_VERSION:?}" \
        spel/minimal-linux.pkr.hcl

    build_packer_templates() {
        packer build \
            -only "${SPEL_BUILDERS:?}" \
            -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
            -var "spel_version=${SPEL_VERSION:?}" \
            -var "aws_ami_groups=[]" \
            spel/minimal-linux.pkr.hcl

        BUILDEXIT=$?

        FAILED_BUILDS=()

        for BUILDER in ${SPEL_BUILDERS//,/ }; do
            BUILD_NAME="${BUILDER//*./}"
            AMI_NAME="${SPEL_IDENTIFIER}-${BUILD_NAME}-${SPEL_VERSION}.x86_64-gp3"
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
    }

    build_packer_templates

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

packer init spel/hardened-linux.pkr.hcl

packer validate \
    -only "${ANSIBLE_LOCKDOWNS}" \
    -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
    -var "spel_version=${SPEL_VERSION:?}" \
    spel/hardened-linux.pkr.hcl

packer build \
    -only "${ANSIBLE_LOCKDOWNS}" \
    -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
    -var "spel_version=${SPEL_VERSION:?}" \
    spel/hardened-linux.pkr.hcl

LOCKEXIT=$?

export SUCCESS_BUILDS=$(IFS=, ; echo "${SUCCESS_LOCKDOWNS[*]}")

if [[ $LOCKEXIT -ne 0 ]]; then
    FAILED_LOCKERS=$(IFS=, ; echo "${FAILED_LOCKDOWNS[*]}")
    echo "ERROR: Failed lockdowns: ${FAILED_LOCKERS}"
    echo "ERROR: Lockdown build failed. Scroll up past the test to see the packer error and review the build logs."
    exit $LOCKEXIT
fi
