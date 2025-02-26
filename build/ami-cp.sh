#!/bin/bash
set -e

import_ami() {
    AMI_ID="${1}"
    TARGET_AMI_NAME="${2:-my-cool-ami}"

    if test -n "${AMI_ID}"; then
        echo "Importing ${TARGET_AMI_NAME} -> us-gov-east-1 and us-gov-west-1"
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

    # Copy AMI from aws commercial
    echo "Copying ${TARGET_AMI_NAME} to ${S3_BUCKET_COMMERCIAL}"
    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws ec2 create-store-image-task \
        --image-id "${AMI_ID}" \
        --bucket "${S3_BUCKET_COMMERCIAL}" \
        --profile commercial \
        --output text

    # Wait for the AMI to be copied to S3
    echo "Waiting for ${TARGET_AMI_NAME} to be copied to ${S3_BUCKET_COMMERCIAL}"
    while true; do
        TASK_STATE=$(AWS_REGION="us-east-1" \
            AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
            AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
            aws ec2 describe-store-image-tasks --image-id "${AMI_ID}" --query "StoreImageTaskResults[0].StoreTaskState" --output text --profile commercial)

        if [ "$TASK_STATE" == "Completed" ]; then
            echo "Successfully copied ${TARGET_AMI_NAME} to ${S3_BUCKET_COMMERCIAL}"
            break
        elif [ "$TASK_STATE" == "Failed" ]; then
            echo "Failed to copy ${TARGET_AMI_NAME} to ${S3_BUCKET_COMMERCIAL}"
            exit 1
        else
            echo "Current state: $TASK_STATE. Waiting..."
            sleep 30
        fi
    done

    AMI_ID_BIN="${1}".bin
    AMI_NAME=${2:-ami-from-aws-commercial}

    # Get image from commercial aws
    echo "Downloading ${TARGET_AMI_NAME} from ${S3_BUCKET_COMMERCIAL}"
    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws s3 cp "s3://${S3_BUCKET_COMMERCIAL}/${AMI_ID_BIN}" "${AMI_ID_BIN}" --profile commercial
    echo "Successfully downloaded ${TARGET_AMI_NAME} from ${S3_BUCKET_COMMERCIAL}"

    echo "Deleting ${TARGET_AMI_NAME} in ${S3_BUCKET_COMMERCIAL}"
    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws s3 rm "s3://${S3_BUCKET_COMMERCIAL}/${AMI_ID_BIN}" --profile commercial
    echo "Successfully deleted ${TARGET_AMI_NAME} in ${S3_BUCKET_COMMERCIAL}"

    AWS_REGION="us-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_COMMERCIAL_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_COMMERCIAL_SECRET_ACCESS_KEY}" \
    aws s3 rb "s3://${S3_BUCKET_COMMERCIAL}" --force --region "us-east-1" --profile commercial

    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 mb "s3://${S3_BUCKET_GOV_EAST}" --region "us-gov-east-1" --profile govcloud

    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 mb "s3://${S3_BUCKET_GOV_WEST}" --region "us-gov-west-1" --profile govcloud

    # Upload image to gov s3
    echo "Uploading ${TARGET_AMI_NAME} to ${S3_BUCKET_GOV_EAST}"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 cp "${AMI_ID_BIN}" "s3://${S3_BUCKET_GOV_EAST}" --profile govcloud
    echo "Successfully uploaded ${TARGET_AMI_NAME} to ${S3_BUCKET_GOV_EAST}"

    echo "Uploading AMI ${AMI_ID} to ${S3_BUCKET_GOV_WEST}"
    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws s3 cp "${AMI_ID_BIN}" "s3://${S3_BUCKET_GOV_WEST}" --profile govcloud
    echo "Successfully uploaded ${TARGET_AMI_NAME} to ${S3_BUCKET_GOV_WEST}"

    echo "Deleting ${TARGET_AMI_NAME} downloaded from ${S3_BUCKET_COMMERCIAL}"
    rm "${AMI_ID_BIN}"
    echo "Successfully deleted ${TARGET_AMI_NAME} downloaded from ${S3_BUCKET_COMMERCIAL}"

    # Load image to EC2 in us-gov-east-1
    echo "Restoring ${TARGET_AMI_NAME} from ${S3_BUCKET_GOV_EAST} to us-gov-east-1"
    AMI_ID_GOV_EAST=$(AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 create-restore-image-task \
        --object-key "${AMI_ID_BIN}" \
        --bucket "${S3_BUCKET_GOV_EAST}" \
        --name "${AMI_NAME}" \
        --profile govcloud | jq -r .ImageId)
    echo "Successfully copied ${TARGET_AMI_NAME} --> ${AMI_ID_GOV_EAST} @ us-gov-east-1"

    # Load image to EC2 in us-gov-west-1
    echo "Restoring ${TARGET_AMI_NAME} from ${S3_BUCKET_GOV_WEST} to us-gov-west-1"
    AMI_ID_GOV_WEST=$(AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 create-restore-image-task \
        --object-key "${AMI_ID_BIN}" \
        --bucket "${S3_BUCKET_GOV_WEST}" \
        --name "${AMI_NAME}" \
        --profile govcloud | jq -r .ImageId)
    echo "Successfully copied ${TARGET_AMI_NAME} --> ${AMI_ID_GOV_WEST} @ us-gov-west-1"

    # Wait for the copied AMI to become available in us-gov-east-1
    echo "Waiting for ${TARGET_AMI_NAME} to become available in us-gov-east-1"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 wait image-available --region "us-gov-east-1" --image-ids "${AMI_ID_GOV_EAST}" --profile govcloud
    echo "${TARGET_AMI_NAME} now available in us-gov-east-1"

    # Wait for the copied AMI to become available in us-gov-west-1
    echo "Waiting for ${TARGET_AMI_NAME} to become available in us-gov-west-1"
    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 wait image-available --region "us-gov-west-1" --image-ids "${AMI_ID_GOV_WEST}" --profile govcloud
    echo "${TARGET_AMI_NAME} now available in us-gov-west-1"

    # Get the snapshot ID associated with the AMI in us-gov-east-1
    SNAPSHOT_ID_GOV_EAST=$(AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 describe-images --image-ids "${AMI_ID_GOV_EAST}" --query "Images[0].BlockDeviceMappings[0].Ebs.SnapshotId" --output text --profile govcloud)

    # Get the snapshot ID associated with the AMI in us-gov-west-1
    SNAPSHOT_ID_GOV_WEST=$(AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 describe-images --image-ids "${AMI_ID_GOV_WEST}" --query "Images[0].BlockDeviceMappings[0].Ebs.SnapshotId" --output text --profile govcloud)

    # Wait for the snapshot to become available in us-gov-east-1
    echo "Waiting for snapshot ${SNAPSHOT_ID_GOV_EAST} to become available in us-gov-east-1"
    AWS_REGION="us-gov-east-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 wait snapshot-completed --snapshot-ids "${SNAPSHOT_ID_GOV_EAST}" --profile govcloud
    echo "Snapshot ${SNAPSHOT_ID_GOV_EAST} is now available in us-gov-east-1"

    # Wait for the snapshot to become available in us-gov-west-1
    echo "Waiting for snapshot ${SNAPSHOT_ID_GOV_WEST} to become available in us-gov-west-1"
    AWS_REGION="us-gov-west-1" \
    AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
    aws ec2 wait snapshot-completed --snapshot-ids "${SNAPSHOT_ID_GOV_WEST}" --profile govcloud
    echo "Snapshot ${SNAPSHOT_ID_GOV_WEST} is now available in us-gov-west-1"

    if [ "$PUBLIC" = "true" ]; then
        # Make the AMIs public
        echo "Making ${TARGET_AMI_NAME} public in us-gov-east-1"
        AWS_REGION="us-gov-east-1" \
        AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
        AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
        aws ec2 modify-image-attribute --image-id "${AMI_ID_GOV_EAST}" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile govcloud
        echo "${TARGET_AMI_NAME} now public in us-gov-east-1"

        echo "Making ${TARGET_AMI_NAME} public in us-gov-west-1"
        AWS_REGION="us-gov-west-1" \
        AWS_ACCESS_KEY_ID="${AWS_GOVCLOUD_ACCESS_KEY_ID}" \
        AWS_SECRET_ACCESS_KEY="${AWS_GOVCLOUD_SECRET_ACCESS_KEY}" \
        aws ec2 modify-image-attribute --image-id "${AMI_ID_GOV_WEST}" --launch-permission "{\"Add\": [{\"Group\":\"all\"}]}" --profile govcloud
        echo "${TARGET_AMI_NAME} now public in us-gov-west-1"
    fi

    echo "Successfully imported ${TARGET_AMI_NAME} --> us-gov-east-1 and us-gov-west-1"

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
}

# Copy AMI to GovCloud partition using the script from the repository
IFS=' ' read -r -a SUCCESS_BUILDS_ARRAY <<< "${SUCCESS_BUILDS}"
for BUILDER in "${SUCCESS_BUILDS_ARRAY[@]}"; do
    BUILD_NAME="${BUILDER//*./}"
    AMI_NAME="${SPEL_IDENTIFIER}-${BUILD_NAME}-${SPEL_VERSION}.x86_64-gp3"
    BUILDER_AMI=$(aws ec2 describe-images --filters Name=name,Values="$AMI_NAME" Name=creation-date,Values="$(date +%Y-%m-%dT*)" --owners self --query 'Images[0].ImageId' --out text --profile commercial)

    if [[ "$BUILDER_AMI" != "None" ]]; then
        import_ami "$BUILDER_AMI" "$AMI_NAME"
    fi
done
