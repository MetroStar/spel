# Troubleshooting Guide

> **Chimera Platform** — Decision-tree diagnosis for common failure modes.

Find the symptom that matches your situation, then follow the resolution steps. Each entry includes diagnostic commands you can run immediately.

---

## Build Failures

### Packer Times Out / SSH or WinRM Connection Refused

```
Symptom: "Timeout waiting for SSH" or "Timeout waiting for WinRM"
```

**Check 1 — Security group rules:**

```bash
aws ec2 describe-security-groups --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions'
```

Required inbound rules:
- **Linux**: TCP 22 (SSH)
- **Windows**: TCP 5986 (WinRM HTTPS)

**Check 2 — Subnet routing:**

```bash
# Connected (IGW):
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-xxxxx" \
  --query 'RouteTables[0].Routes'
# Verify a route to 0.0.0.0/0 via an IGW exists

# Air-gapped:
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'VpcEndpoints[].ServiceName'
# Verify: com.amazonaws.REGION.ec2, com.amazonaws.REGION.sts
```

**Check 3 — Instance profile:**

```bash
aws iam get-instance-profile --instance-profile-name chimera-packer
```

Verify the profile exists and has a role attached.

**Check 4 — Instance actually launched:**

Check the EC2 console for a recently launched instance. If no instance appears, the Packer AMI filter may be returning no results (see next section).

---

### Packer "No Valid Sources" / Source AMI Not Found

```
Symptom: "No AMI was found matching filters" or empty source_ami
```

**Check 1 — AMI owner for your partition:**

| Partition | RHEL Owner | Amazon Owner |
|-----------|-----------|--------------|
| Commercial (`aws`) | `309956199498` | `137112412989` |
| GovCloud (`aws-us-gov`) | `219670896067` | `045324592363` |

Verify the owner ID in `chimera/hardened.pkr.hcl` source blocks matches your partition.

**Check 2 — AMI name filter:**

```bash
# List available AMIs matching the filter pattern
aws ec2 describe-images \
  --owners 309956199498 \
  --filters "Name=name,Values=RHEL-9*" \
  --query 'Images[*].[Name,ImageId]' --output table
```

**Check 3 — Region mismatch:**

AMIs are region-specific. Verify `PKR_VAR_aws_region` matches where the source AMIs exist.

---

### RPM Signature Verification Fails

```
Symptom: "Package XXXX is not signed" or GPG check failures during OS install
```

This occurs in air-gapped environments using unsigned local mirrors.

**Fix:**

```bash
# Set in CI/CD variables:
AMIGEN_REPO_NOSIGNATURE=true

# Or set in Packer variables:
PKR_VAR_amigen_repo_nosignature=true
```

Only use this when you trust the mirror source. In connected environments, always use signed packages.

---

### FIPS Boot Failure (EL8)

```
Symptom: Instance fails to boot or kernel panic after STIG hardening on EL8
```

The RHEL8-STIG Ansible role can strip the `boot=UUID` parameter from `/etc/default/grub`, which breaks FIPS boot integrity validation.

**Diagnosis:**

```bash
# If the instance boots to a rescue shell:
grep boot=UUID /etc/default/grub
# If missing, this is the issue
```

**Fix:**

The `chimera/scripts/boot-fips-wrapper.sh` script handles this automatically during builds. If you see this failure:

1. Verify `boot-fips-wrapper.sh` is in the provisioner sequence in `chimera/hardened.pkr.hcl`
2. Check the build log for errors during the FIPS wrapper execution
3. Ensure `dracut-fips` was installed successfully

---

### Ansible Role Failure

```
Symptom: "role 'RHEL9-STIG' was not found" or collection import errors
```

**Check 1 — Role availability:**

```bash
# Inside the Docker container:
ls chimera/ansible/roles/
ls chimera/ansible/collections/ansible_collections/
```

Roles and collections must be present in the Docker image. If missing, rebuild the Docker image (`offline-prepare.yml`).

**Check 2 — Version pins:**

```bash
cat requirements.yml
```

Verify role and collection versions are pinned and available.

**Check 3 — Ansible configuration:**

```bash
cat ansible.cfg
```

Verify `roles_path` and `collections_path` include the correct directories.

---

### AWS Credentials Expire Mid-Build

