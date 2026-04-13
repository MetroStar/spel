# Operating Model

> **Chimera Platform** — Day 0 through steady-state operations for STIG-hardened AMI builds and continuous compliance.

This document defines responsibilities, schedules, and workflows for each phase of the platform lifecycle.

## Lifecycle Phases

```mermaid
gantt
    title Platform Lifecycle
    dateFormat X
    axisFormat %s

    section Day 0 — Setup
    Provision infrastructure   :d0a, 0, 2
    First Docker image build   :d0b, 0, 1

    section Day 1 — Build
    First hardened AMI         :d1a, 2, 6
    Validate + distribute      :d1b, 6, 7

    section Day 2+ — Operate
    Scheduled STIG enforcement :d2a, 7, 30
    Patch management           :d2b, 7, 30
    Monthly AMI refresh        :d2c, 7, 30
```

## Day 0 — Setup

**Duration**: 1–2 hours (connected) or 2–4 hours (air-gapped, including Docker import)

### Steps

1. **Configure IAM prerequisites** (one-time per AWS account) — Create an IAM OIDC identity provider for GitHub Actions or GitLab, and an IAM role with permissions for Packer, OpenTofu, and SSM. Set `MaxSessionDuration` to at least 21600 (6 hours). Store the role ARN as a CI/CD secret. See [CI-CD-Setup — IAM Configuration](../CI-CD-Setup.md#aws-iam-configuration) for the full IAM policies.

2. **Provision infrastructure via CI/CD** — The pipelines automate backend bootstrap, tfvars generation, and `tofu apply`:
   - **GitHub Actions**: Run the `infra-setup.yml` workflow with `action=apply` (or let `build.yml` call it automatically before the first build).
   - **GitLab CI**: Run the `infra:create` job from `.gitlab/infra.gitlab-ci.yml`.
   - **Alternative**: Run `tofu apply` from `infra/` locally (see [Onboarding Guide — Step 1c](onboarding-guide.md#1c-alternative-provision-via-local-cli)).

   This creates:
   - VPC, subnet, security group, optional internet gateway
   - VPC endpoints (8 types for air-gapped SSM connectivity)
   - IAM roles and instance profiles for Packer-launched EC2 instances
   - KMS CMK for encrypting S3, CloudWatch, SSM, and SNS
   - S3 buckets for SSM output and compliance evidence
   - CloudWatch log group (90-day retention)
   - SSM documents (OpenSCAP scan, Windows STIG enforce, Session Manager preferences)
   - State Manager associations (STIG enforcement, scanning, inventory, patching)
   - Patch Manager baselines and maintenance windows
   - DHMC (auto-registers all EC2 instances with SSM)
   - Auto-tagging (EventBridge + Lambda propagates AMI tags to instances)

3. **Configure CI/CD** — Store AWS credentials (OIDC role ARN or static keys) and set required variables. See the [Onboarding Guide](onboarding-guide.md) for the full walkthrough.

### Day 0 Outputs

| Output | Used By |
|--------|---------|
| VPC ID, Subnet ID, Security Group ID | Packer builds |
| Instance Profile name | Packer-launched EC2 instances |
| KMS Key ARN | EBS encryption, S3 encryption |
| S3 Bucket name | SSM output, compliance evidence |

## Day 1 — Build

**Duration**: 2–5 hours per OS (see [Build Times](../../README.md#build-times))

### Steps

1. **Build Docker image** (if not already available) — Run the `offline-prepare.yml` workflow. Produces `chimera-builder-YYYYMMDD.tar.gz` (~305 MB).

2. **Run AMI builds** — Trigger the build pipeline with desired OS targets. The pipeline:
   - Builds minimal AMIs (EBS surrogate: custom LVM partitioning, OS install, AWS tooling)
   - Builds hardened AMIs (launches from minimal, applies STIG lockdown via Ansible/AWS scripts)
   - Runs compliance scans (OpenSCAP + Goss) and downloads reports as artifacts
   - Deregisters intermediate minimal AMIs after successful hardened builds

3. **Validate** — Launch an instance from the hardened AMI and run `tests/test-ssm-validation.sh` to verify SSM registration, RunCommand, and Session Manager connectivity.

4. **Distribute** — Copy AMIs to additional regions if needed (`aws_ami_regions` variable). Update launch templates or Auto Scaling groups to reference the new AMI.

### Day 1 Outputs

| Output | Location |
|--------|----------|
| Hardened AMI IDs | AWS EC2 (logged in CI/CD job summary) |
| OpenSCAP HTML report | CI/CD build artifact |
| Goss JSON delta | CI/CD build artifact |

## Day 2+ — Operate

Once hardened AMIs are in production, the SSM infrastructure handles continuous compliance automatically.

### Automated Schedules

| Activity | Schedule | Mechanism | Target |
|----------|----------|-----------|--------|
| STIG enforcement (Linux) | Every 7 days | SSM State Manager | `StigPlatform=EL8\|EL9\|AL2023` |
| STIG enforcement (Windows) | Every 7 days | SSM State Manager | `StigPlatform=Win2019\|Win2022` |
| OpenSCAP compliance scan | Every 7 days | SSM State Manager | `StigPlatform=EL*` |
| Ansible STIG check (read-only) | Every 7 days | SSM State Manager | `StigPlatform=EL*` |
| Software inventory collection | Every 12 hours | SSM State Manager | `StigManaged=true` |
| SSM Agent auto-update | Daily (3:00 AM UTC) | SSM State Manager | All instances |
| Patch scan + install | Sunday 4:00 AM UTC | Patch Manager maintenance window | Patch group members |

### Monthly AMI Refresh

Rebuild AMIs monthly (or when new STIG benchmarks or OS patches are released):

1. Increment `CHIMERA_VERSION` (e.g., `2026.04.1`)
2. Trigger the build pipeline
3. Validate new AMIs (compliance scan + SSM connectivity)
4. Update launch templates / ASGs to reference new AMI IDs
5. Rotate out old instances on next deployment cycle

See [Runbook — Monthly AMI Refresh](runbook.md#procedure-1-monthly-ami-refresh) for the full procedure.

### Compliance Evidence Collection

Evidence is generated automatically and stored for audit:

| Evidence Type | Format | Storage | Retention |
|---------------|--------|---------|-----------|
| OpenSCAP scan reports | HTML + XML | S3 `ssm-output/` prefix | S3 lifecycle policy |
| Ansible check-mode output | JSON | S3 `ssm-output/` prefix | S3 lifecycle policy |
| Goss pre/post delta | JSON | CI/CD build artifacts | 30 days (configurable) |
| SSM RunCommand logs | Text | CloudWatch log group | 90 days (configurable) |
| Session Manager recordings | Binary | S3 (KMS-encrypted) | S3 lifecycle policy |
| Patch compliance | SSM Compliance | AWS SSM console | Indefinite |

## Roles and Responsibilities

### RACI Matrix

| Activity | Platform Engineer | Security Engineer | Program ISSO |
|----------|:-:|:-:|:-:|
| Day 0 infrastructure provisioning | **R/A** | C | I |
| Docker image builds | **R/A** | I | I |
| AMI builds (monthly refresh) | **R/A** | C | I |
| STIG exception documentation | C | **R/A** | **A** |
| OpenSCAP scan review | I | **R/A** | I |
| Patch Manager configuration | **R/A** | C | I |
| Patch compliance monitoring | C | **R/A** | I |
| SSM association failure triage | **R/A** | C | I |
| New STIG benchmark integration | C | **R/A** | I |
| ATO evidence package assembly | C | **R** | **A** |
| KMS key rotation | **R/A** | C | I |
| New account/region onboarding | **R/A** | C | I |

**R** = Responsible, **A** = Accountable, **C** = Consulted, **I** = Informed

### Role Definitions

**Platform Engineer** — Owns the build pipeline, infrastructure, and AMI lifecycle. Responsible for monthly refreshes, infrastructure changes, and troubleshooting build failures.

**Security Engineer** — Owns STIG compliance posture. Reviews scan results, documents exceptions, integrates new benchmarks, and assembles ATO evidence from automated outputs.

**Program ISSO** — Accountable for ATO package completeness. Reviews exceptions, approves compensating controls, signs off on compliance evidence.

## Steady-State Monitoring

### What to Watch

| Signal | Where to Check | Action on Failure |
|--------|---------------|-------------------|
| SSM association execution | AWS SSM Console → State Manager | Check instance tags, verify AMI has required tools pre-installed |
| OpenSCAP scan score regression | S3 `ssm-output/` → HTML reports | Investigate new findings; check if upstream role changed |
| Patch compliance drift | SSM Console → Compliance | Verify maintenance window ran; check patch group membership |
| SSM Agent connectivity | SSM Console → Fleet Manager | Check VPC endpoints, instance profile, security group rules |
| CI/CD build failures | GitHub Actions / GitLab CI logs | See [Troubleshooting Guide](troubleshooting-guide.md) |
| Iron Bank token expiry | `ironbank-token-check.yml` (monthly) | Regenerate at registry1.dso.mil → User Profile → CLI Token |

### Alerting

The SSM module optionally provisions an SNS topic for alerts. Subscribe an email address or PagerDuty endpoint to receive notifications for:

- CloudWatch metric alarm triggers (e.g., failed SSM commands)
- Patch Manager compliance changes
- SSM document execution failures

Configure via `notification_email` variable in `infra/modules/ssm/variables.tf`.

## Scaling to Multiple Programs

When deploying Chimera across multiple programs or AWS accounts:

1. **One SSM infrastructure per account** — SSM resources (DHMC, associations, patch baselines) are account-wide. Run `tofu apply` once per account.
2. **Ephemeral networking per build** — VPCs and subnets are created and destroyed per build cycle (or kept persistent if preferred). Cost is minimal.
3. **Shared Docker image** — The same `chimera-builder` Docker image works across all accounts and programs. Build once, distribute to each environment.
4. **Per-program STIG customization** — Override Ansible variables via `chimera/ansible/` role defaults or add program-specific exception documentation.

See [Template Package](template-package.md) for the full adaptation guide.
