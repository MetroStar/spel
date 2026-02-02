# Restore WinRM connectivity for Packer after STIG hardening
# This script runs all restoration steps atomically to avoid connection disruption

$ErrorActionPreference = 'Continue'

# Step 1: Configure WinRM service
Set-Service -Name WinRM -StartupType Automatic

# Step 2: Re-enable WinRM settings that STIG may have disabled
winrm set winrm/config/service '@{AllowUnencrypted="true"}' 2>$null
winrm set winrm/config/service/auth '@{Basic="true"}' 2>$null
winrm set winrm/config/client '@{AllowUnencrypted="true"}' 2>$null
winrm set winrm/config/client/auth '@{Basic="true"}' 2>$null

# Step 3: Ensure HTTPS listener exists
$httpsListener = Get-ChildItem -Path WSMan:\localhost\Listener -ErrorAction SilentlyContinue | 
    Where-Object { $_.Keys -contains 'Transport=HTTPS' }
if (-not $httpsListener) {
    $cert = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue | 
        Where-Object { $_.Subject -match $env:COMPUTERNAME } | 
        Select-Object -First 1
    if ($cert) {
        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force
    } else {
        # Create self-signed cert if none exists
        $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force
    }
}

# Step 4: Configure firewall rules (using netsh for atomic execution)
netsh advfirewall firewall delete rule name="WinRM HTTPS Inbound (Packer)" 2>$null
netsh advfirewall firewall delete rule name="WinRM HTTP Inbound (Packer)" 2>$null
netsh advfirewall firewall add rule name="WinRM HTTPS Inbound (Packer)" dir=in action=allow protocol=tcp localport=5986
netsh advfirewall firewall add rule name="WinRM HTTP Inbound (Packer)" dir=in action=allow protocol=tcp localport=5985

# Step 5: Ensure no blocking rules for WinRM
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new enable=yes 2>$null
netsh advfirewall firewall set rule name="Windows Remote Management (HTTPS-In)" new enable=yes 2>$null

# Step 6: Start WinRM (don't restart to avoid dropping current connection)
Start-Service WinRM -ErrorAction SilentlyContinue

Write-Output "WinRM restoration complete"
