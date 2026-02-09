# Post-STIG Cleanup and Sysprep Script
# This script runs as fire-and-forget after STIG hardening completes.
# It handles WinRM restoration, EC2 networking, cleanup, and sysprep
# all in one atomic operation so we don't need multiple Ansible tasks.

$ErrorActionPreference = "Continue"
$LogFile = "C:\Windows\Temp\post-stig-cleanup.log"

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFile
    Write-Host "$Timestamp - $Message"
}

Write-Log "Starting post-STIG cleanup script"

# ============================================================================
# SECTION 1: Restore EC2 Network Functionality
# ============================================================================
Write-Log "Restoring EC2 network functionality..."

try {
    # Create firewall rule for EC2 Instance Metadata Service (IMDS)
    $imdsRule = Get-NetFirewallRule -DisplayName "Allow EC2 IMDS" -ErrorAction SilentlyContinue
    if (-not $imdsRule) {
        New-NetFirewallRule -DisplayName "Allow EC2 IMDS" `
            -Direction Outbound `
            -RemoteAddress 169.254.169.254 `
            -Protocol TCP `
            -RemotePort 80 `
            -Action Allow `
            -Profile Any `
            -ErrorAction Stop
        Write-Log "Created IMDS firewall rule"
    }

    # Create firewall rule for DNS
    $dnsRule = Get-NetFirewallRule -DisplayName "Allow DNS Outbound" -ErrorAction SilentlyContinue
    if (-not $dnsRule) {
        New-NetFirewallRule -DisplayName "Allow DNS Outbound" `
            -Direction Outbound `
            -Protocol UDP `
            -RemotePort 53 `
            -Action Allow `
            -Profile Any `
            -ErrorAction Stop
        Write-Log "Created DNS firewall rule"
    }

    # Create firewall rule for HTTP/HTTPS (needed for Windows Update, etc.)
    $httpRule = Get-NetFirewallRule -DisplayName "Allow HTTP/HTTPS Outbound" -ErrorAction SilentlyContinue
    if (-not $httpRule) {
        New-NetFirewallRule -DisplayName "Allow HTTP/HTTPS Outbound" `
            -Direction Outbound `
            -Protocol TCP `
            -RemotePort 80,443 `
            -Action Allow `
            -Profile Any `
            -ErrorAction Stop
        Write-Log "Created HTTP/HTTPS firewall rule"
    }

    # Ensure DHCP client is running
    $dhcpService = Get-Service -Name Dhcp -ErrorAction SilentlyContinue
    if ($dhcpService -and $dhcpService.Status -ne 'Running') {
        Set-Service -Name Dhcp -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name Dhcp -ErrorAction SilentlyContinue
        Write-Log "Started DHCP client service"
    }

    Write-Log "EC2 network restoration complete"
} catch {
    Write-Log "Warning during EC2 network restoration: $_"
}

# ============================================================================
# SECTION 2: Run cleanup-sysprep.ps1 if it exists
# ============================================================================
Write-Log "Running cleanup-sysprep.ps1..."

$cleanupScript = "C:\Windows\Temp\cleanup-sysprep.ps1"
if (Test-Path $cleanupScript) {
    try {
        & $cleanupScript 2>&1 | ForEach-Object { Write-Log "cleanup-sysprep: $_" }
        Write-Log "cleanup-sysprep.ps1 completed"
    } catch {
        Write-Log "Warning during cleanup-sysprep.ps1: $_"
    }
} else {
    Write-Log "cleanup-sysprep.ps1 not found, skipping"
}

# ============================================================================
# SECTION 3: Create SetupComplete.cmd for first-boot tasks
# ============================================================================
Write-Log "Creating SetupComplete.cmd..."

$setupCompleteDir = "C:\Windows\Setup\Scripts"
$setupCompleteFile = "$setupCompleteDir\SetupComplete.cmd"

try {
    if (-not (Test-Path $setupCompleteDir)) {
        New-Item -ItemType Directory -Path $setupCompleteDir -Force | Out-Null
    }

    # Create SetupComplete.cmd that runs on first boot after sysprep
    @"
@echo off
REM SetupComplete.cmd - Runs on first boot after sysprep
REM Re-enable WinRM and restart SSM Agent for post-deployment readiness

REM Wait for network to be ready
ping -n 30 127.0.0.1 > nul

REM Restart SSM Agent to pick up new instance identity after Sysprep
net stop AmazonSSMAgent 2>nul
net start AmazonSSMAgent 2>nul

REM Enable WinRM
winrm quickconfig -force -q
netsh advfirewall firewall add rule name="WinRM HTTPS" protocol=TCP dir=in localport=5986 action=allow

REM Log completion
echo %date% %time% - SetupComplete.cmd finished >> C:\Windows\Temp\SetupComplete.log
"@ | Out-File -FilePath $setupCompleteFile -Encoding ASCII -Force

    Write-Log "SetupComplete.cmd created at $setupCompleteFile"
} catch {
    Write-Log "Warning creating SetupComplete.cmd: $_"
}

# ============================================================================
# SECTION 4: Run EC2Launch Sysprep
# ============================================================================
Write-Log "Preparing for sysprep..."

# Give a moment for any pending operations to complete
Start-Sleep -Seconds 5

# Determine which EC2Launch version is available
$ec2LaunchV2 = "C:\Program Files\Amazon\EC2Launch\ec2launch.exe"
$ec2LaunchV1 = "$env:ProgramData\Amazon\EC2-Windows\Launch\Scripts\SysprepInstance.ps1"

Write-Log "Checking for EC2Launch..."

if (Test-Path $ec2LaunchV2) {
    Write-Log "Found EC2Launch v2, running sysprep with shutdown..."
    try {
        # EC2Launch v2 (Windows 2022) - must use --shutdown to shutdown after sysprep
        # Run synchronously since we want the shutdown to happen
        & $ec2LaunchV2 sysprep --shutdown 2>&1 | ForEach-Object { Write-Log "ec2launch: $_" }
        Write-Log "EC2Launch v2 sysprep completed (shutdown should be imminent)"
    } catch {
        Write-Log "Error during EC2Launch v2 sysprep: $_"
        # Fallback: try to shutdown manually
        Write-Log "Attempting manual shutdown..."
        Stop-Computer -Force
    }
} elseif (Test-Path $ec2LaunchV1) {
    Write-Log "Found EC2Launch v1, running sysprep..."
    try {
        # EC2Launch v1 (Windows 2016/2019) - SysprepInstance.ps1 should shutdown by default
        # Run synchronously to ensure it completes
        & powershell.exe -ExecutionPolicy Bypass -File $ec2LaunchV1 2>&1 | ForEach-Object { Write-Log "ec2launch: $_" }
        Write-Log "EC2Launch v1 sysprep completed (shutdown should be imminent)"
    } catch {
        Write-Log "Error during EC2Launch v1 sysprep: $_"
        # Fallback: try to shutdown manually
        Write-Log "Attempting manual shutdown..."
        Stop-Computer -Force
    }
} else {
    Write-Log "ERROR: No EC2Launch found! Attempting direct sysprep..."
    Write-Log "Checked paths:"
    Write-Log "  - $ec2LaunchV2"
    Write-Log "  - $ec2LaunchV1"
    # Last resort: run sysprep directly
    try {
        & C:\Windows\System32\Sysprep\sysprep.exe /oobe /generalize /shutdown /quiet
        Write-Log "Direct sysprep initiated"
    } catch {
        Write-Log "Direct sysprep failed: $_"
        Stop-Computer -Force
    }
}

Write-Log "Post-STIG cleanup script completed. Sysprep should be running."
Write-Log "The system will shut down shortly for image capture."
Write-Log "The system will shut down shortly for image capture."
