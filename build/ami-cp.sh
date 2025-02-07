#!/bin/bash

# Function to get temporary credentials from instance metadata
get_temp_credentials() {
    local role_name=$1
    local creds=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$role_name)
    export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $creds | jq -r '.Token')
}

# Function to assume a role and get temporary credentials
assume_role() {
    local role_arn=$1
    local session_name=$2
    local creds=$(aws sts assume-role --role-arn "$role_arn" --role-session-name "$session_name")
    export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $creds | jq -r '.Credentials.SessionToken')
}

status() {
    watch -n 1 "\
    AWS_REGION="${AWS_DEFAULT_REGION}" \
    aws ec2 describe-store-image-tasks"
}

import_ami() {
    AMI_ID="${2}"
    TARGET_AMI_NAME="${3:-my-cool-ami}"

    if test -n "${AMI_ID}"; then
        echo "Importing ${AMI_ID} @ ${AWS_DEFAULT_REGION} -> ${TARGET_AMI_NAME} @ ${AWS_REGION_GOV}"
    else
        echo "Usage: ./ami-cp.sh import_ami ami-id"
        echo "missing source ami-id"
        echo "exiting..."
        exit 1
    fi

    # Get temporary credentials for the commercial role
    COMMERCIAL_ROLE_NAME="YourCommercialRoleName"
    get_temp_credentials $COMMERCIAL_ROLE_NAME

    # Copy AMI from aws commercial
    STS=$(AWS_REGION="${AWS_DEFAULT_REGION}" \
    aws ec2 create-store-image-task \
        --image-id "${AMI_ID}" \
        --bucket "${S3_BUCKET_COMMERCIAL}" | jq .OriginKey)

    # Check status of ami export
    STS=$(AWS_REGION="${AWS_DEFAULT_REGION}" \
    aws ec2 describe-store-image-tasks \
        |  jq -c ".StoreImageTaskResults | map(select(.AmiId == \"${AMI_ID}\"))[0].ProgressPercentage")

    i=1
    sp="/-\|"

    until [ $STS -eq 100 ]; do
        printf "\b${sp:i++%${#sp}:1} progress=$STS\r"
        sleep 1
        STS=$(AWS_REGION="${AWS_DEFAULT_REGION}" \
        aws ec2 describe-store-image-tasks \
            |  jq -c ".StoreImageTaskResults | map(select(.AmiId == \"${AMI_ID}\"))[0].ProgressPercentage")
    done

    AMI_ID_BIN="${2}".bin
    AMI_NAME=${3:-ami-from-aws-commercial}

    echo "AMI_ID=${2}, AMI_NAME="${TARGET_AMI_NAME}", S3_BUCKET_GOV="${S3_BUCKET_GOV}", AWS_REGION_GOV="${AWS_REGION_GOV}""
    echo "S3_BUCKET_COMMERCIAL="${S3_BUCKET_COMMERCIAL}", AWS_REGION_COMMERCIAL="${AWS_DEFAULT_REGION}""

    # Get image from commercial aws
    AWS_REGION="${AWS_DEFAULT_REGION}" \
    aws s3 cp "s3://${S3_BUCKET_COMMERCIAL}"/${AMI_ID_BIN} ${AMI_ID_BIN}

    # Assume the role in the GovCloud account
    GOVCLOUD_ROLE_ARN="arn:aws-us-gov:iam::GOVCLOUD_ACCOUNT_ID:role/GovCloudRole"
    assume_role $GOVCLOUD_ROLE_ARN "GovCloudSession"

    # Upload image to gov s3
    AWS_REGION="${AWS_REGION_GOV}" \
    aws s3 cp "${AMI_ID_BIN}" "s3://${S3_BUCKET_GOV}"

    # Load image to EC2
    AMI_ID_GOV=$(AWS_REGION=$AWS_REGION_GOV \
    aws ec2 create-restore-image-task \
        --object-key "${AMI_ID_BIN}" \
        --bucket "${S3_BUCKET_GOV}" \
        --name "${AMI_NAME}" | jq -r .ImageId)

    echo "Successfully copied ${AMI_ID} @ ${AWS_DEFAULT_REGION} --> ${AMI_ID_GOV} @ ${AWS_REGION_GOV}"

    # Make the copied AMI public in GovCloud regions
    GOVCLOUD_REGIONS=("us-gov-west-1" "us-gov-east-1")
    for GOVCLOUD_REGION in "${GOVCLOUD_REGIONS[@]}"; do
        if [[ "$GOVCLOUD_REGION" != "$AWS_REGION_GOV" ]]; then
            echo "Copying AMI $AMI_ID_GOV to region $GOVCLOUD_REGION"
            COPY_AMI_ID=$(AWS_REGION=$GOVCLOUD_REGION \
            aws ec2 copy-image --source-image-id "$AMI_ID_GOV" --source-region "$AWS_REGION_GOV" --region "$GOVCLOUD_REGION" --name "$TARGET_AMI_NAME" --query 'ImageId' --output text)

            # Wait for the copied AMI to become available
            AWS_REGION=$GOVCLOUD_REGION \
            aws ec2 wait image-available --image-ids "$COPY_AMI_ID"

            # Make the copied AMI public
            echo "Making copied AMI $COPY_AMI_ID public in region $GOVCLOUD_REGION"
            AWS_REGION=$GOVCLOUD_REGION \
            aws ec2 modify-image-attribute --image-id "$COPY_AMI_ID" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}"
        fi
    done
}

usage() {
    echo "usage: $0 [ import_ami | status ]"
    exit 1
}

case "${1}"
in
    ("import_ami") import_ami ${@} ;;
    ("status") status ;;
    (*) usage ;;
esac
