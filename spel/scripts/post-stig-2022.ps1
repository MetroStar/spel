# Post-STIG script for Windows Server 2022
# This script is uploaded BEFORE STIG and executed AFTER STIG completes
# It runs in background mode to avoid WinRM session issues
# Includes Sysprep execution (EC2Launch v2 requires manual Sysprep call)

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
Write-Log "=== POST-STIG: EC2 Network, Cleanup, and Sysprep (Windows 2022) ==="

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

    # STEP 3: Run Cleanup Script (includes DISM operations which may take 5-10 minutes)
    Write-Log "Step 3: Running cleanup script (full mode with DISM)..."
    if (Test-Path 'C:\Windows\Temp\cleanup-sysprep.ps1') {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        & 'C:\Windows\Temp\cleanup-sysprep.ps1' -SkipSysprep 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log "  Cleanup script completed"
    } else {
        Write-Log "  WARNING: cleanup-sysprep.ps1 not found"
    }

    # STEP 4: EC2Launch v2 Reset
    Write-Log "Step 4: Running EC2Launch v2 reset..."
    $ec2LaunchV2 = 'C:\Program Files\Amazon\EC2Launch\ec2launch.exe'
    if (Test-Path $ec2LaunchV2) {
        & $ec2LaunchV2 reset --block 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log "  EC2Launch v2 reset completed"
    } else {
        Write-Log "  WARNING: EC2Launch v2 not found at $ec2LaunchV2"
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

    Write-Log "=== POST-STIG: Complete. Running Sysprep... ==="

    # Create marker file to signal completion to Packer (before Sysprep shuts down)
    $markerFile = 'C:\Windows\Temp\post-stig-complete.marker'
    New-Item -Path $markerFile -ItemType File -Force | Out-Null
    Write-Log "Created completion marker: $markerFile"

    # STEP 6: Run Sysprep (Windows 2022 with EC2Launch v2)
    Write-Log "Step 6: Running Sysprep..."
    
    # Remove the scheduled task before sysprep
    Unregister-ScheduledTask -TaskName "PostSTIG" -Confirm:$false -ErrorAction SilentlyContinue
    
    $sysprepPath = "$env:SystemRoot\System32\Sysprep\Sysprep.exe"
    if (Test-Path $sysprepPath) {
        Write-Log "  Starting Sysprep.exe (will shutdown instance)..."
        # Use Start-Process without -Wait so we can log before shutdown
        Start-Process -FilePath $sysprepPath -ArgumentList '/generalize /oobe /shutdown /quiet' -NoNewWindow
        Write-Log "  Sysprep started. Instance will shutdown shortly."
    } else {
        Write-Log "  ERROR: Sysprep.exe not found at $sysprepPath"
    }

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
}

Write-Log "Script completed."
