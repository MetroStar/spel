# Runbook

> **Crucible Platform** — Operational procedures for steady-state management.

Each procedure includes a trigger condition, step-by-step instructions, verification, and rollback guidance.

---

## Procedure 1: Monthly AMI Refresh

**Trigger**: Calendar schedule (monthly) or new OS patches available.

### Steps

1. Increment the version string:
   ```bash
   # Example: 2026.04.1 → 2026.05.1
   export CRUCIBLE_VERSION=2026.05.1
   ```

2. Trigger the build pipeline for all active OS targets.

3. After builds complete, review compliance artifacts:
   - Download OpenSCAP HTML report from build artifacts
   - Confirm no new STIG findings compared to previous month
   - If new findings appear, investigate whether upstream Ansible roles changed or a new package introduced the finding

4. Launch a test instance from each new hardened AMI. Run `tests/test-ssm-validation.sh` to verify SSM connectivity.

5. Update launch templates or Auto Scaling group configurations to reference the new AMI IDs.

6. Roll instances on the next deployment cycle (or trigger an ASG instance refresh).

### Verification

- New AMIs appear in EC2 with naming pattern `crucible-hardened-*-2026.05.1*`
- OpenSCAP score is equal to or better than the previous month
- Test instances register in SSM within 5 minutes of launch

### Rollback

Previous AMIs are retained in EC2 (only intermediate *minimal* AMIs are auto-deregistered). To roll back, update launch templates to reference the previous month's hardened AMI IDs.

---

## Procedure 2: New STIG Benchmark Release

**Trigger**: DISA publishes a new STIG benchmark version (typically quarterly).

### Steps

