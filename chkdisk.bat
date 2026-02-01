@echo off
setlocal ENABLEDELAYEDEXPANSION

:: Check for Administrator Privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Please run this script as Administrator.
    pause
    exit /b 1
)

:: Force UTF-8 encoding for the console
chcp 65001 >nul

REM =========================
REM  CONFIGURATION
REM =========================
set "DISK_LETTER=D"
set "GRUB_CFG=C:\grub2\grub.cfg"
set "LOG=C:\chkdisk.log"
set "REBOOT_FLAG=C:\reboot.txt"

REM --- CHECK REBOOT FLAG ---
if not exist "%REBOOT_FLAG%" (
    echo 0 > "%REBOOT_FLAG%"
)

set /p AUTH_VAL=<"%REBOOT_FLAG%"
set "AUTH_VAL=!AUTH_VAL: =!"

if "!AUTH_VAL!"=="0" (
    echo [Manual Mode] Flag is 0. Automation suspended.
    timeout /t 5
    exit /b 0
)

REM --- INITIALIZE LOG ---
echo [%date% %time%] --- NEW REPAIR SESSION STARTING --- > "%LOG%"
echo Target disk: %DISK_LETTER%: >> "%LOG%"
echo Grub config: %GRUB_CFG% >> "%LOG%"

REM Check for files and drives
if not exist "%GRUB_CFG%" (
    echo [%date% %time%] ERROR: grub.cfg NOT FOUND >> "%LOG%"
    goto END
)

if not exist "%DISK_LETTER%:\" (
    echo [%date% %time%] ERROR: drive %DISK_LETTER%: NOT FOUND >> "%LOG%"
    goto END
)

REM === CHKDSK REPAIR ===
echo [%date% %time%] Running chkdsk... >> "%LOG%"
chkdsk %DISK_LETTER%: /F >> "%LOG%" 2>&1
set "CHKCODE=%ERRORLEVEL%"
echo [%date% %time%] chkdsk exit code = !CHKCODE! >> "%LOG%"

REM Error levels 0-3 are generally acceptable
if !CHKCODE! GTR 3 (
    echo [%date% %time%] ERROR: CHKDSK FAILED WITH CODE !CHKCODE! >> "%LOG%"
    goto END
)

REM === UPDATE GRUB CONFIG ===
echo [%date% %time%] Updating grub.cfg (Windows -> Linux) >> "%LOG%"

:: Using a more stable PowerShell call without complex line breaks
powershell -NoProfile -Command ^
    "$p='%GRUB_CFG%';" ^
    "$c=Get-Content $p;" ^
    "if($c -match 'set default=0'){$c=$c -replace 'set default=0','set default=1';$c|Set-Content $p; Write-Output 'Success'}else{throw 'No set default=0 found'}" >> "%LOG%" 2>&1

if %errorlevel% neq 0 (
    echo [%date% %time%] ERROR: PowerShell failed to update grub.cfg >> "%LOG%"
) else (
    echo [%date% %time%] PowerShell update finished successfully >> "%LOG%"
)

REM === SET REBOOT FLAG ===
echo [%date% %time%] Setting reboot flag to 1 >> "%LOG%"
echo 1 > "%REBOOT_FLAG%"

REM === SEND LOG TO TELEGRAM ===
if exist "C:\tg_send.bat" (
    call C:\tg_send.bat "%LOG%"
) else (
    echo [%date% %time%] WARNING: C:\tg_send.bat not found >> "%LOG%"
)

:END
echo [%date% %time%] END chkdisk.bat >> "%LOG%"
timeout /t 3
endlocal
exit /b 0