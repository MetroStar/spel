# Post-STIG script for Windows Server 2016/2019
# This script is uploaded BEFORE STIG and executed AFTER STIG completes
# It runs in background mode to avoid WinRM session issues

param(
    [switch]$Background
)

$logFile = "C:\PostSTIG.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Add-Content -Path $logFile
    Write-Host "$timestamp - $Message"
}

# If -Background is specified, relaunch ourselves as a background job
if ($Background) {
    Write-Log "Starting post-STIG script in background mode..."
    
    # Create a scheduled task to run this script immediately without -Background
    $scriptPath = $MyInvocation.MyCommand.Path
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask -TaskName "PostSTIG" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    
    Write-Log "Scheduled task created. Script will run in 5 seconds."
    return
}

# Main execution
Write-Log "=== POST-STIG: EC2 Network, Cleanup, and Sysprep ==="

try {
    # STEP 1: Disable Firewall (to ensure any network services work)
    Write-Log "Step 1: Disabling Windows Firewall..."
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -ErrorAction SilentlyContinue
    Write-Log "  Firewall disabled"

    # STEP 2: Restore EC2 Network Functionality
    Write-Log "Step 2: Restoring EC2 network functionality..."
    
    # DHCP
    Set-Service -Name 'Dhcp' -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name 'Dhcp' -ErrorAction SilentlyContinue
    Write-Log "  DHCP service configured"
    
    # Enable DHCP on network adapters
    Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | ForEach-Object { 
        Set-NetIPInterface -InterfaceIndex $_.ifIndex -Dhcp Enabled -ErrorAction SilentlyContinue 
    }
    Write-Log "  DHCP enabled on network adapters"
    
    # AWS Services
    @('AmazonSSMAgent', 'EC2Config', 'EC2Launch', 'AmazonCloudWatchAgent') | ForEach-Object { 
        if (Get-Service -Name $_ -ErrorAction SilentlyContinue) { 
            Set-Service -Name $_ -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name $_ -ErrorAction SilentlyContinue
            Write-Log "  Service $_ configured"
        } 
    }

    # STEP 3: Run Cleanup Script
    Write-Log "Step 3: Running cleanup script..."
    if (Test-Path 'C:\Windows\Temp\cleanup-sysprep.ps1') {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        & 'C:\Windows\Temp\cleanup-sysprep.ps1' -SkipSysprep 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log "  Cleanup script completed"
    } else {
        Write-Log "  WARNING: cleanup-sysprep.ps1 not found"
    }

    # STEP 4: EC2Launch v1 Sysprep Prep
    Write-Log "Step 4: Running EC2Launch v1 sysprep prep..."
    $ec2LaunchPath = "$env:ProgramData\Amazon\EC2-Windows\Launch\Scripts"
    if (Test-Path "$ec2LaunchPath\InitializeInstance.ps1") {
        & "$ec2LaunchPath\InitializeInstance.ps1" -Schedule 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log "  InitializeInstance.ps1 completed"
    }
    if (Test-Path "$ec2LaunchPath\SysprepInstance.ps1") {
        & "$ec2LaunchPath\SysprepInstance.ps1" -NoShutdown 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log "  SysprepInstance.ps1 completed"
    }

    # STEP 5: Copy SetupComplete.cmd (AFTER EC2Launch runs to avoid it being overwritten)
    Write-Log "Step 5: Installing SetupComplete.cmd..."
    New-Item -Path 'C:\Windows\Setup\Scripts' -ItemType Directory -Force | Out-Null
    if (Test-Path 'C:\Windows\Temp\SetupComplete.cmd') {
        Copy-Item -Path 'C:\Windows\Temp\SetupComplete.cmd' -Destination 'C:\Windows\Setup\Scripts\SetupComplete.cmd' -Force
        Write-Log "  SetupComplete.cmd installed"
    } else {
        Write-Log "  WARNING: SetupComplete.cmd not found in Temp"
    }

    # Verify the copy
    if (Test-Path 'C:\Windows\Setup\Scripts\SetupComplete.cmd') {
        Write-Log "  Verified: SetupComplete.cmd exists in Scripts folder"
    } else {
        Write-Log "  ERROR: SetupComplete.cmd NOT in Scripts folder!"
    }

    Write-Log "=== POST-STIG: Complete. Packer will stop the instance. ==="

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
}

# Remove the scheduled task if it exists
Unregister-ScheduledTask -TaskName "PostSTIG" -Confirm:$false -ErrorAction SilentlyContinue

# Create marker file to signal completion to Packer
$markerFile = 'C:\Windows\Temp\post-stig-complete.marker'
New-Item -Path $markerFile -ItemType File -Force | Out-Null
Write-Log "Created completion marker: $markerFile"

Write-Log "Script completed successfully."
