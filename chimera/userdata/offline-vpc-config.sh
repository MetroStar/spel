#!/bin/bash
#
# Offline VPC Endpoint Configuration Script
# This script configures DNS resolution for AWS service VPC endpoints
# Used when building in air-gapped Offline VPCs with privatelink endpoints
#
set -euo pipefail

# VPC endpoint DNS names (passed as environment variables from Packer)
VPC_ENDPOINT_EC2="${VPC_ENDPOINT_EC2:-}"
VPC_ENDPOINT_S3="${VPC_ENDPOINT_S3:-}"
VPC_ENDPOINT_SSM="${VPC_ENDPOINT_SSM:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "Configuring Offline VPC endpoint DNS resolution..."

# Add EC2 endpoint to /etc/hosts if specified
if [ -n "$VPC_ENDPOINT_EC2" ]; then
    echo "Configuring EC2 VPC endpoint: $VPC_ENDPOINT_EC2"
    echo "$VPC_ENDPOINT_EC2 ec2.${AWS_REGION}.amazonaws.com" >> /etc/hosts
    echo "$VPC_ENDPOINT_EC2 api.ec2.${AWS_REGION}.amazonaws.com" >> /etc/hosts
fi

# Add S3 endpoint to /etc/hosts if specified
if [ -n "$VPC_ENDPOINT_S3" ]; then
    echo "Configuring S3 VPC endpoint: $VPC_ENDPOINT_S3"
    echo "$VPC_ENDPOINT_S3 s3.${AWS_REGION}.amazonaws.com" >> /etc/hosts
    echo "$VPC_ENDPOINT_S3 s3-${AWS_REGION}.amazonaws.com" >> /etc/hosts
fi

# Add SSM endpoint to /etc/hosts if specified
if [ -n "$VPC_ENDPOINT_SSM" ]; then
    echo "Configuring SSM VPC endpoint: $VPC_ENDPOINT_SSM"
    echo "$VPC_ENDPOINT_SSM ssm.${AWS_REGION}.amazonaws.com" >> /etc/hosts
    echo "$VPC_ENDPOINT_SSM ec2messages.${AWS_REGION}.amazonaws.com" >> /etc/hosts
    echo "$VPC_ENDPOINT_SSM ssmmessages.${AWS_REGION}.amazonaws.com" >> /etc/hosts
fi

echo "VPC endpoint DNS configuration complete"
cat /etc/hosts
