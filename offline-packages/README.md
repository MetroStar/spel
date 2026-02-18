# Offline AWS Utilities Packages for Offline Builds

> **Note**: This directory contains ONLY AWS-specific utilities (AWS CLI, SSM Agent, CFN Bootstrap).  
> YUM/DNF repository mirrors are NOT synced for Offline - the Offline environment has its own RPM repositories available.

## Downloads

If you prefer to download manually:

### 1. AWS CLI v2
```bash
wget https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
  -O offline-packages/awscli-exe-linux-x86_64.zip
```

### 2. AWS CloudFormation Bootstrap
```bash
wget https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz \
  -O offline-packages/aws-cfn-bootstrap-py3-latest.tar.gz
```

### 3. AWS SSM Agent (Compatible with EL8/EL9)

**Note:** Single SSM Agent RPM works for both EL8 and EL9 (saves storage)

```bash
wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm \
  -O offline-packages/amazon-ssm-agent.rpm
```

## File Sizes (Approximate)

- AWS CLI v2: ~50 MB
- AWS CFN Bootstrap: ~500 KB
- AWS SSM Agent: ~25 MB
- **Total: ~75 MB** (optimized - single SSM agent)
- **Compressed: ~70 MB**

> **Note**: The Dockerfile also downloads `LinuxAWSConfigureSTIG.tgz` (the AWS STIG script for AL2023), which is base64-encoded into the Docker image. That file is not stored in this directory.

## Usage in Packer

These files are referenced in Packer templates via variables:

```hcl
export PKR_VAR_spel_cfnbootstrap_source="file://$(pwd)/offline-packages/aws-cfn-bootstrap-py3-latest.tar.gz"
export PKR_VAR_spel_awscli_source="file://$(pwd)/offline-packages/awscli-exe-linux-x86_64.zip"
export PKR_VAR_spel_ssm_agent_source="file://$(pwd)/offline-packages/amazon-ssm-agent.rpm"
```

## Verification

After downloading, verify the files:

```bash
ls -lh offline-packages/
# Should show:
# - awscli-exe-linux-x86_64.zip
# - aws-cfn-bootstrap-py3-latest.tar.gz
# - amazon-ssm-agent.rpm (or symlink)
```
