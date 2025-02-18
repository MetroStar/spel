#!/bin/bash
set -e

status() {
    watch -n 1 "\
    AWS_REGION=\"${AWS_DEFAULT_REGION}\" \
    AWS_ACCESS_KEY_ID=\"${AWS_COMMERCIAL_ACCESS_KEY_ID}\" \
    AWS_SECRET_ACCESS_KEY=\"${AWS_COMMERCIAL_SECRET_ACCESS_KEY}\" \
    aws ec2 describe-store-image-tasks --profile commercial"
}

import_ami() {
    AMI_ID="${2}"
    TARGET_AMI_NAME="${3:-my-cool-ami}"

    if test -n "${AMI_ID}"; then
        echo "Importing ${AMI_ID} @ ${AWS_DEFAULT_REGION} -> ${TARGET_AMI_NAME} @ us-gov-east-1"
    else
        echo "Usage: ./ami-cp.sh import_ami ami-id"
        echo "missing source ami-id"
        echo "exiting..."
        exit 1
    fi

    # Copy AMI from aws commercial
    echo "Copying AMI ${AMI_ID} from ${AWS_DEFAULT_REGION} to ${S3_BUCKET_COMMERCIAL}"
    AWS_REGION="${AWS_DEFAULT_REGION}" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws ec2 create-store-image-task \
        --image-id "${AMI_ID}" \
        --bucket "${S3_BUCKET_COMMERCIAL}" \
        --profile commercial | jq .OriginKey

    AMI_ID_BIN="${2}".bin
    AMI_NAME=${3:-ami-from-aws-commercial}

    echo "AMI_ID=${2}, AMI_NAME=${TARGET_AMI_NAME}, S3_BUCKET_GOV=${S3_BUCKET_GOV}, AWS_REGION_GOV=us-gov-east-1"
    echo "S3_BUCKET_COMMERCIAL=${S3_BUCKET_COMMERCIAL}, AWS_REGION_COMMERCIAL=${AWS_DEFAULT_REGION}"

    # Get image from commercial aws
    echo "Downloading AMI ${AMI_ID} from ${S3_BUCKET_COMMERCIAL}"
    AWS_REGION="${AWS_DEFAULT_REGION}" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws s3 cp "s3://${S3_BUCKET_COMMERCIAL}/${AMI_ID_BIN}" "${AMI_ID_BIN}" --profile commercial
    aws s3 rm "s3://${S3_BUCKET_COMMERCIAL}/${AMI_ID_BIN}" --profile commercial

    # Upload image to gov s3
    echo "Uploading AMI ${AMI_ID} to ${S3_BUCKET_GOV}"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 cp "${AMI_ID_BIN}" "s3://${S3_BUCKET_GOV}" --profile govcloud
    rm "${AMI_ID_BIN}"

    # Load image to EC2
    echo "Restoring AMI ${AMI_ID} from ${S3_BUCKET_GOV} to us-gov-east-1"
    AMI_ID_GOV=$(AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 create-restore-image-task \
        --object-key "${AMI_ID_BIN}" \
        --bucket "${S3_BUCKET_GOV}" \
        --name "${AMI_NAME}" \
        --profile govcloud | jq -r .ImageId)

    echo "Successfully copied ${AMI_ID} @ ${AWS_DEFAULT_REGION} --> ${AMI_ID_GOV} @ us-gov-east-1"

    # Wait for the copied AMI to become available
    echo "Waiting for AMI ${AMI_ID_GOV} to become available in GovCloud region us-gov-east-1"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 wait image-available --region "us-gov-east-1" --image-ids "${AMI_ID_GOV}" --profile govcloud

    echo "Making AMI ${AMI_ID_GOV} public"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 modify-image-attribute --image-id "${AMI_ID_GOV}" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile govcloud

    # Copy AMI to other GovCloud region
    echo "Copying AMI ${AMI_ID_GOV} to region us-gov-west-1"
    COPY_AMI_ID=$(AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 copy-image --source-image-id "${AMI_ID_GOV}" --source-region "us-gov-east-1" --region "us-gov-west-1" --name "${AMI_NAME}" --query 'ImageId' --output text --profile govcloud)

    # Wait for the copied AMI to become available
    echo "Waiting for copied AMI ${COPY_AMI_ID} to become available in GovCloud region us-gov-west-1"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 wait image-available --region "us-gov-west-1" --image-ids "${COPY_AMI_ID}" --profile govcloud

    # Make the copied AMI public in other GovCloud region
    echo "Making copied AMI ${COPY_AMI_ID} in GovCloud region us-gov-west-1 public"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 modify-image-attribute --region "us-gov-west-1" --image-id "${COPY_AMI_ID}" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile govcloud

    echo "Successfully copied ${AMI_ID} @ ${AWS_DEFAULT_REGION} --> ${COPY_AMI_ID} @ us-gov-west-1"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 rm "s3://${S3_BUCKET_GOV}/${AMI_ID_BIN}" --profile govcloud
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
