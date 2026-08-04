@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Keep startup fully ASCII and launch PowerShell directly. The previous
rem script trampoline could be rejected as an invalid character on some PCs
rem before the panel had a chance to start.
set "PANEL_SCRIPT=%~dp0BubuQuotaPanel.ps1"
if not exist "%PANEL_SCRIPT%" set "PANEL_SCRIPT=%LOCALAPPDATA%\OrangeBubuUltimate\BubuQuotaPanel.ps1"
if not exist "%PANEL_SCRIPT%" set "PANEL_SCRIPT=%LOCALAPPDATA%\OrangeBubuPet\BubuQuotaPanel.ps1"
if not exist "%PANEL_SCRIPT%" exit /b 1

start "" /b "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PANEL_SCRIPT%"
exit /b 0