```
Symptom: "ExpiredToken" or "The security token included in the request is expired"
(typically 1-3 hours into a build)
```

**Fix:**

```bash
# The IAM role's MaxSessionDuration must be >= 21600 (6 hours)
aws iam get-role --role-name YourRole --query 'Role.MaxSessionDuration'

# If less than 21600:
aws iam update-role --role-name YourRole --max-session-duration 21600
```

For GitHub Actions, also verify `role-duration-seconds: 21600` is set in the workflow's `aws-actions/configure-aws-credentials` step.

---

## Infrastructure Failures

### OpenTofu State Lock

```
Symptom: "Error acquiring the state lock" or "ConditionalCheckFailedException"
```

**Check 1 — Is another operation running?**

Wait for it to complete. If you are certain no other operation is running:

**Check 2 — Stale lock:**

```bash
# View the lock info
aws dynamodb get-item \
  --table-name chimera-tfstate-lock \
  --key '{"LockID":{"S":"chimera-tfstate-ACCOUNT/terraform.tfstate"}}'

# Force unlock (ONLY if you're certain no other operation is running):
cd infra/
tofu force-unlock LOCK_ID
```

---

### VPC Endpoint DNS Resolution Fails

```
Symptom: Air-gapped build can't reach AWS APIs despite VPC endpoints existing
```

**Check 1 — Endpoints are in the correct VPC and subnet:**

```bash
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'VpcEndpoints[].[ServiceName,State,DnsEntries[0].DnsName]'
```

All endpoints should show `State: available`.

**Check 2 — DNS resolution:**

The `chimera/userdata/offline-vpc-config.sh` script configures `/etc/hosts` entries for offline DNS. Verify it ran during instance startup:

```bash
# On the build instance:
cat /etc/hosts | grep amazonaws
```

**Check 3 — Security group allows endpoint traffic:**

VPC interface endpoints have their own security groups. Verify HTTPS (443) inbound is allowed from the build subnet CIDR.

---

### KMS Key Access Denied

```
Symptom: "AccessDeniedException" when encrypting/decrypting with KMS
```

**Check 1 — IAM policy includes KMS actions:**

The Packer execution role and the instance profile both need:
- `kms:GenerateDataKey*`
- `kms:Decrypt`
- `kms:Encrypt`
- `kms:DescribeKey`
- `kms:CreateGrant`

