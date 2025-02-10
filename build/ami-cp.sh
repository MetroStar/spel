#!/bin/bash

status() {
    watch -n 1 "\
    AWS_REGION="${AWS_DEFAULT_REGION}" \
    aws ec2 describe-store-image-tasks --profile commercial"
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

    # Copy AMI from aws commercial
    STS=$(aws ec2 create-store-image-task \
        --image-id "${AMI_ID}" \
        --bucket "${S3_BUCKET_COMMERCIAL}" \
        --profile commercial | jq .OriginKey)

    # Check status of ami export
    STS=$(aws ec2 describe-store-image-tasks \
        --profile commercial \
        |  jq -c ".StoreImageTaskResults | map(select(.AmiId == \"${AMI_ID}\"))[0].ProgressPercentage")

    i=1
    sp="/-\|"

    until [ $STS -eq 100 ]; do
        printf "\b${sp:i++%${#sp}:1} progress=$STS\r"
        sleep 1
        STS=$(aws ec2 describe-store-image-tasks \
            --profile commercial \
            |  jq -c ".StoreImageTaskResults | map(select(.AmiId == \"${AMI_ID}\"))[0].ProgressPercentage")
    done

    AMI_ID_BIN="${2}".bin
    AMI_NAME=${3:-ami-from-aws-commercial}

    echo "AMI_ID=${2}, AMI_NAME="${TARGET_AMI_NAME}", S3_BUCKET_GOV="${S3_BUCKET_GOV}", AWS_REGION_GOV="us-gov-west-1""
    echo "S3_BUCKET_COMMERCIAL="${S3_BUCKET_COMMERCIAL}", AWS_REGION_COMMERCIAL="${AWS_DEFAULT_REGION}""

    # Get image from commercial aws
    aws s3 cp "s3://${S3_BUCKET_COMMERCIAL}"/${AMI_ID_BIN} ${AMI_ID_BIN} --profile commercial
    aws s3 rm "s3://${S3_BUCKET_COMMERCIAL}"/${AMI_ID_BIN} --profile commercial

    # Upload image to gov s3
    aws s3 cp "${AMI_ID_BIN}" "s3://${S3_BUCKET_GOV}" --profile govcloud
    rm "${AMI_ID_BIN}"

    # Load image to EC2
    AMI_ID_GOV=$(aws ec2 create-restore-image-task \
        --object-key "${AMI_ID_BIN}" \
        --bucket "${S3_BUCKET_GOV}" \
        --name "${AMI_NAME}" \
        --profile govcloud | jq -r .ImageId)

    echo "Successfully copied ${AMI_ID} @ ${AWS_DEFAULT_REGION} --> ${AMI_ID_GOV} @ us-gov-west-1"

    # Wait for the copied AMI to become available
    aws ec2 wait image-available --region "us-gov-west-1" --image-ids "$AMI_ID_GOV" --profile govcloud

    echo "Making AMI $AMI_ID_GOV public"
    aws ec2 modify-image-attribute --image-id "$AMI_ID_GOV" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile govcloud

    # Copy AMI to other GovCloud region
    echo "Copying AMI $AMI_ID_GOV to region us-gov-east-1"
    COPY_AMI_ID=$(aws ec2 copy-image --source-image-id "$AMI_ID_GOV" --source-region "us-gov-west-1" --region "us-gov-east-1" --name "$AMI_NAME" --query 'ImageId' --output text --profile govcloud)

    # Wait for the copied AMI to become available
    aws ec2 wait image-available --region "us-gov-east-1" --image-ids "$COPY_AMI_ID" --profile govcloud

    # Make the copied AMI public in other GovCloud region
    echo "Making copied AMI $COPY_AMI_ID in GovCloud region us-gov-east-1 public"
    aws ec2 modify-image-attribute --region "us-gov-east-1" --image-id "$COPY_AMI_ID" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile govcloud
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
