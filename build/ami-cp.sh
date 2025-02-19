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
        echo "Importing ${AMI_ID} @ ${AWS_DEFAULT_REGION} -> ${TARGET_AMI_NAME} @ us-gov-east-1 and us-gov-west-1"
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
        --profile commercial

    # Wait for the AMI to be copied to S3
    echo "Waiting for AMI ${AMI_ID} to be copied to S3 in ${AWS_DEFAULT_REGION}"
    AWS_REGION="${AWS_DEFAULT_REGION}" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws ec2 wait store-image-task-complete \
        --image-id "${AMI_ID}" \
        --profile commercial
    echo "Successfully copied ${AMI_ID} to ${S3_BUCKET_COMMERCIAL}"

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

    # Load image to EC2 in both regions in parallel
    echo "Restoring AMI ${AMI_ID} from ${S3_BUCKET_GOV} to us-gov-east-1 and us-gov-west-1"
    declare -A AMI_IDS
    for REGION in "us-gov-east-1" "us-gov-west-1"; do
        AMI_IDS[$REGION]=$(AWS_REGION="$REGION" \
        AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
        AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
        aws ec2 create-restore-image-task \
            --object-key "${AMI_ID_BIN}" \
            --bucket "${S3_BUCKET_GOV}" \
            --name "${AMI_NAME}" \
            --profile govcloud | jq -r .ImageId) &
    done

    wait

    echo "Successfully copied ${AMI_ID} @ ${AWS_DEFAULT_REGION} --> ${AMI_IDS[us-gov-east-1]} @ us-gov-east-1 and ${AMI_IDS[us-gov-west-1]} @ us-gov-west-1"

    # Wait for the copied AMIs to become available
    for REGION in "us-gov-east-1" "us-gov-west-1"; do
        echo "Waiting for AMI ${AMI_IDS[$REGION]} to become available in GovCloud region $REGION"
        AWS_REGION="$REGION" \
        AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
        AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
        aws ec2 wait image-available --region "$REGION" --image-ids "${AMI_IDS[$REGION]}" --profile govcloud &
    done

    wait

    # Make the AMIs public
    for REGION in "us-gov-east-1" "us-gov-west-1"; do
        echo "Making AMI ${AMI_IDS[$REGION]} public in $REGION"
        AWS_REGION="$REGION" \
        AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
        AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
        aws ec2 modify-image-attribute --image-id "${AMI_IDS[$REGION]}" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile govcloud &
    done

    wait

    echo "Successfully copied ${AMI_ID} @ ${AWS_DEFAULT_REGION} --> ${AMI_IDS[us-gov-east-1]} @ us-gov-east-1 and ${AMI_IDS[us-gov-west-1]} @ us-gov-west-1"
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
