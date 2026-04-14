@echo off
echo [%date% %time%] Starting SetupComplete.cmd >> C:\SetupComplete.log 2>&1

:: Wait for network stack to initialize after Sysprep
ping -n 15 127.0.0.1 > nul

:: Reapply Administrator rename
wmic useraccount where "Name='Administrator'" call rename Name="maintuser" 2>> C:\SetupComplete.log

:: Remove temporary user account
net user TempPackerUser /delete >> C:\SetupComplete.log 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] User TempPackerUser deleted. >> C:\SetupComplete.log
) else (
    echo [ERROR] Failed to delete TempPackerUser. Error: %errorlevel% >> C:\SetupComplete.log
)

:: Remove user profile directory (if exists)
rmdir /s /q "C:\Users\TempPackerUser" >> C:\SetupComplete.log 2>&1

:: Remove from local Administrators group (if member)
net localgroup Administrators TempPackerUser /delete >> C:\SetupComplete.log 2>&1

:: Restart SSM Agent to pick up new instance identity after Sysprep
echo [%date% %time%] Restarting AmazonSSMAgent... >> C:\SetupComplete.log
net stop AmazonSSMAgent >> C:\SetupComplete.log 2>&1
net start AmazonSSMAgent >> C:\SetupComplete.log 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] AmazonSSMAgent restarted. >> C:\SetupComplete.log
) else (
    echo [WARNING] AmazonSSMAgent restart returned %errorlevel%. >> C:\SetupComplete.log
)

:: Enable WinRM HTTPS for post-deployment configuration management
winrm quickconfig -force -q >> C:\SetupComplete.log 2>&1
netsh advfirewall firewall add rule name="WinRM HTTPS" protocol=TCP dir=in localport=5986 action=allow >> C:\SetupComplete.log 2>&1

:: Log success
echo [%date% %time%] SetupComplete.cmd finished. >> C:\SetupComplete.log