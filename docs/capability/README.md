# Chimera Platform — Capability Package

Automated STIG-hardened AMI builds with air-gapped delivery and continuous compliance for AWS GovCloud and commercial environments.

The Chimera Platform is a reusable capability that produces DISA STIG-compliant Amazon Machine Images for 9 operating systems. It automates the full lifecycle — infrastructure provisioning, image hardening, compliance evidence generation, and post-deployment enforcement — through CI/CD pipelines that work in both connected and disconnected (air-gapped) AWS environments.

This directory contains all documentation needed to evaluate, adopt, operate, and extend the platform.

## Quick Start

**New to this?** Follow the [Onboarding Guide](onboarding-guide.md) — zero to first hardened AMI in 4–6 hours.

**Evaluating for a capture?** Start with the [Capability Summary](capability-summary.md) and [Value Brief](value-brief.md).

## Capability Assets

| Document | Description | Audience |
|----------|-------------|----------|
| [Capability Summary](capability-summary.md) | Self-contained one-pager suitable for email distribution | Delivery leads, capture managers |
| [Reference Architecture](reference-architecture.md) | Architecture diagrams, component map, security boundaries, platform support matrix | Solutions architects, proposals |
| [Operating Model](operating-model.md) | Day 0/1/2+ lifecycle, RACI matrix, automated schedules, monitoring guidance | Platform engineers, ISSOs |
| [Onboarding Guide](onboarding-guide.md) | Step-by-step walkthrough: prerequisites → infrastructure → first build → validation | New delivery teams |
| [Runbook](runbook.md) | 8 operational procedures: monthly refresh, new STIG benchmarks, add OS, KMS rotation, etc. | Operations engineers |
| [Troubleshooting Guide](troubleshooting-guide.md) | Decision-tree diagnosis for build, infrastructure, SSM, and air-gapped failures | All practitioners |
| [Template Package](template-package.md) | Configuration reference, infrastructure customization, pipeline adaptation, storage planning | New program setup |
| [Value Brief](value-brief.md) | Quantified ROI (~1,500–3,000 hrs/yr saved), NIST 800-53 mapping, proposal talking points | Capture teams, proposals |

## Supporting References

These existing documents provide deep technical detail. The capability assets above link into them where appropriate.

| Document | Description |
|----------|-------------|
| [CI-CD-Setup](../CI-CD-Setup.md) | Full IAM policies, OIDC setup, and pipeline configuration for GitHub Actions and GitLab CI |
| [Manual-SSM-Setup](../Manual-SSM-Setup.md) | AWS CLI commands to provision SSM infrastructure without OpenTofu |
| [STIG Exceptions](../STIG_EXCEPTIONS.md) | Controls intentionally skipped with compensating controls and justification |
| [Windows-STIG-Driver-Compatibility](../Windows-STIG-Driver-Compatibility.md) | Nitro driver compatibility notes for Windows STIG hardening |
| [Infrastructure README](../../infra/README.md) | OpenTofu module reference (inputs, outputs, quickstart) |
| [SSM Module README](../../infra/modules/ssm/README.md) | SSM module detail: documents, associations, patching, DHMC, auto-tagging |

## Maintenance

These documents reference actual file paths, variable names, and commands from the codebase. When making changes to the build pipeline or infrastructure:

1. Verify that referenced file paths still exist
2. Update variable names or defaults if they change
3. Review the platform support matrix when adding or removing OS targets
4. Update the value brief if the capability scope changes significantly

**Ownership**: The platform engineering team owns these documents. Review quarterly or when the codebase changes materially.
