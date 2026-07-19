@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG=%TEMP%\BubuPet-install.log"
set "PET_SOURCE=%ROOT%\pet\bubu-office"

if defined CODEX_HOME (
  set "CODEX_DIR=%CODEX_HOME%"
) else (
  set "CODEX_DIR=%USERPROFILE%\.codex"
)
set "PET_DEST=%CODEX_DIR%\pets\bubu-office"

>"%LOG%" echo Bubu Windows installer open-source V1.0.1
>>"%LOG%" echo Started: %DATE% %TIME%
>>"%LOG%" echo OS: %OS%
>>"%LOG%" echo Architecture: %PROCESSOR_ARCHITECTURE%
>>"%LOG%" echo Package files: runtime checked
>>"%LOG%" echo Codex home: configured for current user

echo.
echo Bubu Windows installer V1.0.1
echo ----------------------
if exist "%ROOT%\CODEX-ONLY.txt" (
  echo Panel: Codex quota only ^(no BTC/ETH^)
) else (
  echo Panel: Codex quota + BTC/ETH
)

if not defined USERPROFILE goto :no_profile
if not exist "%PET_SOURCE%\pet.json" goto :missing_files
if not exist "%PET_SOURCE%\spritesheet.webp" goto :missing_files

if not exist "%CODEX_DIR%\pets" mkdir "%CODEX_DIR%\pets" >>"%LOG%" 2>&1
if errorlevel 1 goto :copy_failed
if not exist "%PET_DEST%" mkdir "%PET_DEST%" >>"%LOG%" 2>&1
if errorlevel 1 goto :copy_failed

xcopy "%PET_SOURCE%\*" "%PET_DEST%\" /E /I /H /R /Y >>"%LOG%" 2>&1
if errorlevel 1 goto :copy_failed

if not exist "%PET_DEST%\pet.json" goto :copy_failed
if not exist "%PET_DEST%\spritesheet.webp" goto :copy_failed

echo [OK] Bubu pet files were installed.
>>"%LOG%" echo Pet install: OK

if /I "%~1"=="/petonly" goto :pet_only_done

where powershell.exe >nul 2>&1
if errorlevel 1 goto :optional_skipped
if not exist "%ROOT%\windows\install-optional.ps1" goto :optional_skipped

echo Installing the optional quota panel...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\windows\install-optional.ps1" -Root "%ROOT%" >>"%LOG%" 2>&1
if errorlevel 1 goto :optional_failed

echo [OK] Optional quota panel was installed and passed its health check.
>>"%LOG%" echo Optional panel install: OK
goto :all_done

:pet_only_done
echo [OK] Compatibility mode finished without PowerShell.
echo Open ChatGPT/Codex and choose Bubu in the pet picker.
>>"%LOG%" echo Compatibility mode: pet only
goto :finish_ok

:optional_skipped
echo [NOTE] PowerShell is unavailable, so the optional quota panel was skipped.
echo The Bubu pet itself is installed and can be selected in ChatGPT/Codex.
>>"%LOG%" echo Optional panel install: SKIPPED
goto :finish_ok

:optional_failed
echo [NOTE] The optional quota panel could not be installed on this PC.
echo The Bubu pet itself is installed successfully.
echo Diagnostic log: %LOG%
echo Run Repair-Bubu-Panel.cmd after reviewing the log.
>>"%LOG%" echo Optional panel install: FAILED
goto :finish_ok

:all_done
echo.
echo Restart ChatGPT/Codex completely. If Bubu is not selected,
echo choose Bubu from the pet picker.

:finish_ok
echo.
echo Log: %LOG%
echo.
pause
exit /b 0

:no_profile
echo [ERROR] Windows USERPROFILE is unavailable.
>>"%LOG%" echo ERROR: USERPROFILE unavailable
goto :finish_error

:missing_files
echo [ERROR] Package files are incomplete. Extract the whole ZIP first.
>>"%LOG%" echo ERROR: package files missing
goto :finish_error

:copy_failed
echo [ERROR] Bubu could not be copied to the Codex pet folder.
echo Check free disk space and folder permissions.
>>"%LOG%" echo ERROR: pet copy failed with code %ERRORLEVEL%
goto :finish_error

:finish_error
echo Diagnostic log: %LOG%
echo.
pause
exit /b 1
