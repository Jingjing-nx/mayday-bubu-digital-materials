@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG=%TEMP%\OrangeBubuPet-uninstall.log"

if defined CODEX_HOME (
  set "CODEX_DIR=%CODEX_HOME%"
) else (
  set "CODEX_DIR=%USERPROFILE%\.codex"
)
set "ORANGE_PET_DEST=%CODEX_DIR%\pets\bubu-orange"
set "PANEL_DEST=%LOCALAPPDATA%\OrangeBubuPet"
set "RUN_VALUE=OrangeBubuQuotaPanel"
set "STARTUP_FILE=OrangeBubuQuotaPanel.cmd"
if exist "%ROOT%\ULTIMATE.txt" (
  set "PANEL_DEST=%LOCALAPPDATA%\OrangeBubuUltimate"
  set "RUN_VALUE=OrangeBubuUltimatePanel"
  set "STARTUP_FILE=OrangeBubuUltimatePanel.cmd"
)

>"%LOG%" echo Bubu Windows uninstaller
>>"%LOG%" echo Started: %DATE% %TIME%

where powershell.exe >nul 2>&1
if not errorlevel 1 if exist "%ROOT%\windows\uninstall-optional.ps1" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\windows\uninstall-optional.ps1" >>"%LOG%" 2>&1
)

reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "%RUN_VALUE%" /f >>"%LOG%" 2>&1
del /F /Q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\%STARTUP_FILE%" >>"%LOG%" 2>&1
if exist "%PANEL_DEST%" rmdir /S /Q "%PANEL_DEST%" >>"%LOG%" 2>&1
if exist "%ORANGE_PET_DEST%" rmdir /S /Q "%ORANGE_PET_DEST%" >>"%LOG%" 2>&1

if exist "%ORANGE_PET_DEST%" (
  echo [ERROR] Bubu could not be fully removed.
  echo Log: %LOG%
  pause
  exit /b 1
)
echo [OK] Orange Bubu was removed. Other pet projects were untouched.
echo Restart ChatGPT/Codex completely.
echo Log: %LOG%
echo.
pause
exit /b 0
