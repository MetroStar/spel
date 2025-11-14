<#
.SYNOPSIS
    Enhanced script to clean and prepare a Windows Server 2016 EC2 instance
    for AMI creation. Performs comprehensive cleaning and AWS-specific optimizations.

.DESCRIPTION
    This script performs deep cleaning of logs, temp files, WinSxS, registry,
    network configurations, and AWS-specific cleanup before generalizing 
    the instance using EC2Launch and Sysprep for AMI creation.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipSysprep
)

Set-StrictMode -Version Latest
$ProgressPreference     = 'SilentlyContinue'
$ErrorActionPreference  = 'Stop'
$ConfirmPreference      = 'None'  # Suppress all confirmation prompts

# Make sure verbose/information messages are visible in non-interactive runs (Packer)
$VerbosePreference     = 'Continue'
$InformationPreference = 'Continue'

# Trap: on any terminating error, emit structured output (no color by default)
trap {
    Write-Output
    Write-Output "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1' | Write-Output
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Output
    Write-Output
    Write-Output 'Script failed. Sleeping for 60m for manual inspection before self-destruction...'
    Start-Sleep -Seconds (60*60)
    Exit 1
}

# Detect Windows version
$osVersion = (Get-WmiObject -Class Win32_OperatingSystem).Version
$osName = (Get-WmiObject -Class Win32_OperatingSystem).Caption
$isServer2019OrLater = [Version]$osVersion -ge [Version]"10.0.17763"
$isServer2016 = [Version]$osVersion -ge [Version]"10.0.14393" -and [Version]$osVersion -lt [Version]"10.0.17763"

Write-Output "Detected OS: $osName (Version: $osVersion)"
if ($isServer2019OrLater) {
    Write-Output "Using Windows Server 2019+ optimizations..."
} elseif ($isServer2016) {
    Write-Output "Using Windows Server 2016 optimizations..."
} else {
    Write-Output "Warning: Unsupported Windows version detected!"
}

Write-Output "Starting enhanced Windows Server EC2 AMI cleanup..."

# -------------------------------------------------------------------
## Section 1: Stop Services & Clear Logs / Temp Files
# -------------------------------------------------------------------

Write-Output 'Stopping services that might interfere with file removal...'
function Stop-ServiceForReal($name) {
    while ($true) {
        $svc = Get-Service $name -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            Write-Verbose "Service $name does not exist. Skipping."
            break
        }
        
        if ($svc.Status -eq 'Stopped') {
            Write-Verbose "Service $name is already stopped."
            break
        }
        
        Write-Output "Stopping service $name..."
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

# Stop services that can interfere with cleanup
$servicesToStop = @(
    'TrustedInstaller',   # Windows Modules Installer
    'wuauserv',          # Windows Update
    'BITS',              # Background Intelligent Transfer Service
    'cryptSvc',          # Cryptographic Services
    'VSS',               # Volume Shadow Copy
    'swprv',             # Microsoft Software Shadow Copy Provider
    'Themes',            # Themes service
    'TabletInputService', # Tablet PC Input Service
    'WSearch'            # Windows Search
)

foreach ($service in $servicesToStop) {
    Stop-ServiceForReal $service
}

Write-Output 'Clearing all event logs...'
try {
    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
        # Check if the object has a LogName property and it's not null/empty
        if ($_ -and $_.LogName -and $_.LogName.Trim() -ne '') {
            Write-Verbose "Clearing log: $($_.LogName)"
            try {
                wevtutil.exe clear-log $_.LogName 2>$null
            } catch {
                Write-Verbose "Could not clear log $($_.LogName): $($_.Exception.Message)"
            }
        } else {
            Write-Verbose "Skipping invalid or empty log entry"
        }
    }
} catch {
    Write-Verbose "Error accessing event logs: $($_.Exception.Message)"
    Write-Output "Falling back to alternative log clearing method..."
    
    # Alternative method using wevtutil directly
    try {
        $logList = wevtutil.exe el 2>$null
        foreach ($logName in $logList) {
            if ($logName -and $logName.Trim() -ne '') {
                Write-Verbose "Clearing log (fallback): $logName"
                wevtutil.exe clear-log $logName 2>$null
            }
        }
    } catch {
        Write-Verbose "Fallback log clearing also failed: $($_.Exception.Message)"
    }
}

