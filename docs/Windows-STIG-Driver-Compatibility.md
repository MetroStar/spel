# Windows STIG Driver Compatibility Analysis

## Overview

This document identifies STIG controls that may affect driver installation and Windows boot compatibility on AWS Nitro instances.

## Critical AWS Drivers

The following drivers are essential for booting on AWS Nitro-based instances:

| Driver | Purpose | Impact if Missing |
| -------- | --------- | ------------------- |
| ENA (Elastic Network Adapter) | Network connectivity on Nitro | Instance unreachable |
| NVMe / stornvme | Storage access on Nitro | Boot failure (inaccessible boot device) |
| AWSNVMe | AWS-specific NVMe extensions | May cause boot issues |

## STIG Controls That May Affect Drivers

### Device Installation Restrictions

**V-225060 / WN16-CC-000260** - Device Installation: Prevent installation of devices not described by other policy settings

- **Risk**: May block new hardware during first boot on different instance type
- **Registry**: `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs`
- **Mitigation**: Ensure AWS device IDs are not blocked

**V-225061 / WN16-CC-000270** - Device Installation: Prevent installation of devices using drivers that match device setup classes

- **Risk**: May block driver installation by device class GUID
- **Registry**: `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceClasses`
- **Mitigation**: AWS drivers use standard device classes, should not be affected

### Code Signing Requirements

**V-225048 / WN16-CC-000140** - Driver signing: Block installation of unsigned drivers

- **Risk**: AWS drivers should be signed by Amazon/Microsoft, no issue expected
- **Mitigation**: None needed, AWS drivers are properly signed

**V-225049 / WN16-CC-000150** - Kernel-mode drivers must be signed

- **Risk**: Same as above
- **Mitigation**: None needed

### Windows Update / Feature Restrictions

**V-225225 / WN16-CC-000560** - Users must be prevented from changing installation options

- **Risk**: Low for AMI creation
- **Mitigation**: None needed

## Instance Type Compatibility Matrix

| Nitro Generation | Instance Types | Driver Requirements |
| --- | --- | --- |
| Gen 1 | t3, m5, c5, r5 | ENA + NVMe (basic) |
| Gen 2 | m6i, c6i, r6i | ENA + NVMe (enhanced) |
| Gen 3 | m7i, c7i, r7i | ENA + NVMe (latest) |

## Verification Steps

1. **Pre-Build**: Run `Get-WindowsDriver -Online -All | Where-Object { $_.OriginalFileName -like '*ena*' -or $_.OriginalFileName -like '*nvme*' }`

2. **Post-STIG**: Windows STIG enforcement uses a custom wrapper document (`WindowsSTIGEnforce`) around the AWS-managed `AWSEC2-ConfigureSTIG`. The wrapper adds a post-STIG step that restores the built-in admin rename (SID-500 → `maintuser`), which `AWSEC2-ConfigureSTIG` resets via Local Security Policy. Check SSM RunCommand output and `C:\ProgramData\Amazon\SSM\Logs` for STIG application results.

3. **Test AMI**: Verify boot across Nitro generations by launching the AMI on t3, m6i, and m7i instance types

## Registry Keys to Check

```powershell
# Device Installation Restrictions
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions" -ErrorAction SilentlyContinue

# Driver Signing
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Driver Signing" -ErrorAction SilentlyContinue

# Code Integrity
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -ErrorAction SilentlyContinue
```

## Troubleshooting Boot Failures

1. **Get Console Output**: `aws ec2 get-console-output --instance-id i-xxx`
2. **Get Screenshot**: `aws ec2 get-console-screenshot --instance-id i-xxx`
3. **Look for**:
   - "INACCESSIBLE_BOOT_DEVICE" = Missing NVMe driver
   - No network connectivity = Missing ENA driver
   - BSOD with DRIVER_IRQL_NOT_LESS_OR_EQUAL = Driver compatibility issue

## Recommended Testing

After any STIG changes, test the AMI on at least:

- `t3.medium` (Nitro Gen 1 baseline)
- `m6i.large` (Nitro Gen 2)
- `m7i.large` (Nitro Gen 3, if available)

If Gen 1 works but Gen 2/3 fails, the issue is likely driver-related.