See [CI-CD-Setup — IAM Configuration](../CI-CD-Setup.md#aws-iam-configuration) for the full policy.

**Check 2 — KMS key policy allows the principal:**

```bash
aws kms get-key-policy --key-id KEY_ARN --policy-name default --output text
```

Verify the key policy includes the Packer execution role and the instance profile role as principals.

---

## Runtime / SSM Failures

### Instance Not Appearing in SSM

```
Symptom: Launched instance from hardened AMI but it doesn't show in Systems Manager Fleet Manager
```

**Check 1 — Instance profile:**

```bash
aws ec2 describe-instances --instance-ids i-xxxxx \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'
```

The instance must have an instance profile with `AmazonSSMManagedInstanceCore` (or equivalent permissions).

**Check 2 — VPC endpoints (air-gapped):**

```bash
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'VpcEndpoints[].ServiceName' --output table
```

Required: `ssm`, `ssmmessages`, `ec2messages`. Without these, the SSM agent cannot communicate.

**Check 3 — DHMC (Default Host Management Configuration):**

```bash
aws ssm get-service-setting \
  --setting-id arn:aws:ssm:REGION:ACCOUNT:servicesetting/ssm/managed-instance/default-ec2-instance-management-role
```

Should return the role configured by OpenTofu.

**Check 4 — SSM Agent running:**

```bash
# Connect via SSH (if possible) or check instance console output:
systemctl status amazon-ssm-agent
```

---

### STIG Association Execution Failed

```
Symptom: SSM State Manager association shows "Failed" status
```

**Check 1 — Review output in S3:**

```bash
aws s3 ls s3://chimera-ssm-ACCOUNT/ssm-output/ --recursive | tail
# Download the latest output for the failed association
```

**Check 2 — Verify tools are pre-installed on AMI:**

The hardened AMI should include: `ansible-core`, `openscap-scanner`, `scap-security-guide`, `unzip`, `wget`. If missing, the AMI build may not have completed the hardening phase fully.

**Check 3 — Tag targeting:**

```bash
aws ec2 describe-tags --filters \
  "Name=resource-id,Values=i-xxxxx" \
  "Name=key,Values=StigPlatform"
```

Verify the instance has the correct `StigPlatform` tag matching the association target.

---

### Patch Manager Not Patching

```
Symptom: Instances not receiving patches during maintenance windows
```

**Check 1 — Patch group membership:**

```bash
aws ec2 describe-tags --filters \
  "Name=resource-id,Values=i-xxxxx" \
  "Name=key,Values=Patch Group"
```

Instances must be tagged with the correct `Patch Group` value.

**Check 2 — Maintenance window schedule:**

```bash
aws ssm describe-maintenance-windows \
  --query 'WindowIdentities[].[Name,Schedule,Enabled]'
```

Default: Sunday 4:00 AM UTC. Verify the window is enabled and the schedule is correct.

**Check 3 — Baseline approval rules:**

```bash
aws ssm describe-patch-baselines --filters \
  "Key=OWNER,Values=Self" \
  --query 'BaselineIdentities[].[BaselineName,DefaultBaseline]'
```

Verify custom baselines are set as defaults for the patch groups.

---

### Windows Admin Rename Reverted

```
Symptom: SID-500 account is "Administrator" instead of "maintuser"
```

See [Runbook — Procedure 8: Windows Admin Rename Recovery](runbook.md#procedure-8-windows-admin-rename-recovery) for the full fix.

Quick check:

```powershell
Get-LocalUser | Where-Object { $_.SID -like '*-500' } | Select Name
```

---

## Air-Gapped Specific

### Docker Import Fails on GitLab Runner

```
Symptom: "Error processing tar file" or checksum mismatch
```

**Check 1 — Tarball integrity:**

```bash
ls -lh /transfer/chimera-builder-*.tar.gz
sha256sum -c /transfer/chimera-builder-*.tar.gz.sha256
```

**Check 2 — Disk space:**

```bash
df -h /var/lib/docker
```

Docker needs at least ~1 GB free to import the ~834 MB uncompressed image.

**Check 3 — Docker daemon:**

```bash
systemctl status docker
docker info | grep "Storage Driver"
```

---

### Base64 Decode Fails

```
Symptom: Corrupted tarball after decoding base64 file from SharePoint transfer
```

SharePoint and some email systems inject line breaks or modify binary content during transfer.

**Fix:**

```bash
# Re-decode with explicit settings:
base64 -d chimera-builder-*.tar.gz.b64 > chimera-builder-decoded.tar.gz

# Verify checksum:
sha256sum chimera-builder-decoded.tar.gz
```

If the checksum still doesn't match, the file was corrupted during upload to SharePoint. Re-upload using a method that preserves binary integrity (e.g., zip the `.b64` file first, or use SFTP/SCP instead).

---

### "Connection Refused" During Air-Gapped Build

```
Symptom: Packer or SSM operations fail with connection errors in disconnected environment
```

**Check — All 8 VPC endpoint types are provisioned:**

```bash
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'VpcEndpoints[].ServiceName' --output table
```

Required endpoints:

| Endpoint | Required For |
|----------|-------------|
| `com.amazonaws.REGION.ec2` | Packer API calls |
| `com.amazonaws.REGION.sts` | OIDC credential exchange |
| `com.amazonaws.REGION.ssm` | SSM agent registration |
| `com.amazonaws.REGION.ssmmessages` | Session Manager |
| `com.amazonaws.REGION.ec2messages` | SSM RunCommand |
| `com.amazonaws.REGION.logs` | CloudWatch log delivery |
| `com.amazonaws.REGION.kms` | KMS encryption operations |
| `com.amazonaws.REGION.s3` | S3 access (Gateway endpoint) |

If any are missing, re-run `tofu apply` with `enable_vpc_endpoints=true` and `enable_packer_endpoints=true`.

---

## See Also

- [CI-CD-Setup — IAM Configuration](../CI-CD-Setup.md#aws-iam-configuration) for IAM policy details
- [Windows-STIG-Driver-Compatibility](../Windows-STIG-Driver-Compatibility.md) for Windows-specific boot and driver issues
- [STIG Exceptions](../STIG_EXCEPTIONS.md) for controls intentionally skipped