Write-Output "Cleaning comprehensive temp file locations..."
$tempPaths = @(
    "$env:windir\Temp\*",
    "$env:windir\Logs\*",
    "$env:windir\Panther\*",
    "$env:windir\WinSxS\ManifestCache\*",
    "$env:windir\SoftwareDistribution\Download\*",
    "$env:windir\SoftwareDistribution\DataStore\*",
    "$env:windir\System32\Driverstore\FileRepository\*",
    "$env:windir\System32\winevt\Logs\*",
    "$env:windir\inf\*.log",
    "$env:windir\Prefetch\*",
    "C:\ProgramData\Microsoft\Windows\WER\*",
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\*",
    "C:\Windows\System32\LogFiles\*",
    "C:\Windows\System32\config\systemprofile\AppData\Local\Temp\*",
    "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp\*",
    "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Temp\*",
    "$env:LOCALAPPDATA\Temp\*",
    "C:\Users\Administrator\AppData\Local\Temp\*",
    "C:\Users\Administrator\AppData\Local\Microsoft\Windows\Temporary Internet Files\*",
    "C:\Users\Administrator\AppData\Local\Microsoft\Windows\INetCache\*",
    "C:\Users\Administrator\AppData\Local\Microsoft\Windows\History\*",
    "C:\Users\Administrator\AppData\Roaming\Microsoft\Windows\Recent\*",
    "C:\Users\Administrator\Favorites\*",
    "C:\Users\Administrator\Downloads\*",
    "C:\Users\Administrator\Desktop\*",
    "C:\Users\maintuser\AppData\Local\Temp\*",
    "C:\Users\maintuser\AppData\Local\Microsoft\Windows\Temporary Internet Files\*",
    "C:\Users\maintuser\AppData\Local\Microsoft\Windows\INetCache\*",
    "C:\Users\maintuser\AppData\Local\Microsoft\Windows\History\*",
    "C:\Users\maintuser\AppData\Roaming\Microsoft\Windows\Recent\*",
    "C:\Users\maintuser\AppData\Roaming\Microsoft\Office\Recent\*",
    "C:\Users\maintuser\AppData\Local\Microsoft\Office\*",
    "C:\Users\maintuser\Favorites\*",
    "C:\Users\maintuser\Downloads\*",
    "C:\Users\maintuser\Desktop\*",
    "C:\Users\maintuser\Documents\*",
    "C:\Users\maintuser\Pictures\*",
    "C:\Users\maintuser\Videos\*",
    "C:\Users\maintuser\Music\*"
)

