# Build Documentation

This document explains the GitHub Actions workflow defined in `build.yml`, detailing each step, the purpose of configuring AWS credentials, the environment variables setup, and the functionality of the `build.sh` and `ami-cp.sh` scripts.

## GitHub Actions Workflow: `build.yml`

The `build.yml` workflow is designed to automate the process of building and publishing STIGed AMIs (Amazon Machine Images) for the SPEL project. The workflow is triggered manually or on a schedule and performs the following steps:

### Workflow Triggers

- **Manual Trigger**: The workflow can be manually triggered with an option to set the AMIs to public.
- **Scheduled Trigger**: The workflow runs on the first day of every month at 09:00 UTC.

### Permissions

- **id-token**: Write permission for generating OIDC tokens.
- **contents**: Write permission for repository contents.

### Job: Build SPEL AMIs

#### Steps

1. **Checkout Repository**
   - Uses the `actions/checkout@v4` action to clone the repository.

2. **Configure AWS Credentials**
   - Uses the `aws-actions/configure-aws-credentials@v2` action to configure AWS credentials for accessing AWS services.
   - Assumes the `Packer_Amazon` role in the specified AWS commercial account.

3. **Set Up Environment**
   - Sets up necessary environment variables for the build process:
     - `PUBLIC`: Indicates whether the AMIs should be public.
     - `SPEL_IDENTIFIER`: Identifier for the SPEL project.
     - `SPEL_VERSION`: Version of the build, based on the current date.
     - `PKR_VAR_aws_region`: AWS region for the build.
     - `PACKER_GITHUB_API_TOKEN`: GitHub API token for Packer.
     - AWS credentials for both commercial and GovCloud partitions.

4. **Install Necessary Packages**
   - Installs required packages for the build process, including `xz-utils`, `curl`, `jq`, `unzip`, `make`, and various development libraries.

5. **Install Packer**
   - Runs the `make -f Makefile.spel install` command to install Packer, a tool used for creating machine images.

6. **Build STIGed AMIs**
   - Runs the `make -f Makefile.spel build` command to build the AMIs using Packer.

7. **Copy STIGed AMIs to GovCloud**
   - Runs the `make -f Makefile.spel copy` command to copy the built AMIs to the AWS GovCloud regions.

8. **Check if README.md Needs Update**
   - Checks if the `README.md` file needs to be updated with the current month. Sets the `update_needed` environment variable accordingly.

9. **Update README.md with Current Month**
   - If an update is needed, updates the `README.md` file with the current month, commits the change, and pushes it to the repository.

## AWS Credentials Configuration

AWS credentials are configured to allow the workflow to interact with AWS services, such as creating and copying AMIs. The credentials are necessary for:
- Authenticating with AWS to perform operations.
- Assuming the required IAM role for accessing resources.

## Environment Variables Setup

The environment variables are set up to:
- Control the behavior of the build process (e.g., whether AMIs should be public).
- Provide necessary identifiers and versioning information.
- Supply AWS credentials for accessing commercial and GovCloud partitions.

## `build.sh` Script

The `build/build.sh` script performs the following tasks:
- Ensures required environment variables are set.
- Creates AWS CLI configuration files for commercial and GovCloud partitions.
- Checks and manages AMI quotas to avoid exceeding limits.
- Create AMIs using Packer and the `spel/minimal-linux.pkr.hcl` template.
- Retries failed builds until successful.
- Tests the built AMIs to ensure they meet the required standards using Packer and the `tests/minimal-linux.pkr.hcl` template.

## `build/ami-cp.sh` Script

The `ami-cp.sh` script handles the copying of AMIs to the AWS GovCloud regions. It performs the following tasks:
- Imports the specified AMI to the GovCloud regions.
- Generates unique S3 bucket names for temporary storage.
- Copies the AMI from the commercial partition to the S3 bucket in the commercial partition.
- Downloads the AMI from that S3 bucket and uploads it to the S3 buckets in their respective GovCloud regions.
- Restores the AMI to the GovCloud regions and makes them public if requested.
- Cleans up temporary S3 buckets and files.

This documentation provides an overview of the build process and the functionality of the key components involved in the GitHub Actions workflow.
