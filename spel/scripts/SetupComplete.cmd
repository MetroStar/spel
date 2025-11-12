@echo off
echo [%date% %time%] Starting SetupComplete.cmd >> C:\SetupComplete.log 2>&1

:: Reapply Administrator rename
wmic useraccount where "Name='Administrator'" call rename Name="maintuser" 2>> C:\SetupComplete.log

:: Remove temporary user account
net user TempPackerUser /delete >> C:\SetupComplete.log 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] User TempPackerUser deleted. >> C:\SetupComplete.log
) else (
    echo [ERROR] Failed to delete TempPackerUser. Error: %errorlevel% >> C:\SetupComplete.log
)

:: Optional: Remove user profile directory (if exists)
rmdir /s /q "C:\Users\TempPackerUser" >> C:\SetupComplete.log 2>&1

:: Optional: Remove from local Administrators group (if member)
net localgroup Administrators TempPackerUser /delete >> C:\SetupComplete.log 2>&1

:: Optional: Log success
echo [%date% %time%] SetupComplete.cmd finished. >> C:\SetupComplete.log