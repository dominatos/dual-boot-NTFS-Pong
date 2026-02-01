@echo off
setlocal ENABLEDELAYEDEXPANSION
chcp 65001 >nul
REM =========================
REM CONFIGURATION
REM =========================
set "FLAG_FILE=C:\reboot.txt"
set "LOG=C:\reboot.log"
REM =========================
echo [%date% %time%] --- reboot --- > "%LOG%"
echo ================================================== >> "%LOG%"
echo [%date% %time%] START reboot-if-needed.bat >> "%LOG%"

REM Check if the flag file exists
if not exist "%FLAG_FILE%" (
    echo [%date% %time%] ERROR: %FLAG_FILE% not found >> "%LOG%"
    goto END
)

REM Read the first line of the file and remove spaces
set /p REBOOT_FLAG=<"%FLAG_FILE%"
set "REBOOT_FLAG=!REBOOT_FLAG: =!"

echo [%date% %time%] reboot.txt value = "!REBOOT_FLAG!" >> "%LOG%"

REM Check the flag value
if "!REBOOT_FLAG!"=="1" (
    echo [%date% %time%] Reboot requested >> "%LOG%"
    
    REM Reset the flag to 0 before rebooting
    echo 0 > "%FLAG_FILE%"
    
    REM Execute restart with a 5-second delay
    shutdown /r /t 5 /c "Reboot requested by reboot-if-needed.bat"
) else (
    echo [%date% %time%] Reboot NOT requested >> "%LOG%"
)
REM === SEND LOG TO TELEGRAM ===
call C:\tg_send.bat "%LOG%"
:END
echo [%date% %time%] END reboot-if-needed.bat >> "%LOG%"
endlocal
exit /b 0
