# Post-STIG script for Windows Server 2019
# This script is uploaded BEFORE STIG and executed AFTER STIG completes
# It runs in background mode to avoid WinRM session issues
# Includes Sysprep execution with shutdown for reliable instance-state polling

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
    # STEP 1: Configure targeted firewall rules (keep firewall enabled for STIG compliance)
    Write-Log "Step 1: Configuring targeted firewall rules..."

    # Allow EC2 Instance Metadata Service (IMDS) — required for identity, credentials, userdata
    if (-not (Get-NetFirewallRule -DisplayName "Allow EC2 IMDS" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "Allow EC2 IMDS" `
            -Direction Outbound -RemoteAddress 169.254.169.254 `
            -Protocol TCP -RemotePort 80 `
            -Action Allow -Profile Any -ErrorAction SilentlyContinue
        Write-Log "  Created IMDS firewall rule"
    }

    # Allow DNS — required for name resolution
    if (-not (Get-NetFirewallRule -DisplayName "Allow DNS Outbound" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "Allow DNS Outbound" `
            -Direction Outbound -Protocol UDP -RemotePort 53 `
            -Action Allow -Profile Any -ErrorAction SilentlyContinue
        Write-Log "  Created DNS firewall rule"
    }

    # Allow HTTP/HTTPS — required for SSM agent, Windows Update, package downloads
    if (-not (Get-NetFirewallRule -DisplayName "Allow HTTP/HTTPS Outbound" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "Allow HTTP/HTTPS Outbound" `
            -Direction Outbound -Protocol TCP -RemotePort 80,443 `
            -Action Allow -Profile Any -ErrorAction SilentlyContinue
        Write-Log "  Created HTTP/HTTPS firewall rule"
    }

    # Ensure firewall stays enabled (STIG-compliant)
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue
    Write-Log "  Firewall configured with targeted rules (remains enabled)"

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

    # STEP 2.5: Verify Critical AWS Drivers for Nitro Instance Compatibility
    Write-Log "Step 2.5: Verifying critical AWS drivers for Nitro instance compatibility..."
    
    # These drivers are essential for booting on Nitro-based instances (t3, m5, m6i, m7i, etc.)
    $criticalDrivers = @(
        @{ Name = "ENA";        Desc = "Elastic Network Adapter (network on Nitro)"; Pattern = "*ena*" },
        @{ Name = "NVMe";       Desc = "NVMe storage driver (storage on Nitro)";     Pattern = "*nvme*" },
        @{ Name = "AWSNVMe";    Desc = "AWS NVMe driver";                            Pattern = "*awsnvme*" }
    )
    
    $driverIssues = $false
    $allDrivers = Get-WindowsDriver -Online -All -ErrorAction SilentlyContinue
    
    foreach ($driver in $criticalDrivers) {
        $found = $allDrivers | Where-Object { 
            $_.OriginalFileName -like $driver.Pattern -or 
            $_.ProviderName -like $driver.Pattern -or
            $_.Driver -like $driver.Pattern
        }
        
        if ($found) {
            $count = ($found | Measure-Object).Count
            Write-Log "  [OK] $($driver.Name): Found $count driver package(s) - $($driver.Desc)"
            foreach ($d in $found) {
                Write-Log "       INF: $($d.OriginalFileName), Version: $($d.Version), Provider: $($d.ProviderName)"
            }
        } else {
            Write-Log "  [WARNING] $($driver.Name): NOT FOUND - $($driver.Desc)"
            $driverIssues = $true
        }
    }
    
    # Also check for specific AWS PnP devices
    $awsPnpDevices = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
        $_.FriendlyName -match 'ENA|NVMe|AWS' -or $_.Manufacturer -match 'Amazon'
    }
    
    if ($awsPnpDevices) {
        Write-Log "  AWS PnP devices found:"
        foreach ($device in $awsPnpDevices) {
            Write-Log "       $($device.FriendlyName) [$($device.Status)]"
        }
    }
    
    if ($driverIssues) {
        Write-Log "  !!! WARNING: Missing critical AWS drivers may cause boot failures on some Nitro instance types !!!"
        Write-Log "  !!! Older Nitro (t3, m5) may work, but newer (m6i, m7i) might fail !!!"
    } else {
        Write-Log "  All critical AWS drivers present"
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

    # STEP 3.5: Verify DriverStore integrity after cleanup (critical for Sysprep)
    # Sysprep /generalize strips hardware bindings; PnP uses DriverStore to re-detect
    # drivers on first boot. Without DriverStore, AMI fails on m6i/m7i instance types.
    Write-Log "Step 3.5: Verifying DriverStore integrity after cleanup..."
    $driverStorePath = "$env:windir\System32\DriverStore\FileRepository"
    if (Test-Path $driverStorePath) {
        $storeCount = (Get-ChildItem $driverStorePath -Directory -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Log "  DriverStore FileRepository: $storeCount driver packages"
        foreach ($pattern in @('*ena*', '*nvme*', '*awsnvme*', '*amazon*')) {
            $match = Get-ChildItem $driverStorePath -Directory -Filter $pattern -ErrorAction SilentlyContinue
            if ($match) { foreach ($m in $match) { Write-Log "  [OK] DriverStore: $($m.Name)" } }
        }
        if ($storeCount -eq 0) {
            Write-Log "  [CRITICAL] DriverStore is EMPTY! AMI will not boot on newer Nitro instances!"
        }
    } else {
        Write-Log "  [CRITICAL] DriverStore FileRepository MISSING!"
    }

    # STEP 4: EC2Launch v1 Reset and Sysprep Prep
    Write-Log "Step 4: Running EC2Launch v1 sysprep prep..."
    $ec2LaunchPath = "$env:ProgramData\Amazon\EC2-Windows\Launch\Scripts"
    if (Test-Path "$ec2LaunchPath\InitializeInstance.ps1") {
        & "$ec2LaunchPath\InitializeInstance.ps1" -Schedule 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log "  InitializeInstance.ps1 completed"
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

    # Create marker file to signal completion (before Sysprep shuts down)
    $markerFile = 'C:\Windows\Temp\post-stig-complete.marker'
    New-Item -Path $markerFile -ItemType File -Force | Out-Null
    Write-Log "Created completion marker: $markerFile"

    # STEP 6: Run Sysprep via EC2Launch v1 (with shutdown for instance-state polling)
    Write-Log "Step 6: Running EC2Launch v1 sysprep..."
    
    # Remove the scheduled task before sysprep
    Unregister-ScheduledTask -TaskName "PostSTIG" -Confirm:$false -ErrorAction SilentlyContinue
    
    $ec2LaunchPath = "$env:ProgramData\Amazon\EC2-Windows\Launch\Scripts"
    if (Test-Path "$ec2LaunchPath\SysprepInstance.ps1") {
        Write-Log "  Starting EC2Launch v1 sysprep (will shutdown instance)..."
        # Run SysprepInstance.ps1 WITHOUT -NoShutdown so it shuts down after completion
        & "$ec2LaunchPath\SysprepInstance.ps1" 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log "  EC2Launch v1 sysprep initiated. Instance should shutdown shortly."
    } else {
        Write-Log "  WARNING: SysprepInstance.ps1 not found, falling back to direct Sysprep..."
        $sysprepPath = "$env:SystemRoot\System32\Sysprep\Sysprep.exe"
        if (Test-Path $sysprepPath) {
            Start-Process -FilePath $sysprepPath -ArgumentList '/generalize /oobe /shutdown /quiet' -NoNewWindow
            Write-Log "  Direct Sysprep started."
        } else {
            Write-Log "  ERROR: Sysprep.exe not found!"
        }
    }

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
}

Write-Log "Script completed."
