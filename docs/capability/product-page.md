# STIG-Hardened AMIs. Automated. Air-Gap Ready. Mission-Deployed.

## Compliance isn't a post-deployment problem. It's a build-time guarantee. Crucible delivers both.

---

## Introducing Crucible:

## Automated STIG Compliance for Enterprise Cloud Infrastructure

Crucible is a fully automated platform that builds DISA STIG-hardened Amazon Machine Images across 9 operating systems — from RHEL and Oracle Linux to Windows Server — and enforces continuous compliance post-deployment through AWS Systems Manager.

Rather than relying on manual hardening scripts, ad-hoc scanning, or months of security engineering per OS, Crucible packages the entire STIG lifecycle — partitioning, hardening, scanning, evidence generation, and ongoing enforcement — into an unattended CI/CD pipeline that runs in connected and air-gapped AWS environments.

Designed for GovCloud and IL environments where internet access is restricted and compliance timelines are non-negotiable, Crucible ships as a self-contained Docker image with all dependencies baked in. Transfer it to any network. Build hardened AMIs in hours, not months.

---

**95% Faster** — First Hardened AMI in 4–6 Hours

**1,500–3,000+** — Engineer-Hours Saved Annually Per Program

**100% Automated** — Monthly Compliance Verification

---

## The Real Challenge

ATO timelines slip when STIG hardening is manual, undocumented, or inconsistent across operating systems. Crucible eliminates the gap between security requirements and operational delivery.

##### Fragmented Hardening Across OS Targets

##### One Pipeline, 9 Operating Systems — Linux and Windows STIGed from the Same Automation

##### Manual Compliance Evidence Collection

##### Automated OpenSCAP Scanning, Goss Auditing, and Audit-Ready Artifacts in S3

##### Air-Gapped Environments Block Standard Tooling

##### Self-Contained Docker Image with Offline Delivery — No Internet Required at Build Time

##### Compliance Drift Between Monthly Scans

##### Continuous STIG Enforcement via SSM State Manager — Every 7 Days, Unattended

##### Weeks-Long Onboarding for New Teams

##### New Delivery Team to First Hardened AMI in 2–3 Days with Documented Runbooks and Templates

---

## Platform Support

| Linux | Windows |
|-------|---------|
| RHEL 9, RHEL 8 | Windows Server 2019 |
| Oracle Linux 9, Oracle Linux 8 | Windows Server 2022 |
| Rocky Linux 9, Alma Linux 9 | |
| Amazon Linux 2023 | |

---

## Who Crucible Supports

##### Cloud Engineers & Platform Teams

Provision infrastructure, build hardened AMIs, and manage the monthly refresh cycle — all through CI/CD with documented runbooks.

##### Security Engineers & ISSOs

Review automated OpenSCAP and Goss scan results, maintain STIG exception documentation, and assemble ATO evidence packages from pre-generated artifacts.

##### Program Managers & Capture Teams

Reduce ATO schedule risk with a proven, reusable capability. Quantified ROI and NIST 800-53 control mapping ready for proposals.

##### System Integrators & Delivery Teams

Fork the platform, customize variables for your program, and deploy to new accounts or regions — connected or air-gapped — using documented templates and pre-flight checklists.

---

## How It Works

Crucible's two-phase Packer pipeline runs inside a portable Docker container — the same image works in GitHub Actions, GitLab CI, or a local workstation.

##### Build

CI/CD automatically provisions AWS infrastructure (VPC, IAM, KMS, SSM) via OpenTofu, then builds minimal AMIs with STIG-compliant LVM partitioning and hardens them with Ansible STIG roles — producing compliance-scanned AMIs with zero manual intervention.

##### Enforce

Post-deployment, SSM State Manager associations re-apply STIG hardening every 7 days, run OpenSCAP scans, patch instances on schedule, and store all evidence in encrypted S3 — automatically.

##### Deliver

The entire platform ships as a ~378 MB Docker tarball. Transfer it via SCP, USB, or secure file share. VPC endpoints provide private AWS API connectivity. No internet access required at build or run time.

---

## Results + Impact

| Metric | Without Crucible | With Crucible | Reduction |
|--------|----------------|--------------|-----------|
| First hardened AMI (1 OS) | 80–120 engineer-hours | 4–6 hours | ~95% |
| Full platform (9 OS) | 720–1,080 hours | 36–54 hours | ~95% |
| Monthly compliance verification | 72–144 hours/month | 0 (automated) | 100% |
| New team onboarding | 2–4 weeks | 2–3 days | ~85% |
| ATO evidence collection | 180–360 hours | 8–16 hours | ~95% |

---

## Bring Crucible to Your Program

Whether you're standing up a new GovCloud environment, hardening AMIs for an active ATO, or packaging infrastructure for a proposal, Crucible is ready to deploy. MetroStar's Innovation Lab team can help you adapt, scale, and operationalize it for your mission.

[Request A Demo](https://www.metrostar.com/contact-us/)
