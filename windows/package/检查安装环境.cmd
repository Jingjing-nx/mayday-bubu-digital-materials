@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

set "REPORT=%USERPROFILE%\Desktop\Bubu-Windows-Check.txt"
set "ROOT=%~dp0"

>"%REPORT%" echo Bubu Windows compatibility check 20
>>"%REPORT%" echo Date: %DATE% %TIME%
>>"%REPORT%" echo Windows: %OS%
>>"%REPORT%" echo Architecture: %PROCESSOR_ARCHITECTURE%
>>"%REPORT%" echo User profile: available
>>"%REPORT%" echo Local app data: available

if exist "%ROOT%pet\bubu-office\pet.json" (
  >>"%REPORT%" echo Package pet.json: OK
) else (
  >>"%REPORT%" echo Package pet.json: MISSING
)
if exist "%ROOT%pet\bubu-office\spritesheet-win-20.webp" (
  >>"%REPORT%" echo Package blue versioned spritesheet: OK
) else (
  >>"%REPORT%" echo Package blue versioned spritesheet: MISSING
)
where powershell.exe >>"%REPORT%" 2>&1
if errorlevel 1 (
  >>"%REPORT%" echo PowerShell: UNAVAILABLE - the optional panel cannot run
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%windows\diagnose.ps1" -Report "%REPORT%" -Root "%ROOT%" >>"%REPORT%" 2>&1
)

echo Compatibility report created:
echo %REPORT%
echo.
pause
