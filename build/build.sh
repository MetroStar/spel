#!/bin/bash
# Do not use `set -e`, as we handle the errexit in the script
set -u -o pipefail

# Ensure required environment variables are set
: "${AWS_COMMERCIAL_ACCESS_KEY_ID:?}"
: "${AWS_COMMERCIAL_SECRET_ACCESS_KEY:?}"
: "${AWS_GOVCLOUD_ACCESS_KEY_ID:?}"
: "${AWS_GOVCLOUD_SECRET_ACCESS_KEY:?}"

# Create AWS CLI configuration files
mkdir -p ~/.aws

cat <<EOL > ~/.aws/credentials
[commercial]
aws_access_key_id = ${AWS_COMMERCIAL_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_COMMERCIAL_SECRET_ACCESS_KEY}

[govcloud]
aws_access_key_id = ${AWS_GOVCLOUD_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_GOVCLOUD_SECRET_ACCESS_KEY}
EOL

cat <<EOL > ~/.aws/config
[profile commercial]
region = us-east-1

[profile govcloud]
region = us-gov-east-1
EOL

# Function to check and manage AMI quotas
check_and_manage_ami_quotas() {
    REGIONS=("us-east-1" "us-east-2" "us-west-1" "us-west-2")

    for REGION in "${REGIONS[@]}"; do
        echo "Checking AMI quotas in region $REGION"

        # Get the service quota limit for public AMIs
        QUOTA_LIMIT=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-0E3CBAB9 --region "$REGION" --query 'Quota.Value' --output text --profile commercial)

        # Convert QUOTA_LIMIT to an integer
        QUOTA_LIMIT=${QUOTA_LIMIT%.*}

        # Get the current number of public AMIs
        CURRENT_PUBLIC_AMIS=$(aws ec2 describe-images --owners self --filters Name=is-public,Values=true --region "$REGION" --query 'Images[*].ImageId' --output text --profile commercial | wc -w)

        # Calculate the difference
        DIFFERENCE=$((QUOTA_LIMIT - CURRENT_PUBLIC_AMIS))

        echo "Quota limit: $QUOTA_LIMIT, Current public AMIs: $CURRENT_PUBLIC_AMIS, Difference: $DIFFERENCE"

        # If the difference is less than 5, make the 5 oldest AMIs private
        if [ "$DIFFERENCE" -lt 5 ]; then
            echo "Making the 5 oldest AMIs private in region $REGION"
            OLDEST_AMIS=$(aws ec2 describe-images --owners self --filters Name=is-public,Values=true --region "$REGION" --query 'Images | sort_by(@, &CreationDate)[:5].ImageId' --output text  --profile commercial)
            for AMI_ID in $OLDEST_AMIS; do
                echo "Making AMI $AMI_ID private"
                aws ec2 modify-image-attribute --image-id "$AMI_ID" --launch-permission "{\"Remove\": [{\"Group\":\"all\"}]}" --region "$REGION" --profile commercial
            done
        fi
    done

    REGIONS=("us-gov-east-1" "us-gov-west-1")

    for REGION in "${REGIONS[@]}"; do
        echo "Checking AMI quotas in region $REGION"

        # Get the service quota limit for public AMIs
        QUOTA_LIMIT=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-0E3CBAB9 --region "$REGION" --query 'Quota.Value' --output text --profile govcloud)

        # Convert QUOTA_LIMIT to an integer
        QUOTA_LIMIT=${QUOTA_LIMIT%.*}

        # Get the current number of public AMIs
        CURRENT_PUBLIC_AMIS=$(aws ec2 describe-images --owners self --filters Name=is-public,Values=true --region "$REGION" --query 'Images[*].ImageId' --output text --profile govcloud | wc -w)

        # Calculate the difference
        DIFFERENCE=$((QUOTA_LIMIT - CURRENT_PUBLIC_AMIS))

        echo "Quota limit: $QUOTA_LIMIT, Current public AMIs: $CURRENT_PUBLIC_AMIS, Difference: $DIFFERENCE"

        # If the difference is less than 5, make the 5 oldest AMIs private
        if [ "$DIFFERENCE" -lt 5 ]; then
            echo "Making the 5 oldest AMIs private in region $REGION"
            OLDEST_AMIS=$(aws ec2 describe-images --owners self --filters Name=is-public,Values=true --region "$REGION" --query 'Images | sort_by(@, &CreationDate)[:5].ImageId' --output text --profile govcloud)
            for AMI_ID in $OLDEST_AMIS; do
                echo "Making AMI $AMI_ID private"
                aws ec2 modify-image-attribute --image-id "$AMI_ID" --launch-permission "{\"Remove\": [{\"Group\":\"all\"}]}" --region "$REGION" --profile govcloud
            done
        fi
    done
}

if [ $PUBLIC = "true" ]; then
  # Check and manage AMI quotas before starting the build
  check_and_manage_ami_quotas
fi

echo "==========STARTING BUILD=========="
echo "Building packer template, spel/minimal-linux.pkr.hcl"

FAILED_BUILDS=()
SUCCESS_BUILDS=()

build_packer_templates() {
    packer build \
        -only "${SPEL_BUILDERS:?}" \
        -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
        -var "spel_version=${SPEL_VERSION:?}" \
        spel/minimal-linux.pkr.hcl

    BUILDEXIT=$?

    FAILED_BUILDS=()

    for BUILDER in ${SPEL_BUILDERS//,/ }; do
        BUILD_NAME="${BUILDER//*./}"
        AMI_NAME="${SPEL_IDENTIFIER}-${BUILD_NAME}-${SPEL_VERSION}.x86_64-gp3"
        BUILDER_ENV="${BUILDER//[.-]/_}"
        BUILDER_AMI=$(aws ec2 describe-images --filters Name=name,Values="$AMI_NAME" Name=creation-date,Values=$(date +%Y-%m-%dT*) --owners self --query 'Images[0].ImageId' --out text --profile commercial)
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

# Retry failed builds until there are no more failed builds
while [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; do
    echo "Retrying failed builds: ${FAILED_BUILDS[*]}"
    SPEL_BUILDERS=$(IFS=, ; echo "${FAILED_BUILDS[*]}")
    build_packer_templates
done

SUCCESS_BUILDERS=$(IFS=, ; echo "${SUCCESS_BUILDS[*]}")
echo "Successful builds being tested: ${SUCCESS_BUILDERS}"

FAILED_TEST_BUILDS=()

packer build \
    -only "${SUCCESS_BUILDERS//amazon-ebssurrogate./amazon-ebs.}" \
    -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
    -var "spel_version=${SPEL_VERSION:?}" \
    tests/minimal-linux.pkr.hcl | tee packer_test_output.log

TESTEXIT=$?

echo "SUCCESS_BUILDS=${SUCCESS_BUILDS[*]}" >> $GITHUB_ENV

if [[ $BUILDEXIT -ne 0 ]]; then
    FAILED_BUILDERS=$(IFS=, ; echo "${FAILED_BUILDS[*]}")
    echo "ERROR: Failed builds: ${FAILED_BUILDERS}"
    echo "ERROR: Build failed. Scroll up past the test to see the packer error and review the build logs."
    exit $BUILDEXIT
fi

if [[ $TESTEXIT -ne 0 ]]; then
    FAILED_TEST_BUILDS+=($(grep -oP '(?<=Build ).*(?= errored)' packer_test_output.log | sed "s/'//g" | paste -sd ','))
fi
