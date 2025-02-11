#!/bin/bash
# Do not use `set -e`, as we handle the errexit in the script
set -u -o pipefail

# Function to check and manage AMI quotas
check_and_manage_ami_quotas() {
    REGIONS=("us-east-1" "us-east-2" "us-west-1" "us-west-2")

    for REGION in "${REGIONS[@]}"; do
        echo "Checking AMI quotas in region $REGION"

        # Get the service quota limit for public AMIs
        QUOTA_LIMIT=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --region "$REGION" --query 'Quota.Value' --output text)

        # Get the current number of public AMIs
        CURRENT_PUBLIC_AMIS=$(aws ec2 describe-images --owners self --filters Name=is-public,Values=true --region "$REGION" --query 'Images[*].ImageId' --output text | wc -w)

        # Calculate the difference
        DIFFERENCE=$((QUOTA_LIMIT - CURRENT_PUBLIC_AMIS))

        echo "Quota limit: $QUOTA_LIMIT, Current public AMIs: $CURRENT_PUBLIC_AMIS, Difference: $DIFFERENCE"

        # If the difference is less than 5, make the 5 oldest AMIs private
        if [ "$DIFFERENCE" -lt 5 ]; then
            echo "Making the 5 oldest AMIs private in region $REGION"
            OLDEST_AMIS=$(aws ec2 describe-images --owners self --filters Name=is-public,Values=true --region "$REGION" --query 'Images | sort_by(@, &CreationDate)[:5].ImageId' --output text)
            for AMI_ID in $OLDEST_AMIS; do
                echo "Making AMI $AMI_ID private"
                aws ec2 modify-image-attribute --image-id "$AMI_ID" --launch-permission "{\"Remove\": [{\"Group\":\"all\"}]}" --region "$REGION"
            done
        fi
    done
}

# Check and manage AMI quotas before starting the build
check_and_manage_ami_quotas

echo "==========STARTING BUILD=========="
echo "Building packer template, spel/minimal-linux.pkr.hcl"

packer build \
    -only "${SPEL_BUILDERS:?}" \
    -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
    -var "spel_version=${SPEL_VERSION:?}" \
    spel/minimal-linux.pkr.hcl

BUILDEXIT=$?

FAILED_BUILDS=()
SUCCESS_BUILDS=()

for BUILDER in ${SPEL_BUILDERS//,/ }; do
    BUILD_NAME="${BUILDER//*./}"
    AMI_NAME="${SPEL_IDENTIFIER}-${BUILD_NAME}-${SPEL_VERSION}.x86_64-gp3"
    BUILDER_ENV="${BUILDER//[.-]/_}"
    BUILDER_AMI=$(aws ec2 describe-images --filters Name=name,Values="$AMI_NAME" --query 'Images[0].ImageId' --out text)
    if [[ "$BUILDER_AMI" == "None" ]]
    then
        FAILED_BUILDS+=("$BUILDER")
    else
        SUCCESS_BUILDS+=("$BUILDER")
        export "$BUILDER_ENV"="$BUILDER_AMI"
    fi
done

if [[ -n "${SUCCESS_BUILDS:-}" ]]
then
    SUCCESS_BUILDERS=$(IFS=, ; echo "${SUCCESS_BUILDS[*]}")
    echo "Successful builds being tested: ${SUCCESS_BUILDERS}"
    packer build \
        -only "${SUCCESS_BUILDERS//amazon-ebssurrogate./amazon-ebs.}" \
        -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
        -var "spel_version=${SPEL_VERSION:?}" \
        tests/minimal-linux.pkr.hcl
fi

TESTEXIT=$?

if [[ $BUILDEXIT -ne 0 ]]; then
    FAILED_BUILDERS=$(IFS=, ; echo "${FAILED_BUILDS[*]}")
    echo "ERROR: Failed builds: ${FAILED_BUILDERS}"
    echo "ERROR: Build failed. Scroll up past the test to see the packer error and review the build logs."
    exit $BUILDEXIT
fi

if [[ $TESTEXIT -ne 0 ]]; then
    echo "ERROR: Test failed. Review the test logs for the error."
    exit $TESTEXIT
fi
