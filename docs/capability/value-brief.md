# Value Brief

> **Chimera Platform** — Quantified return on investment for automated STIG AMI builds and continuous compliance.

## The Problem

Federal and DoD programs spend hundreds of engineer-hours per operating system manually hardening images, collecting compliance evidence, and maintaining STIG posture. Each new program starts from scratch. Knowledge is siloed, onboarding takes weeks, and compliance is verified point-in-time rather than continuously.

## The Solution

The Chimera Platform automates the entire STIG AMI lifecycle — from infrastructure provisioning through image hardening to post-deployment enforcement — across 9 operating systems in both connected and air-gapped AWS environments.

## Value Quantification

Estimates are based on industry benchmarks: DISA STIG benchmarks contain 300–500 controls per OS, manual remediation averages 10–15 minutes per control, and evidence collection requires screenshot/export documentation per control.

### Per-Activity Savings

| Activity | Manual Baseline | With Chimera | Savings | How |
|----------|----------------|--------------|---------|-----|
| **Initial STIG hardening** (1 OS) | 80–120 hrs | 4–6 hrs | **~95%** | Automated Ansible Lockdown roles apply 300–500 controls unattended |
| **Full platform standup** (9 OS) | 720–1,080 hrs | 36–54 hrs | **~95%** | Same automation, parallelized across OS targets |
| **Environment setup** (VPC, IAM, SSM, patching) | 40–60 hrs | 1–2 hrs | **~97%** | Single `tofu apply` creates all infrastructure |
| **Monthly compliance verification** (9 OS) | 72–144 hrs/mo | 0 hrs/mo | **100%** | SSM State Manager runs STIG enforcement + OpenSCAP scans on schedule |
| **ATO evidence collection** | 180–360 hrs | 8–16 hrs | **~95%** | OpenSCAP HTML/XML + Goss JSON reports generated automatically to S3 |
| **New team onboarding** | 80–160 hrs (2–4 weeks) | 16–24 hrs (2–3 days) | **~85%** | Structured onboarding guide, runbook, and troubleshooting guide |
| **Knowledge transfer** | Tribal knowledge (undocumented) | Codified (8 operational documents) | **N/A** | Documented architecture, procedures, and decision trees |

### Manual Steps Removed

| Manual Step | Automated By |
|-------------|-------------|
| Partition disks per STIG filesystem requirements | AMIgen `DiskSetup.sh` — 7 LVM volumes with STIG-compliant mount options |
| Install and configure OS packages | AMIgen `OSpackages.sh` — ~200 packages from manifest |
| Apply 300–500 STIG controls per OS | Ansible Lockdown roles (Linux) / `AWSEC2-ConfigureSTIG` (Windows) |
| Generate compliance scan reports | OpenSCAP + Goss — HTML, XML, JSON reports as build artifacts |
| Upload evidence to S3 | SSM associations — automatic output to S3 with KMS encryption |
| Configure SSM, patching, and Session Manager | OpenTofu SSM module — documents, associations, baselines, DHMC |
| Tag instances for STIG enforcement targeting | EventBridge + Lambda — AMI tags auto-propagate to instances |
| Verify FIPS 140-2 boot integrity (EL8) | `boot-fips-wrapper.sh` — pre/post role validation of `boot=UUID` |
| Restore Windows admin rename after STIG | Custom SSM document — wraps `AWSEC2-ConfigureSTIG` with `secedit` fix |
| Transfer build tools to air-gapped environments | Docker image — single ~305 MB tarball with all dependencies |

### Annualized Value Per Program

| Scenario | Year 1 Savings | Ongoing Annual Savings |
|----------|---------------|----------------------|
| **Single OS** (e.g., RHEL 9 only) | 300–500 hrs | 100–200 hrs/yr |
| **Full platform** (9 OS targets) | 1,500–3,000 hrs | 900–1,700 hrs/yr |
| **Multi-account** (3 accounts × 9 OS) | 3,000–6,000 hrs | 2,700–5,100 hrs/yr |

Year 1 includes initial setup, first build cycle, and ATO evidence. Ongoing includes monthly refreshes, compliance verification, and patching.

### Onboarding Time Reduction

| Metric | Without Chimera | With Chimera |
|--------|----------------|--------------|
| Time to first hardened AMI | 2–4 weeks | 4–6 hours |
| Time to production-ready compliance pipeline | 4–8 weeks | 1–2 days |
| New engineer ramp-up | 2–4 weeks | 2–3 days |
| Cross-program reuse effort | Rebuild from scratch | Fork + customize (hours) |

## NIST 800-53 Control Coverage

The platform directly supports the following NIST 800-53 control families, which map to common ATO requirements:

| Control | Title | How Chimera Supports It |
|---------|-------|------------------------|
| **CM-6** | Configuration Settings | STIG hardening applied at build time; drift correction via SSM enforcement |
| **CM-2** | Baseline Configuration | AMIs serve as immutable baselines; rebuilt monthly from code |
| **SI-2** | Flaw Remediation | Patch Manager with automated baselines and maintenance windows |
| **RA-5** | Vulnerability Monitoring | Scheduled OpenSCAP scans with DISA STIG profiles |
| **AC-2** | Account Management | Admin rename enforcement (`maintuser`); Session Manager with audit logging |
| **SC-28** | Protection of Information at Rest | KMS CMK encryption for EBS, S3, CloudWatch, SSM sessions |
| **SC-12** | Cryptographic Key Management | KMS key rotation support; FIPS 140-2 enabled on all Linux builds |
| **AU-6** | Audit Record Review | CloudWatch log group with 90-day retention; S3 compliance evidence |
| **SC-10** | Network Disconnect | Session Manager 20-minute idle timeout (STIG AC-12 / SC-10) |

## Proposal Talking Points

For capture teams and proposal writers:

- **Accelerated ATO timeline** — Compliance evidence is generated automatically during every build. ATO package assembly drops from weeks to hours.
- **Continuous compliance** — STIG enforcement runs on a 7-day cycle, not just at build time. Drift is detected and corrected automatically.
- **Air-gapped from Day 1** — The platform was designed for disconnected GovCloud and IL environments. No internet access required at build time.
- **9 operating systems, one pipeline** — Consistent hardening approach across RHEL, Oracle Linux, Rocky, Alma, Amazon Linux, and Windows Server.
- **Reusable across programs** — Fork the repo, customize variables, and build. No re-engineering required.
- **Codified knowledge** — Architecture, procedures, and troubleshooting are documented. Team transitions don't lose institutional knowledge.
- **Proven technology stack** — Built on Packer, Ansible, OpenTofu, and AWS Systems Manager. No proprietary dependencies.
