@echo off
setlocal ENABLEDELAYEDEXPANSION
chcp 65001 >nul

REM ==================================================
REM CONFIGURATION
REM ==================================================
set "LOG=C:\reboot-to-linux.log"
set "GRUB_CFG=C:\grub2\grub.cfg"
REM ==================================================

REM 1. Clear the old log and start fresh
echo [%date% %time%] --- MANUAL REBOOT TO LINUX --- > "%LOG%"

REM 2. Update GRUB via PowerShell
echo [%date% %time%] Updating GRUB config... >> "%LOG%"

REM Important: $p is defined inside PowerShell using the Batch variable %GRUB_CFG%
powershell -NoProfile -Command ^
  "$p='%GRUB_CFG%';" ^
  "$c = Get-Content $p;" ^
  "$changed = $false;" ^
  "for ($i=0; $i -lt $c.Length; $i++) { if ($c[$i] -match '^set default=0') { $c[$i] = 'set default=1'; $changed = $true; break } }" ^
  "if ($changed) { $c | Set-Content $p } else { throw 'NO set default=0 FOUND' }" >> "%LOG%" 2>&1

REM Check if GRUB update was successful
if %ERRORLEVEL% NEQ 0 (
    echo [%date% %time%] ERROR: GRUB update failed! >> "%LOG%"
    call C:\tg_send.bat "%LOG%"
    echo Error details sent to Telegram.
    pause
    exit /b 1
)

echo [%date% %time%] PowerShell GRUB update finished >> "%LOG%"

REM 3. Send Log to Telegram
echo [%date% %time%] Sending log to Telegram... >> "%LOG%"
call C:\tg_send.bat "%LOG%"

REM 4. Trigger the reboot
echo [%date% %time%] Rebooting in 10 seconds... >> "%LOG%"
shutdown /r /t 10 /c "Manual reboot to Linux triggered." >> "%LOG%" 2>&1

:END
echo [%date% %time%] END script >> "%LOG%"
endlocal
exit /b 0