foreach ($path in $tempPaths) {
    # Handle wildcard paths properly
    if ($path -like "*\*" -or $path -like "*.log") {
        # This is a wildcard path, get the parent directory
        $parentPath = Split-Path $path -Parent
        if (Test-Path $parentPath) {
            Write-Output "Removing temporary files from $path..."
            try {
                # Get items matching the pattern
                $itemsToRemove = @(Get-ChildItem $path -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'packer-*' })
                if ($itemsToRemove -and $itemsToRemove.Count -gt 0) {
                    foreach ($item in $itemsToRemove) {
                        try {
                            if ($item -and $item.FullName) {
                                takeown.exe /D Y /R /F "$($item.FullName)" 2>&1 | Out-Null
                                icacls.exe "$($item.FullName)" /grant:r Administrators:F /T /C /Q 2>&1 | Out-Null
                                if ($item.PSIsContainer) {
                                    Remove-Item "$($item.FullName)" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
                                } else {
                                    Remove-Item "$($item.FullName)" -Force -Confirm:$false -ErrorAction SilentlyContinue
                                }
                            }
                        } catch {
                            Write-Verbose "Ignoring failure to remove item: $($_.Exception.Message)"
                        }
                    }
                } else {
                    Write-Verbose "No items to remove in $path"
                }
            } catch {
                Write-Verbose "Ignoring failure to process ${path}: $($_.Exception.Message)"
            }
        }
    } elseif (Test-Path $path -PathType Container) {
        # This is a direct directory path
        $items = Get-ChildItem $path -ErrorAction SilentlyContinue
        if ($items) {
            Write-Output "Removing directory contents from $path..."
            try {
                takeown.exe /D Y /R /F $path 2>&1 | Out-Null
                icacls.exe $path /grant:r Administrators:F /T /C /Q 2>&1 | Out-Null
                Remove-Item "$path\*" -Exclude 'packer-*' -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
            } catch {
                Write-Verbose "Ignoring failure to remove directory contents in ${path}: $($_.Exception.Message)"
            }
        }
    } elseif (Test-Path $path -PathType Leaf) {
        Write-Output "Removing file $path..."
        Remove-Item $path -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------------------------------
## Section 2: AWS-Specific Cleanup
# -------------------------------------------------------------------

Write-Output "Performing AWS-specific cleanup..."

# Clear AWS EC2 instance metadata cache
Write-Output "Clearing EC2 instance metadata cache..."
$ec2ConfigLog = "C:\Program Files\Amazon\Ec2ConfigService\Logs"
if (Test-Path $ec2ConfigLog) {
    Remove-Item "$ec2ConfigLog\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

# Clear EC2Launch logs (version-specific paths)
if ($isServer2019OrLater) {
    # EC2Launch v2 for Server 2019+
    $ec2LaunchLogs = @(
        "C:\ProgramData\Amazon\EC2Launch\log\*",
        "C:\ProgramData\Amazon\EC2-Windows\Launch\Log\*"
    )
} else {
    # EC2Launch v1 for Server 2016
    $ec2LaunchLogs = @(
        "C:\ProgramData\Amazon\EC2-Windows\Launch\Log\*"
    )
}

foreach ($logPath in $ec2LaunchLogs) {
    if (Test-Path $logPath) {
        Write-Output "Clearing EC2Launch logs: $logPath"
        Remove-Item $logPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# Clear CloudWatch logs agent data
$cloudWatchLogs = "C:\ProgramData\Amazon\AmazonCloudWatchAgent\Logs"
if (Test-Path $cloudWatchLogs) {
    Remove-Item "$cloudWatchLogs\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

# Clear SSM agent logs
$ssmLogs = "C:\ProgramData\Amazon\SSM\Logs"
if (Test-Path $ssmLogs) {
    Remove-Item "$ssmLogs\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

# Reset network adapter configurations
Write-Output "Resetting network configurations..."
try {
    # Clear DNS cache
    ipconfig /flushdns | Out-Null
    
    # Reset network adapters to DHCP
    # Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | ForEach-Object {
    #     Set-NetIPInterface -InterfaceIndex $_.InterfaceIndex -Dhcp Enabled -ErrorAction SilentlyContinue
    #     Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue
    # }
} catch {
    Write-Verbose "Network reset had issues: $_"
}

# -------------------------------------------------------------------
## Section 3: Registry Cleanup
# -------------------------------------------------------------------

Write-Output "Performing registry cleanup..."

# Clear MRU (Most Recently Used) lists
$mruPaths = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs'
)

foreach ($mruPath in $mruPaths) {
    if (Test-Path $mruPath) {
        Write-Output "Clearing registry path: $mruPath"
        try {
            Remove-Item $mruPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "Could not clear ${mruPath}: $($_.Exception.Message)"
        }
    }
}

# Clear maintuser-specific registry paths and user profile data
Write-Output "Cleaning maintuser-specific registry and profile data..."
try {
    # Load maintuser hive if it exists and clean it
    $maintUserProfilePath = "C:\Users\maintuser"
    if (Test-Path $maintUserProfilePath) {
        Write-Output "Found maintuser profile, performing comprehensive cleanup..."
        
        # Get maintuser SID for registry operations
        try {
            $maintUserSID = (New-Object System.Security.Principal.NTAccount("maintuser")).Translate([System.Security.Principal.SecurityIdentifier]).Value
            Write-Verbose "Maintuser SID: $maintUserSID"
            
            # Clean maintuser registry hive paths (if loaded)
            $maintUserRegPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$maintUserSID",
                "HKU:\$maintUserSID\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
                "HKU:\$maintUserSID\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
                "HKU:\$maintUserSID\Software\Microsoft\Office",
                "HKU:\$maintUserSID\Software\Microsoft\Internet Explorer\TypedURLs"
            )
            
            foreach ($regPath in $maintUserRegPaths) {
                if (Test-Path $regPath) {
                    Write-Verbose "Clearing maintuser registry path: $regPath"
                    Remove-Item $regPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Verbose "Could not resolve maintuser SID or clean registry: $($_.Exception.Message)"
        }
        
        # Reset maintuser profile permissions and ownership
        # Note: Skipping recursive permission reset as it can take very long on large profiles
        # Files will be cleaned up anyway, so permission reset is not critical
        # try {
        #     Write-Output "Resetting maintuser profile permissions..."
        #     takeown.exe /D Y /R /F "$maintUserProfilePath" /A 2>&1 | Out-Null
        #     icacls.exe "$maintUserProfilePath" /reset /T /C /Q 2>&1 | Out-Null
        #     icacls.exe "$maintUserProfilePath" /grant:r "maintuser:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
        # } catch {
        #     Write-Verbose "Failed to reset maintuser profile permissions: $($_.Exception.Message)"
        # }
        
        # Clear maintuser PowerShell history
        $maintUserPSHistory = "$maintUserProfilePath\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
        if (Test-Path $maintUserPSHistory) {
            Remove-Item $maintUserPSHistory -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
        
        # Clear maintuser event logs related paths
        $maintUserEventPaths = @(
            "$maintUserProfilePath\AppData\Local\Microsoft\Windows\History",
            "$maintUserProfilePath\AppData\Local\Microsoft\Windows\INetCache",
            "$maintUserProfilePath\AppData\Local\Microsoft\Windows\INetCookies",
            "$maintUserProfilePath\AppData\Roaming\Microsoft\Windows\Cookies"
        )
        
        foreach ($eventPath in $maintUserEventPaths) {
            if (Test-Path $eventPath) {
                Remove-Item "$eventPath\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-Verbose "Maintuser profile not found, skipping user-specific cleanup"
    }
} catch {
    Write-Verbose "Maintuser cleanup encountered issues: $($_.Exception.Message)"
}

# Clear Windows activation cache
Write-Output "Clearing Windows activation cache..."
try {
    # Run slmgr commands with timeout to prevent hanging
    $slmgrJob1 = Start-Job -ScriptBlock { cscript.exe //nologo C:\Windows\System32\slmgr.vbs /cpky }
    $slmgrJob2 = Start-Job -ScriptBlock { cscript.exe //nologo C:\Windows\System32\slmgr.vbs /ckms }
    
    # Wait max 30 seconds for each command
    Wait-Job -Job $slmgrJob1 -Timeout 30 | Out-Null
    Wait-Job -Job $slmgrJob2 -Timeout 30 | Out-Null
    
    # Clean up jobs
    Remove-Job -Job $slmgrJob1 -Force -ErrorAction SilentlyContinue
    Remove-Job -Job $slmgrJob2 -Force -ErrorAction SilentlyContinue
} catch {
    Write-Verbose "Windows activation cache clear failed: $_"
}

# -------------------------------------------------------------------
## Section 4: Windows Update & BITS Cleanup
# -------------------------------------------------------------------

Write-Output "Resetting Windows Update and BITS..."

Write-Output "Clearing BITS jobs..."
try {
    Get-BitsTransfer -AllUsers | Remove-BitsTransfer
} catch {
    Write-Verbose "Failed to clear BITS jobs (likely no jobs to clear)."
}

Write-Output "Resetting Windows Update components..."
try {
    # Rename SoftwareDistribution folder
    if (Test-Path "$env:windir\SoftwareDistribution") {
        Rename-Item "$env:windir\SoftwareDistribution" "SoftwareDistribution.old" -ErrorAction SilentlyContinue
    }
    
    # Reset catroot2 database
    if (Test-Path "$env:windir\System32\catroot2") {
        Rename-Item "$env:windir\System32\catroot2" "catroot2.old" -ErrorAction SilentlyContinue
    }
    
    Start-Service cryptSvc -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Start-Service BITS -ErrorAction SilentlyContinue
} catch {
    Write-Verbose "Windows Update reset had issues: $_"
}

# -------------------------------------------------------------------
## Section 5: System Optimization (WinSxS & Features)
# -------------------------------------------------------------------

Write-Output 'Cleaning up the WinSxS Component Store...'
try {
    Write-Output "Running DISM cleanup operations..."
    dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
    dism.exe /Online /Cleanup-Image /SPSuperseded
} catch {
    Write-Output "DISM failed with Exit Code $LASTEXITCODE. Trying scheduled task fallback..."
    try {
        schtasks.exe /Run /TN "\Microsoft\Windows\Servicing\StartComponentCleanup"

        Write-Output "Waiting for StartComponentCleanup task to finish..."
        $taskRunning = $true
        $timeout = 0
        while ($taskRunning -and $timeout -lt 60) {
            Start-Sleep -Seconds 30
            $timeout++
            try {
                $taskState = (Get-ScheduledTask -TaskName "StartComponentCleanup" -TaskPath "\Microsoft\Windows\Servicing\").State
                if ($taskState -ne "Running") {
                    Write-Output "Task finished with state: $taskState"
                    $taskRunning = $false
                } else {
                    Write-Output "Task is still running... ($timeout/60)"
                }
            } catch {
                Write-Output "Could not check task state, assuming it finished."
                $taskRunning = $false
            }
        }
    } catch {
        Write-Verbose "DISM fallback task failed: $_"
    }
}

Write-Output "Removing disabled Windows Features..."
try {
    if ($isServer2019OrLater) {
        # Server 2019+ has better feature management
        $disabledFeatures = Get-WindowsOptionalFeature -Online | Where-Object {$_.State -eq 'Disabled'}
        foreach ($feature in $disabledFeatures) {
            Write-Verbose "Removing feature: $($feature.FeatureName)"
            Disable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -Remove -NoRestart -ErrorAction SilentlyContinue
        }
        
        # Also clean up Windows Capabilities (Server 2019+ feature)
        $capabilities = Get-WindowsCapability -Online | Where-Object {$_.State -eq 'NotPresent'}
        foreach ($capability in $capabilities) {
            Write-Verbose "Removing capability: $($capability.Name)"
            Remove-WindowsCapability -Online -Name $capability.Name -ErrorAction SilentlyContinue
        }
    } else {
        # Server 2016 standard approach
        $disabledFeatures = Get-WindowsOptionalFeature -Online | Where-Object {$_.State -eq 'Disabled'}
        foreach ($feature in $disabledFeatures) {
            Write-Verbose "Removing feature: $($feature.FeatureName)"
            dism.exe /Online /Quiet /Disable-Feature "/FeatureName:$($feature.FeatureName)" /Remove 2>$null
        }
    }
} catch {
    Write-Verbose "Could not remove all disabled features: $_"
}

Write-Output 'Analyzing WinSxS folder post-cleanup...'
dism.exe /Online /Cleanup-Image /AnalyzeComponentStore

# -------------------------------------------------------------------
## Section 6: Security and Privacy Cleanup
# -------------------------------------------------------------------

Write-Output "Performing security and privacy cleanup..."

# Clear certificate stores of user certificates
Write-Output "Clearing user certificate stores..."
try {
    # Clear My store (personal certificates) - this should work without UI
    Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Remove-Item -Force -Confirm:$false -ErrorAction SilentlyContinue
    
    # Skip Root store cleanup - requires UI in non-interactive sessions
    # Get-ChildItem Cert:\CurrentUser\Root | Where-Object {$_.Subject -notlike "*Microsoft*" -and $_.Subject -notlike "*Windows*"} | Remove-Item -Force -Confirm:$false -ErrorAction SilentlyContinue
    
    # Clear maintuser certificates if profile exists
    $maintUserCertPath = "C:\Users\maintuser\AppData\Roaming\Microsoft\SystemCertificates"
    if (Test-Path $maintUserCertPath) {
        Write-Output "Clearing maintuser certificate stores..."
        Remove-Item "$maintUserCertPath\My\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        # Skip root certs - they require UI
        # Remove-Item "$maintUserCertPath\Root\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$maintUserCertPath\TrustedPeople\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {
    Write-Verbose "Certificate cleanup had issues: $_"
}

# Clear PowerShell execution policy and profiles
Write-Output "Resetting PowerShell configuration..."
try {
    # Skip execution policy change - Packer already sets it via command line
    # and GPO may override it anyway
    # Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
    
    # Clear PowerShell profiles
    if (Test-Path $PROFILE.AllUsersAllHosts) {
        Remove-Item $PROFILE.AllUsersAllHosts -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {
    Write-Verbose "PowerShell configuration reset had issues: $_"
}

# -------------------------------------------------------------------
## Section 7: Final System Hygiene
# -------------------------------------------------------------------

Write-Output 'Performing final system hygiene...'

Write-Output 'Clearing pagefile registry key...'
try {
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name PagingFiles -Value '' -PropertyType String -Force | Out-Null
} catch {
    Write-Verbose "Pagefile registry clear failed: $_"
}

Write-Output "Clearing PowerShell history..."
try {
    Remove-Item (Get-PSReadlineOption).HistorySavePath -Force -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue
    
    # Clear maintuser PowerShell history
    $maintUserPSPaths = @(
        "C:\Users\maintuser\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt",
        "C:\Users\maintuser\Documents\WindowsPowerShell\*",
        "C:\Users\maintuser\Documents\PowerShell\*"
    )
    
    foreach ($psPath in $maintUserPSPaths) {
        if (Test-Path $psPath) {
            Write-Verbose "Clearing maintuser PowerShell path: $psPath"
            Remove-Item $psPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
} catch {
    Write-Verbose "PowerShell history clear failed: $_"
}

Write-Output "Clearing browser caches and data..."
try {
    # Clear IE/Edge cache
    RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 4351
    
    # Clear Chrome cache if present (Administrator)
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
    if (Test-Path $chromePath) {
        Remove-Item "$chromePath\Cache\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$chromePath\History*" -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    # Clear maintuser browser caches
    $maintUserChromePath = "C:\Users\maintuser\AppData\Local\Google\Chrome\User Data\Default"
    if (Test-Path $maintUserChromePath) {
        Write-Output "Clearing maintuser Chrome cache..."
        Remove-Item "$maintUserChromePath\Cache\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$maintUserChromePath\History*" -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$maintUserChromePath\Cookies*" -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$maintUserChromePath\Web Data*" -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    # Clear maintuser Firefox cache if present
    $maintUserFirefoxPath = "C:\Users\maintuser\AppData\Local\Mozilla\Firefox\Profiles"
    if (Test-Path $maintUserFirefoxPath) {
        Write-Output "Clearing maintuser Firefox cache..."
        Get-ChildItem $maintUserFirefoxPath -Directory | ForEach-Object {
            Remove-Item "$($_.FullName)\cache2\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item "$($_.FullName)\cookies.sqlite*" -Force -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item "$($_.FullName)\places.sqlite*" -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    
    # Clear maintuser Edge cache
    $maintUserEdgePath = "C:\Users\maintuser\AppData\Local\Microsoft\Edge\User Data\Default"
    if (Test-Path $maintUserEdgePath) {
        Write-Output "Clearing maintuser Edge cache..."
        Remove-Item "$maintUserEdgePath\Cache\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$maintUserEdgePath\History*" -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$maintUserEdgePath\Cookies*" -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {
    Write-Verbose "Browser cache clear had issues: $_"
}

# Optimize system drive (version-specific optimizations)
Write-Output "Optimizing system drive..."
try {
    if ($isServer2019OrLater) {
        # Server 2019+ supports better optimization options
        # Try ReTrim first (may not be supported on all EBS volume types)
        try {
            Write-Verbose "Attempting ReTrim optimization..."
            Optimize-Volume -DriveLetter C -ReTrim -Verbose:$false -ErrorAction Stop
            Write-Verbose "ReTrim optimization completed successfully"
        } catch {
            Write-Verbose "ReTrim not supported on this volume type, skipping"
        }
        
        # Try defrag only if not an SSD/NVMe (EBS volumes are typically SSD-backed)
        # Defrag is not recommended for SSDs and may not be supported by the hardware
        try {
            $volume = Get-Volume -DriveLetter C
            $partition = Get-Partition | Where-Object { $_.DriveLetter -eq 'C' }
            $disk = Get-Disk -Number $partition.DiskNumber
            
            if ($disk.MediaType -eq 'HDD') {
                Write-Verbose "Attempting defragmentation on HDD..."
                Optimize-Volume -DriveLetter C -Defrag -Verbose:$false -ErrorAction Stop
                Write-Verbose "Defragmentation completed successfully"
            } else {
                Write-Verbose "Skipping defragmentation for SSD/NVMe volume (not recommended for SSDs)"
            }
        } catch {
            Write-Verbose "Defragmentation skipped or not supported: $($_.Exception.Message)"
        }
    } else {
        # Server 2016 - attempt optimization but don't fail if not supported
        try {
            Optimize-Volume -DriveLetter C -Defrag -Verbose:$false -ErrorAction Stop
        } catch {
            Write-Verbose "Volume optimization not supported on this hardware: $($_.Exception.Message)"
        }
    }
} catch {
    Write-Verbose "Drive optimization failed: $_"
}

# Clear Windows Defender definitions and reset (they'll be updated on first boot)
Write-Output "Clearing Windows Defender definitions..."
try {
    if ($isServer2019OrLater) {
        # Server 2019+ has better Defender integration
        # Stop Windows Defender service first
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        
        # Clear definition files and scan history
        Remove-Item "$env:ProgramData\Microsoft\Windows Defender\Definition Updates\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\Microsoft\Windows Defender\Scans\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        
        # Clear quarantine and network inspection cache
        Remove-Item "$env:ProgramData\Microsoft\Windows Defender\Quarantine\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\Microsoft\Windows Defender\Network Inspection System\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        
        # Restart service to let it download fresh definitions on first boot
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
    } else {
        # Server 2016 cleanup
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\Microsoft\Windows Defender\Definition Updates\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\Microsoft\Windows Defender\Scans\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
    }
} catch {
    Write-Verbose "Windows Defender cleanup failed: $_"
}

# -------------------------------------------------------------------
## Section 8: Final AMI Generalization (EC2Launch & Sysprep)
# -------------------------------------------------------------------

if (-not $SkipSysprep) {
    Write-Output ("=" * 60)
    Write-Output "FINAL STEP: EC2Launch Sysprep Generalization"
    Write-Output ("=" * 60)
    Write-Output "The instance will SHUT DOWN automatically upon completion."
    Write-Output "Ensure you create the AMI after the instance reaches 'stopped' state."

    try {
        if ($isServer2019OrLater) {
            # Windows Server 2019+ uses EC2Launch v2
            Write-Output "Using EC2Launch v2 for Windows Server 2019+..."
            
            # Check if EC2Launch v2 is installed
            $ec2LaunchV2Path = "C:\Program Files\Amazon\EC2Launch\EC2Launch.exe"
            if (Test-Path $ec2LaunchV2Path) {
                # Configure EC2Launch v2
                & $ec2LaunchV2Path sysprep --shutdown
            } else {
                # Fallback to EC2Launch v1 if v2 is not available
                Write-Output "EC2Launch v2 not found, falling back to v1..."
                Import-Module "C:\ProgramData\Amazon\EC2-Windows\Launch\Module\Ec2Launch.psd1" -ErrorAction Stop
                Set-EC2LaunchConfiguration -ExecuteSysprep $true -ComputerName 'Random' -AdministratorPassword 'Random' -Schedule 
                C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\Ec2LaunchSysprep.ps1
            }
        } else {
            # Windows Server 2016 uses EC2Launch v1
            Write-Output "Using EC2Launch v1 for Windows Server 2016..."
            Import-Module "C:\ProgramData\Amazon\EC2-Windows\Launch\Module\Ec2Launch.psd1" -ErrorAction Stop
            Set-EC2LaunchConfiguration -ExecuteSysprep $true -ComputerName 'Random' -AdministratorPassword 'Random' -Schedule 
            C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\Ec2LaunchSysprep.ps1
        }
    } catch {
        Write-Output "EC2Launch Sysprep failed: $_"
        Write-Output "Attempting manual Sysprep..."

        # Fallback to manual sysprep
        $sysprepPath = "$env:windir\System32\Sysprep\sysprep.exe"
        if (Test-Path $sysprepPath) {
            & $sysprepPath /generalize /oobe /shutdown /unattend:C:\ProgramData\Amazon\EC2-Windows\Launch\Sysprep\Unattend.xml
        } else {
            Write-Output "Sysprep executable not found. Manual intervention required."
            Exit 1
        }
    }
} else {
    Write-Output "Sysprep skipped due to -SkipSysprep parameter."
    Write-Output "AMI cleanup completed successfully!"
    return
}

# The script will not reach this point if Sysprep runs, as it shuts down the OS.
Write-Output "Script execution completed."
Exit 0