1. Check upstream Ansible Lockdown repositories for updated roles:
   - [RHEL8-STIG](https://github.com/ansible-lockdown/RHEL8-STIG)
   - [RHEL9-STIG](https://github.com/ansible-lockdown/RHEL9-STIG)
   - [Windows-2019-STIG](https://github.com/ansible-lockdown/Windows-2019-STIG)
   - [Windows-2022-STIG](https://github.com/ansible-lockdown/Windows-2022-STIG)

2. Update role version pins in `requirements.yml`.

3. Rebuild the Docker image (`offline-prepare.yml`) to pick up updated roles.

4. Build one OS as a smoke test. Compare OpenSCAP scores:
   ```bash
   # Before: download previous OpenSCAP report
   # After: download new build's OpenSCAP report
   # Diff the finding counts
   ```

5. Review any new findings that were previously passing. Determine if they are:
   - **New controls**: Need implementation or documented exception
   - **Changed controls**: Existing automation may need adjustment
   - **False positives**: Document in `docs/STIG_EXCEPTIONS.md`

6. Update `docs/STIG_EXCEPTIONS.md` if new exceptions are required.

7. Build all OS targets and run the full validation cycle.

### Verification

- `requirements.yml` references the new role versions
- OpenSCAP report shows compliance with the new benchmark version
- Exception documentation is current

### Rollback

Revert `requirements.yml` to previous version pins. Rebuild the Docker image.

---

## Procedure 3: Add a New OS Target

**Trigger**: Program requires an OS not currently built (e.g., RHEL 10, Windows Server 2025).

### Steps

1. **Add Packer source block** — In `crucible/hardened.pkr.hcl`, copy an existing source block and modify:
   - Source AMI filter (owner, name pattern)
   - Builder name (e.g., `amazon-ebs.hardened-rhel-10-hvm`)
   - SSH username if different

2. **Add STIG role** — Either:
   - Pin a new upstream Ansible Lockdown role in `requirements.yml`, or
   - Create a custom role under `crucible/ansible/roles/`

3. **Add build provisioner** — In `crucible/hardened.pkr.hcl`, add a `build` block referencing the new source and STIG role.

4. **Add SSM association** — In `infra/modules/ssm/ssm-stig-enforcement.tf`, create a new State Manager association targeting the new `StigPlatform` tag value.

5. **Update auto-tagging** — Ensure `infra/modules/ssm/auto-tagging.tf` propagates the new `StigPlatform` value.

6. **Update documentation**:
   - Add the OS to the support matrix in `docs/capability/reference-architecture.md`
   - Add the builder name to the supported builds table in `README.md`

7. Build and validate the new OS target.

### Verification

- Packer build completes successfully for the new OS
- OpenSCAP scan runs against the correct STIG benchmark
- SSM association targets the new platform tag correctly

---

## Procedure 4: Rotate KMS Key

**Trigger**: Key rotation policy (annual) or suspected compromise.

### Steps

1. **Enable automatic rotation** (if not already):
   ```bash
   aws kms enable-key-rotation --key-id <key-id>
   ```

2. **If replacing the key entirely**, update the OpenTofu variable:
   ```bash
   tofu apply -var="kms_key_id=arn:aws:kms:REGION:ACCOUNT:key/NEW-KEY-ID"
   ```

3. Re-encrypt existing S3 objects:
   ```bash
   # List objects in the SSM output bucket
   aws s3 ls s3://crucible-ssm-ACCOUNT/ --recursive

   # Copy objects in-place with new key (re-encrypts)
   aws s3 cp s3://crucible-ssm-ACCOUNT/ s3://crucible-ssm-ACCOUNT/ \
     --recursive --sse aws:kms --sse-kms-key-id NEW-KEY-ARN
   ```

4. Update the `aws_kms_key_id` variable in CI/CD pipeline configuration for future builds.

### Verification

- `aws kms describe-key --key-id <key-id>` shows the key is enabled
- New SSM outputs are encrypted with the new key
- Old key remains active for decrypting historical data (do not schedule deletion until all old data is rotated)

---

## Procedure 5: Onboard a New AWS Account or Region

**Trigger**: Program expands to a new AWS account (e.g., staging → production) or region.

### Steps

1. **Configure IAM in the new account** — Create an OIDC identity provider and IAM role with the same permissions used in the original account (see [CI-CD-Setup — IAM Configuration](../CI-CD-Setup.md#aws-iam-configuration)). Set `MaxSessionDuration` to at least 21600.

2. **Store the new role ARN** as a CI/CD secret or variable:
   - **GitHub Actions**: Add a new `AWS_ROLE_ARN` secret (or use environment-scoped secrets per account).
   - **GitLab CI**: Set `CI_AWS_ROLE_ARN` as a CI/CD variable, overriding per-pipeline when targeting the new account.

3. **Run the first build** targeting the new account/region. Infrastructure is provisioned automatically:
   - **GitHub Actions**: `build.yml` calls `infra-setup.yml` (`action=apply`, idempotent) — bootstraps the state backend, creates VPC/IAM/SSM resources, and proceeds to the AMI build.
   - **GitLab CI**: Set `PKR_VAR_aws_region` to the new region and run the pipeline (`infra:create` → build jobs).
   - **Alternative (local CLI)**: Provision infrastructure manually before building — see the [Onboarding Guide](onboarding-guide.md#provision-infrastructure-locally-optional).

4. **Copy AMIs** to the new region (if AMIs already exist elsewhere):
   ```bash
   aws ec2 copy-image \
     --source-region us-gov-west-1 \
     --source-image-id ami-0abc123 \
     --name "crucible-hardened-rhel-9-hvm-2026.04.1" \
     --region NEW-REGION --encrypted --kms-key-id NEW-KEY-ARN
   ```

   Or set `aws_ami_regions` in the Packer variables to auto-copy during builds.

5. **Validate** SSM connectivity in the new account by launching a test instance and running `tests/test-ssm-validation.sh`.

### Verification

- AMIs are available in the new region
- Instances launched in the new account register with SSM
- `tofu output` (via `infra-setup.yml` with `action=status` or locally) shows expected resources

---

## Procedure 6: Emergency STIG Remediation

**Trigger**: Critical vulnerability or compliance finding requires immediate remediation (cannot wait for the scheduled 7-day enforcement cycle).

### Steps

1. **Force immediate SSM association execution**:
   ```bash
   # Find the STIG enforcement association ID
   aws ssm list-associations \
     --filters "Key=AssociationName,Values=crucible-stig-enforce-el9"

   # Force execution now
   aws ssm start-associations-once \
     --association-ids "ASSOCIATION-ID"
   ```

2. **Or run ad-hoc remediation via RunCommand**:
   ```bash
   aws ssm send-command \
     --targets "Key=tag:StigPlatform,Values=EL9" \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["ansible-playbook /path/to/stig-playbook.yml"]'
   ```

3. **Verify remediation** by triggering an OpenSCAP scan:
   ```bash
   aws ssm send-command \
     --targets "Key=tag:StigPlatform,Values=EL9" \
     --document-name "crucible-openscap-scan" \
     --output-s3-bucket-name "crucible-ssm-ACCOUNT"
   ```

4. Review scan results in S3.

### Verification

- SSM RunCommand shows successful execution on target instances
- OpenSCAP report confirms the finding is resolved
- No new findings introduced by the remediation

---

## Procedure 7: Update CA Certificates

**Trigger**: New DoD PKI certificates issued, certificate expiry approaching, or organizational CA change.

### Steps

1. **Obtain the new certificate bundle** (typically a PKCS#7 `.p7b` or concatenated PEM file).

2. **Split the bundle** into individual certificates:
   ```bash
   cd crucible/ansible/ca-certs/
   python3 split_certs.py < new-bundle.pem
   ```

3. **Verify certificate fingerprints** against the DISA CRL or authoritative source:
   ```bash
   openssl x509 -in CERT_FILE.pem -fingerprint -noout
   ```

4. **Rebuild AMIs** to include the updated certificates. The `ca-certs-playbook.yml` installs them during the hardened build.

5. **For existing instances**, push the certificates via SSM RunCommand or wait for the next AMI refresh cycle.

### Verification

- `openssl verify -CApath /etc/pki/ca-trust/source/anchors/ /path/to/cert` succeeds on a launched instance
- No certificate trust warnings in application logs

---

## Procedure 8: Windows Admin Rename Recovery

**Trigger**: The AWS `AWSEC2-ConfigureSTIG` SSM document resets the administrator account rename. After running the managed document, the SID-500 account reverts to `Administrator`  instead of `maintuser`.

### Background

The Crucible Platform works around this with a custom SSM document (`infra/modules/ssm/ssm-documents.tf`) that:
1. Runs `AWSEC2-ConfigureSTIG` (STIG hardening)
2. Re-applies the admin rename via `secedit` and `Rename-LocalUser`

### Steps (if the rename is reverted outside the scheduled association)

1. **Verify the current admin name**:
   ```powershell
   # Via SSM Session Manager or RunCommand:
   Get-LocalUser | Where-Object { $_.SID -like '*-500' } | Select Name
   ```

2. **Re-apply the rename manually** via SSM RunCommand:
   ```powershell
   # Export current security policy
   secedit /export /cfg C:\Windows\Temp\secpol.cfg

   # Update the admin rename setting
   (Get-Content C:\Windows\Temp\secpol.cfg) -replace
     'NewAdministratorName\s*=\s*".*"',
     'NewAdministratorName = "maintuser"' |
     Set-Content C:\Windows\Temp\secpol.cfg

   # Apply the policy
   secedit /configure /db C:\Windows\security\local.sdb /cfg C:\Windows\Temp\secpol.cfg /areas SECURITYPOLICY

   # Rename the local user
   Rename-LocalUser -Name "Administrator" -NewName "maintuser"
   ```

3. **Or force the STIG enforcement association** (which includes the rename step):
   ```bash
   aws ssm start-associations-once --association-ids "WINDOWS-STIG-ASSOCIATION-ID"
   ```

### Verification

- `Get-LocalUser | Where-Object { $_.SID -like '*-500' }` returns `maintuser`
- RDP and Session Manager access work with the `maintuser` username
