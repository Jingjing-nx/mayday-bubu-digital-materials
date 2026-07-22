@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG=%TEMP%\BubuPet-uninstall.log"

if defined CODEX_HOME (
  set "CODEX_DIR=%CODEX_HOME%"
) else (
  set "CODEX_DIR=%USERPROFILE%\.codex"
)
set "BLUE_PET_DEST=%CODEX_DIR%\pets\bubu-office"
set "PANEL_DEST=%LOCALAPPDATA%\BubuPet"

>"%LOG%" echo Bubu Windows uninstaller
>>"%LOG%" echo Started: %DATE% %TIME%

where powershell.exe >nul 2>&1
if not errorlevel 1 if exist "%ROOT%\windows\uninstall-optional.ps1" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\windows\uninstall-optional.ps1" >>"%LOG%" 2>&1
)

reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v BubuQuotaPanel /f >>"%LOG%" 2>&1
del /F /Q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\BubuQuotaPanel.cmd" >>"%LOG%" 2>&1
if exist "%PANEL_DEST%" rmdir /S /Q "%PANEL_DEST%" >>"%LOG%" 2>&1
if exist "%BLUE_PET_DEST%" rmdir /S /Q "%BLUE_PET_DEST%" >>"%LOG%" 2>&1

if exist "%BLUE_PET_DEST%" (
  echo [ERROR] Bubu could not be fully removed.
  echo Log: %LOG%
  pause
  exit /b 1
)
echo [OK] Bubu was removed.
echo Restart ChatGPT/Codex completely.
echo Log: %LOG%
echo.
pause
exit /b 0
