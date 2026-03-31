# STIG Exceptions and Compensating Controls

This document describes STIG (Security Technical Implementation Guide) controls that are intentionally not implemented, require compensating controls, or must be configured post-deployment for Chimera hardened AMIs.

## Overview

Chimera hardened AMIs are built using OpenSCAP with the DISA STIG profile. Due to the nature of cloud-based AMI builds, certain STIG controls cannot be applied at build time or require alternative implementations.

**Target Profile:** DISA STIG for RHEL 8 / RHEL 9 (and their clones: Oracle Linux, Rocky, Alma)  
**OpenSCAP Datastream:** `ssg-ol9-ds.xml` / `ssg-rhel9-ds.xml`

---

## Category 1: Cloud Infrastructure Exceptions

These controls are handled by the cloud provider or cannot be implemented in a cloud AMI context.

### Encrypt Partitions (`encrypt_partitions`)
- **Status:** Not Applicable
- **Reason:** AWS EBS volumes provide encryption at the infrastructure level. AMIs are built without LUKS encryption because:
  - AWS EBS encryption is enabled at volume creation time
  - LUKS would prevent AMI portability and automated deployment
  - AWS KMS provides centralized key management
- **Compensating Control:** Enable EBS encryption by default in AWS account settings or specify encrypted volumes at launch time

### GRUB Bootloader Password (`grub2_password`, `grub2_uefi_password`)
- **Status:** Not Implemented
- **Reason:** Cloud instances do not provide console access during boot. Setting a GRUB password would:
  - Prevent automated instance recovery
  - Block kernel parameter modifications needed for troubleshooting
  - Provide no security benefit since physical/console access is not available
- **Compensating Control:** AWS Instance Metadata Service (IMDSv2) controls and IAM policies protect instance configuration

### Require Single User Mode Authentication (`require_singleuser`)
- **Status:** Not Implemented
- **Reason:** Single-user mode is not accessible in cloud environments without special recovery procedures
- **Compensating Control:** AWS Systems Manager Session Manager provides secure authenticated access for recovery scenarios

---

## Category 2: Smartcard/CAC Authentication

These controls require Public Key Infrastructure (PKI) and smartcard reader hardware that must be configured post-deployment.

### Smartcard-Related Controls
| Control ID | Description | Post-Deployment Action |
|------------|-------------|------------------------|
| `sssd_enable_smartcards` | Enable smartcard authentication in SSSD | Configure SSSD with CAC/PIV settings |
| `smartcard_configure_ca` | Configure smartcard CA certificates | Import DoD/Agency CA chain |
| `smartcard_configure_cert_checking` | Enable certificate validation | Configure OCSP/CRL checking |
| `package_opensc_installed` | Install OpenSC smartcard package | Install if smartcard auth required |
| `package_pcsc-lite_installed` | Install PC/SC daemon | Install if smartcard auth required |

**Implementation Notes:**
- Smartcard authentication requires integration with an identity provider (Active Directory, FreeIPA, etc.)
- DoD environments should follow the DoD PKI implementation guide
- The `authselect` tool should be used to enable smartcard authentication profiles

---

## Category 3: GUI/Desktop Environment

These controls are marked "Not Applicable" because Chimera AMIs are server builds without a graphical interface.

### GNOME Desktop Controls
All controls prefixed with `dconf_gnome_*` are not applicable:
- `dconf_gnome_screensaver_lock_enabled`
- `dconf_gnome_session_idle_delay`
- `dconf_gnome_disable_automount`
- `dconf_gnome_screensaver_idle_delay`
- And approximately 20+ additional GNOME-related controls

**Status:** Not Applicable - No GUI installed

---

## Category 4: Post-Deployment Configuration Required

These controls require environment-specific configuration that cannot be determined at build time.

### Centralized Logging (`rsyslog_remote_tls`, `rsyslog_remote_tls_cacert`)
- **Status:** Requires Post-Deployment Configuration
- **Reason:** Log aggregation endpoints are environment-specific
- **Implementation:**
  ```bash
  # /etc/rsyslog.d/remote-tls.conf
  $DefaultNetstreamDriverCAFile /etc/pki/tls/certs/ca-bundle.crt
  $ActionSendStreamDriver gtls
  $ActionSendStreamDriverMode 1
  $ActionSendStreamDriverAuthMode x509/name
  *.* @@logs.example.com:6514
  ```

### Time Synchronization (`chronyd_or_ntpd_specify_remote_server`)
- **Status:** Configured with AWS defaults
- **Reason:** AMI uses Amazon Time Sync Service by default (`169.254.169.123`)
- **Post-Deployment:** Update `/etc/chrony.conf` if different NTP servers are required

### Banner Text (`banner_etc_issue`, `banner_etc_issue_net`, `banner_etc_motd`)
- **Status:** Generic banner installed
- **Reason:** Exact banner text varies by organization
- **Post-Deployment:** Update `/etc/issue`, `/etc/issue.net`, and `/etc/motd` with organization-specific text

---

## Category 5: Manual Verification Required

These controls are marked "notchecked" by OpenSCAP and require manual verification or cannot be automatically validated.

### File Integrity Monitoring
| Control | Description | Verification |
|---------|-------------|--------------|
| `aide_periodic_cron_checking` | AIDE runs via cron | Verify `/etc/cron.daily/aide` or systemd timer exists |
| `aide_scan_notification` | AIDE sends scan results | Configure email/syslog notification |
| `aide_verify_acls` | AIDE checks ACLs | Verify `acl` option in `/etc/aide.conf` |
| `aide_verify_ext_attributes` | AIDE checks extended attributes | Verify `xattrs` option in `/etc/aide.conf` |

