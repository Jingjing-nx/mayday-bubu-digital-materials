@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG=%TEMP%\BubuPanel-repair.log"

>"%LOG%" echo Bubu panel repair
>>"%LOG%" echo Started: %DATE% %TIME%

where powershell.exe >nul 2>&1
if errorlevel 1 goto :blocked
if not exist "%ROOT%\windows\install-optional.ps1" goto :missing

echo Repairing and restarting the Bubu panel...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\windows\install-optional.ps1" -Root "%ROOT%" >>"%LOG%" 2>&1
if errorlevel 1 goto :failed

echo [OK] The panel restarted and passed its health check.
echo Log: %LOG%
echo.
pause
exit /b 0

:blocked
echo [ERROR] PowerShell is unavailable or blocked by policy.
goto :failed

:missing
echo [ERROR] Package files are incomplete. Extract the whole ZIP first.
goto :failed

:failed
echo Run the environment check and send both reports back.
echo Log: %LOG%
echo.
pause
exit /b 1
