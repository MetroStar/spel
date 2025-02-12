#!/bin/bash
# Do not use `set -e`, as we handle the errexit in the script
set -u -o pipefail

# Ensure required environment variables are set
: "${COMMERCIAL_ACCESS_KEY_ID:?}"
: "${COMMERCIAL_SECRET_ACCESS_KEY:?}"
: "${GOVCLOUD_ACCESS_KEY_ID:?}"
: "${GOVCLOUD_SECRET_ACCESS_KEY:?}"

# Set default region if not already set
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)}

# Create AWS CLI configuration files
mkdir -p ~/.aws

cat <<EOL > ~/.aws/credentials
[commercial]
aws_access_key_id = ${COMMERCIAL_ACCESS_KEY_ID}
aws_secret_access_key = ${COMMERCIAL_SECRET_ACCESS_KEY}

[govcloud]
aws_access_key_id = ${GOVCLOUD_ACCESS_KEY_ID}
aws_secret_access_key = ${GOVCLOUD_SECRET_ACCESS_KEY}
EOL

cat <<EOL > ~/.aws/config
[profile commercial]
region = ${AWS_DEFAULT_REGION}

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
    BUILDER_AMI=$(aws ec2 describe-images --filters Name=name,Values="$AMI_NAME" --query 'Images[0].ImageId' --out text --profile commercial)
    if [[ "$BUILDER_AMI" == "None" ]]
    then
        FAILED_BUILDS+=("$BUILDER")
    else
        SUCCESS_BUILDS+=("$BUILDER")
        export "$BUILDER_ENV"="$BUILDER_AMI"
    fi
done

if [[ -n "${SUCCESS_BUILDS:-}" ]]; then
    SUCCESS_BUILDERS=$(IFS=, ; echo "${SUCCESS_BUILDS[*]}")
    echo "Successful builds being tested: ${SUCCESS_BUILDERS}"
    packer build \
        -only "${SUCCESS_BUILDERS//amazon-ebssurrogate./amazon-ebs.}" \
        -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
        -var "spel_version=${SPEL_VERSION:?}" \
        tests/minimal-linux.pkr.hcl

    # Generate unique S3 bucket names
    TIMESTAMP=$(date +%s)
    RANDOM_STRING=$(openssl rand -hex 6)
    S3_BUCKET_COMMERCIAL="commercial-bucket-${TIMESTAMP}-${RANDOM_STRING}"
    S3_BUCKET_GOV="govcloud-bucket-${TIMESTAMP}-${RANDOM_STRING}"

    # Create S3 buckets
    aws s3api create-bucket --bucket "${S3_BUCKET_COMMERCIAL}" --region "${AWS_DEFAULT_REGION}" --create-bucket-configuration LocationConstraint="${AWS_DEFAULT_REGION}" --profile commercial
    aws s3api create-bucket --bucket "${S3_BUCKET_GOV}" --region "us-gov-east-1" --create-bucket-configuration LocationConstraint="us-gov-east-1" --profile govcloud

    # Copy AMI to GovCloud partition using the script from the repository
    for BUILDER in "${SUCCESS_BUILDS[@]}"; do
        BUILD_NAME="${BUILDER//*./}"
        AMI_NAME="${SPEL_IDENTIFIER}-${BUILD_NAME}-${SPEL_VERSION}.x86_64-gp3"
        BUILDER_ENV="${BUILDER//[.-]/_}"
        BUILDER_AMI=$(aws ec2 describe-images --filters Name=name,Values="$AMI_NAME" --query 'Images[0].ImageId' --out text --profile commercial)

        if [[ "$BUILDER_AMI" != "None" ]]; then
            echo "Copying AMI $BUILDER_AMI to GovCloud partition"
            ./ami-cp.sh import_ami $BUILDER_AMI $AMI_NAME
        fi
    done

    # Empty and delete S3 buckets
    aws s3 rm "s3://${S3_BUCKET_COMMERCIAL}" --recursive --profile commercial
    aws s3api delete-bucket --bucket "${S3_BUCKET_COMMERCIAL}" --profile commercial

    aws s3 rm "s3://${S3_BUCKET_GOV}" --recursive --profile govcloud
    aws s3api delete-bucket --bucket "${S3_BUCKET_GOV}" --profile govcloud
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