### Audit Configuration
| Control | Description | Verification |
|---------|-------------|--------------|
| `audit_rules_*` | Various audit rules | Review `/etc/audit/rules.d/` |
| `auditd_data_retention_*` | Log retention settings | Review `/etc/audit/auditd.conf` |

---

## Category 6: Accepted Risk / Intentional Deviations

These controls are intentionally not implemented with documented justification.

### Home Directory Group Ownership — RHEL-08-010740 / RHEL-08-010741

- **Control IDs:** `RHEL-08-010740` (Ensure home dir group-owner matches user primary group), `RHEL-08-010741` (Ensure home dir group has no greater access than owner)
- **Status:** Disabled (set to `false` in Ansible STIG playbook vars)
- **Reason — Harmful:** System accounts (e.g., `nobody`, `dbus`, `tss`, `polkitd`) have their home directory set to `/`, `/usr/bin`, or `/usr/sbin`. These controls recursively change group ownership of those directories, breaking system binaries and potentially bricking the instance.
- **Reason — Performance:** In check mode, the RHEL8-STIG role loops over every user in `/etc/passwd`. For 7+ system accounts with `home=/`, this recursively scans the entire filesystem multiple times, causing SSM timeouts (>2 hours).
- **Scope:** EL8 only. The equivalent EL9 controls do not exhibit this behavior.

### USB Storage (`kernel_module_usb-storage_disabled`)
- **Status:** Not Disabled by Default
- **Reason:** Some cloud instances may require USB passthrough for specific use cases
- **Recommendation:** Disable in `/etc/modprobe.d/` if USB storage is not required:
  ```bash
  echo "install usb-storage /bin/true" > /etc/modprobe.d/usb-storage.conf
  ```

### IPv6 Controls
- **Status:** IPv6 enabled but hardened
- **Reason:** AWS VPCs support dual-stack networking; disabling IPv6 may break future functionality
- **Implementation:** IPv6 sysctl hardening is applied; disable IPv6 entirely only if required by policy

---

## Remediation Tracking

### Controls Recommended for Future Fixes

| Priority | Control ID | Description | Effort |
|----------|-----------|-------------|--------|
| High | `aide_build_database` | Initialize AIDE database | Low |
| High | `accounts_password_pam_*` | PAM password complexity | Medium |
| Medium | `sysctl_net_ipv6_*` | IPv6 hardening | Low |
| Medium | `file_permissions_*` | File permission fixes | Low |
| Low | `service_*_disabled` | Disable unnecessary services | Low |

---

## Compliance Reporting

Chimera AMIs use two complementary compliance scanning tools at build time:

### Goss Auditing (Ansible Lockdown)

Each STIG role (RHEL8-STIG, RHEL9-STIG, AL2023-STIG) includes a built-in Goss
audit framework from [Ansible Lockdown](https://github.com/ansible-lockdown).
Goss scans run automatically before and after remediation when `setup_audit`,
`run_audit`, and `fetch_audit_output` are enabled, producing JSON reports that
document the delta between pre- and post-hardening compliance posture.

The role handles all setup (downloading the Goss binary, cloning audit content
from GitHub) via its defaults (`get_audit_binary_method: download`,
`audit_content: git`). For air-gapped environments, set the `chimera_goss_binary_url`
Packer variable to an internal mirror URL; when set, the build injects
`audit_binary` and `get_audit_binary_checksum: false` into the role's extra vars.

> **Note:** Goss auditing is **disabled** for SSM check-mode runs
> (`setup_audit: false`, `run_audit: false`, `fetch_audit_output: false` in the
> SSM `site.yml`). The RHEL\*-STIG roles' post-audit tasks use
> `ansible.builtin.command` to invoke Goss, which is skipped in Ansible's
> `--check` mode, but the subsequent `"Ensure audit files readable"` file task
> still executes and fails when the (never-created) post-scan JSON is absent.
> This is an upstream check-mode incompatibility. Post-deployment compliance
> verification relies on **OpenSCAP** instead (see below).

### OpenSCAP

After Ansible Lockdown completes, an OpenSCAP scan runs using the DISA STIG
profile from the SCAP Security Guide (`scap-security-guide` RPM). This produces
an HTML report and XML results file at `/tmp/oscap-report.html` and
`/tmp/oscap-results.xml`, which are downloaded as build artifacts.

When generating compliance reports post-deployment, use the following command to
exclude known exceptions:

```bash
oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_stig \
  --skip-rule xccdf_org.ssgproject.content_rule_encrypt_partitions \
  --skip-rule xccdf_org.ssgproject.content_rule_grub2_password \
  --skip-rule xccdf_org.ssgproject.content_rule_grub2_uefi_password \
  --skip-rule xccdf_org.ssgproject.content_rule_require_singleuser \
  --results results.xml \
  --report report.html \
  /usr/share/xml/scap/ssg/content/ssg-ol9-ds.xml
```

---

## Document History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-02-02 | 1.0 | Chimera Team | Initial documentation |

---

## References

- [DISA STIG Viewer](https://public.cyber.mil/stigs/)
- [OpenSCAP Documentation](https://www.open-scap.org/documentation/)
- [SCAP Security Guide](https://github.com/ComplianceAsCode/content)
- [AWS Security Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [AWS EBS Encryption](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html)
