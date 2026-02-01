@echo off
setlocal

REM =========================
REM CONFIGURATION
REM =========================
set "TG_TOKEN=xxxx:xxxx"
set "CHAT_ID=xxxxx"
REM =========================

set "FILE_PATH=%~1"

REM Validation: Check if argument is provided and if the file exists
if "%FILE_PATH%"=="" (
    echo [!] Usage: tg_send.bat C:\path\to\file.log
    exit /b 1
)

if not exist "%FILE_PATH%" (
    powershell -Command "[Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); [System.Windows.Forms.MessageBox]::Show('File not found: %FILE_PATH%')"
    echo [!] File not found: %FILE_PATH%
    exit /b 1
)

REM Send via built-in curl
curl -sS --fail ^
  -F "chat_id=%CHAT_ID%" ^
  -F "document=@%FILE_PATH%" ^
  "https://api.telegram.org/bot%TG_TOKEN%/sendDocument"

if %ERRORLEVEL% equ 0 (
    echo [+] File sent successfully.
    REM Show notification (similar to zenity)
    powershell -Command "[Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); [System.Windows.Forms.MessageBox]::Show('Sent successfully: %FILE_PATH%')"
) else (
    echo [!] Failed to send file. Check your token, Chat ID, or internet connection.
    exit /b 1
)

endlocal
