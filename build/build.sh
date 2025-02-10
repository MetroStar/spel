#!/bin/bash
# Do not use `set -e`, as we handle the errexit in the script
set -u -o pipefail

# Ensure required environment variables are set
: "${YOUR_COMMERCIAL_ACCESS_KEY_ID:?}"
: "${YOUR_COMMERCIAL_SECRET_ACCESS_KEY:?}"
: "${YOUR_GOVCLOUD_ACCESS_KEY_ID:?}"
: "${YOUR_GOVCLOUD_SECRET_ACCESS_KEY:?}"

# Create AWS CLI configuration files
mkdir -p ~/.aws

cat <<EOL > ~/.aws/credentials
[commercial]
aws_access_key_id = ${YOUR_COMMERCIAL_ACCESS_KEY_ID}
aws_secret_access_key = ${YOUR_COMMERCIAL_SECRET_ACCESS_KEY}

[govcloud]
aws_access_key_id = ${YOUR_GOVCLOUD_ACCESS_KEY_ID}
aws_secret_access_key = ${YOUR_GOVCLOUD_SECRET_ACCESS_KEY}
EOL

cat <<EOL > ~/.aws/config
[profile commercial]
region = us-east-1

[profile govcloud]
region = us-gov-west-1
EOL

# Set default region if not already set
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)}

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

    # Make AMIs public and copy to other regions
    for BUILDER in "${SUCCESS_BUILDS[@]}"; do
        BUILD_NAME="${BUILDER//*./}"
        AMI_NAME="${SPEL_IDENTIFIER}-${BUILD_NAME}-${SPEL_VERSION}.x86_64-gp3"
        BUILDER_ENV="${BUILDER//[.-]/_}"
        BUILDER_AMI=$(aws ec2 describe-images --filters Name=name,Values="$AMI_NAME" --query 'Images[0].ImageId' --out text --profile commercial)

        if [[ "$BUILDER_AMI" != "None" ]]; then
            echo "Making AMI $BUILDER_AMI public"
            aws ec2 modify-image-attribute --image-id "$BUILDER_AMI" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile commercial

            # Copy AMI to other regions in the US
            REGIONS=("us-east-1" "us-east-2" "us-west-1" "us-west-2")
            for REGION in "${REGIONS[@]}"; do
                if [[ "$REGION" != "$AWS_DEFAULT_REGION" ]]; then
                    echo "Copying AMI $BUILDER_AMI to region $REGION"
                    COPY_AMI_ID=$(aws ec2 copy-image --source-image-id "$BUILDER_AMI" --source-region "$AWS_DEFAULT_REGION" --region "$REGION" --name "$AMI_NAME" --query 'ImageId' --output text --profile commercial)

                    # Wait for the copied AMI to become available
                    aws ec2 wait image-available --region "$REGION" --image-ids "$COPY_AMI_ID" --profile commercial

                    # Make the copied AMI public
                    echo "Making copied AMI $COPY_AMI_ID in region $REGION public"
                    aws ec2 modify-image-attribute --region "$REGION" --image-id "$COPY_AMI_ID" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile commercial
                fi
            done

            # Copy AMI to GovCloud partition using the script from the repository
            echo "Copying AMI $BUILDER_AMI to GovCloud partition"
            ./ami-cp.sh import_ami $BUILDER_AMI $AMI_NAME
        fi
    done
fi

TESTEXIT=$?

if [[ $BUILDEXIT -ne 0 ]]; then
    FAILED_BUILDERS=$(IFS=, ; echo "${FAILED_BUILDS[*]}")
    echo "ERROR: Failed builds: ${FAILED_BUILDS}"
    echo "ERROR: Build failed. Scroll up past the test to see the packer error and review the build logs."
    exit $BUILDEXIT
fi

if [[ $TESTEXIT -ne 0 ]]; then
    echo "ERROR: Test failed. Review the test logs for the error."
    exit $TESTEXIT
fi
echo "==========BUILD SUCCESSFUL=========="
