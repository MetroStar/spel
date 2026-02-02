# Restore EC2 networking functionality after STIG hardening
# This script runs within Ansible post_tasks before Packer loses WinRM connection

$ErrorActionPreference = 'Continue'

Write-Output 'Restoring EC2 network functionality after STIG hardening...'

# Ensure Windows Firewall allows IMDS access (169.254.169.254)
New-NetFirewallRule -DisplayName 'Allow EC2 IMDS Outbound' -Direction Outbound -RemoteAddress 169.254.169.254 -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'Allow EC2 IMDS Inbound' -Direction Inbound -RemoteAddress 169.254.169.254 -Action Allow -ErrorAction SilentlyContinue

# Allow link-local addresses for DHCP and routing
New-NetFirewallRule -DisplayName 'Allow Link-Local Outbound' -Direction Outbound -RemoteAddress 169.254.0.0/16 -Action Allow -ErrorAction SilentlyContinue

# Ensure DHCP client service is running
Set-Service -Name 'Dhcp' -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name 'Dhcp' -ErrorAction SilentlyContinue

# Ensure network adapters have DHCP enabled
Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | ForEach-Object {
    Set-NetIPInterface -InterfaceIndex $_.ifIndex -Dhcp Enabled -ErrorAction SilentlyContinue
}

# Ensure EC2Config/EC2Launch services are set to start
$ec2Services = @('AmazonSSMAgent', 'EC2Config', 'EC2Launch', 'AmazonCloudWatchAgent')
foreach ($svc in $ec2Services) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
    }
}

# Reset Windows Firewall to allow basic networking while maintaining security
# Allow outbound DNS
New-NetFirewallRule -DisplayName 'Allow DNS Outbound' -Direction Outbound -Protocol UDP -RemotePort 53 -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'Allow DNS Outbound TCP' -Direction Outbound -Protocol TCP -RemotePort 53 -Action Allow -ErrorAction SilentlyContinue

# Allow outbound HTTPS for AWS APIs
New-NetFirewallRule -DisplayName 'Allow HTTPS Outbound' -Direction Outbound -Protocol TCP -RemotePort 443 -Action Allow -ErrorAction SilentlyContinue

# Allow outbound HTTP for metadata and updates
New-NetFirewallRule -DisplayName 'Allow HTTP Outbound' -Direction Outbound -Protocol TCP -RemotePort 80 -Action Allow -ErrorAction SilentlyContinue

Write-Output 'EC2 network restoration complete.'
