#!/bin/bash
set -e

status() {
    watch -n 1 "\
    AWS_REGION=\"us-east-1\" \
    AWS_ACCESS_KEY_ID=\"${AWS_COMMERCIAL_ACCESS_KEY_ID}\" \
    AWS_SECRET_ACCESS_KEY=\"${AWS_COMMERCIAL_SECRET_ACCESS_KEY}\" \
    aws ec2 describe-store-image-tasks --profile commercial"
}

import_ami() {
    AMI_ID="${2}"
    TARGET_AMI_NAME="${3:-my-cool-ami}"

    if test -n "${AMI_ID}"; then
        echo "Importing ${AMI_ID} @ us-east-1 -> ${TARGET_AMI_NAME} @ us-gov-east-1 and us-gov-west-1"
    else
        echo "Usage: ./ami-cp.sh import_ami ami-id"
        echo "missing source ami-id"
        echo "exiting..."
        exit 1
    fi

    # Generate unique S3 bucket names
    TIMESTAMP=$(date +%s)
    RANDOM_STRING=$(openssl rand -hex 6)
    export S3_BUCKET_COMMERCIAL="commercial-${TIMESTAMP}-${RANDOM_STRING}"
    export S3_BUCKET_GOV_EAST="govcloud-east-${TIMESTAMP}-${RANDOM_STRING}"
    export S3_BUCKET_GOV_WEST="govcloud-west-${TIMESTAMP}-${RANDOM_STRING}"

    # Create S3 buckets
    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws s3 mb "s3://${S3_BUCKET_COMMERCIAL}" --region "us-east-1" --profile commercial

    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 mb "s3://${S3_BUCKET_GOV_EAST}" --region "us-gov-east-1" --profile govcloud

    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 mb "s3://${S3_BUCKET_GOV_WEST}" --region "us-gov-west-1" --profile govcloud

    # Copy AMI from aws commercial
    echo "Copying AMI ${AMI_ID} from us-east-1 to ${S3_BUCKET_COMMERCIAL}"
    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws ec2 create-store-image-task \
        --image-id "${AMI_ID}" \
        --bucket "${S3_BUCKET_COMMERCIAL}" \
        --profile commercial

    # Wait for the AMI to be copied to S3
    echo "Waiting for AMI ${AMI_ID} to be copied to S3 in us-east-1"
    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws ec2 wait store-image-task-complete \
        --image-id "${AMI_ID}" \
        --profile commercial
    echo "Successfully copied ${AMI_ID} to ${S3_BUCKET_COMMERCIAL}"

    AMI_ID_BIN="${2}".bin
    AMI_NAME=${3:-ami-from-aws-commercial}

    # Get image from commercial aws
    echo "Downloading AMI ${AMI_ID} from ${S3_BUCKET_COMMERCIAL}"
    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws s3 cp "s3://${S3_BUCKET_COMMERCIAL}/${AMI_ID_BIN}" "${AMI_ID_BIN}" --profile commercial
    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws s3 rm "s3://${S3_BUCKET_COMMERCIAL}/${AMI_ID_BIN}" --profile commercial

    # Upload image to gov s3
    echo "Uploading AMI ${AMI_ID} to ${S3_BUCKET_GOV_EAST}"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 cp "${AMI_ID_BIN}" "s3://${S3_BUCKET_GOV_EAST}" --profile govcloud

    echo "Uploading AMI ${AMI_ID} to ${S3_BUCKET_GOV_WEST}"
    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 cp "${AMI_ID_BIN}" "s3://${S3_BUCKET_GOV_WEST}" --profile govcloud

    rm "${AMI_ID_BIN}"

    # Load image to EC2 in us-gov-east-1
    echo "Restoring AMI ${AMI_ID} from ${S3_BUCKET_GOV_EAST} to us-gov-east-1"
    AMI_ID_GOV_EAST=$(AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 create-restore-image-task \
        --object-key "${AMI_ID_BIN}" \
        --bucket "${S3_BUCKET_GOV_EAST}" \
        --name "${AMI_NAME}" \
        --profile govcloud | jq -r .ImageId)
    echo "Successfully copied ${AMI_ID} @ us-east-1 --> ${AMI_ID_GOV_EAST} @ us-gov-east-1"

    # Load image to EC2 in us-gov-west-1
    echo "Restoring AMI ${AMI_ID} from ${S3_BUCKET_GOV_WEST} to us-gov-west-1"
    AMI_ID_GOV_WEST=$(AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 create-restore-image-task \
        --object-key "${AMI_ID_BIN}" \
        --bucket "${S3_BUCKET_GOV_WEST}" \
        --name "${AMI_NAME}" \
        --profile govcloud | jq -r .ImageId)
    echo "Successfully copied ${AMI_ID} @ us-east-1 --> ${AMI_ID_GOV_WEST} @ us-gov-west-1"

    # Wait for the copied AMI to become available in us-gov-east-1
    echo "Waiting for AMI ${AMI_ID_GOV_EAST} to become available in GovCloud region us-gov-east-1"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 wait image-available --region "us-gov-east-1" --image-ids "${AMI_ID_GOV_EAST}" --profile govcloud

    # Wait for the copied AMI to become available in us-gov-west-1
    echo "Waiting for AMI ${AMI_ID_GOV_EAST} to become available in GovCloud region us-gov-west-1"
    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 wait image-available --region "us-gov-west-1" --image-ids "${AMI_ID_GOV_WEST}" --profile govcloud

    # Make the AMIs public
    echo "Making AMI ${AMI_ID_GOV_EAST} public in us-gov-east-1"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 modify-image-attribute --image-id "${AMI_ID_GOV_EAST}" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile govcloud

    echo "Making AMI ${AMI_ID_GOV_WEST} public in us-gov-west-1"
    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 modify-image-attribute --image-id "${AMI_ID_GOV_WEST}" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile govcloud

    echo "Successfully imported ${AMI_ID} @ us-east-1 --> ${AMI_ID_GOV_EAST} @ us-gov-east-1 and ${AMI_ID_GOV_WEST} @ us-gov-west-1"

    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 rm "s3://${S3_BUCKET_GOV_EAST}/${AMI_ID_BIN}" --profile govcloud
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 rb "s3://${S3_BUCKET_GOV_EAST}" --force --region "us-gov-east-1" --profile govcloud

    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 rm "s3://${S3_BUCKET_GOV_WEST}/${AMI_ID_BIN}" --profile govcloud
    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 rb "s3://${S3_BUCKET_GOV_WEST}" --force --region "us-gov-west-1" --profile govcloud

    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws s3 rb "s3://${S3_BUCKET_COMMERCIAL}" --force --region "us-east-1" --profile commercial
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
