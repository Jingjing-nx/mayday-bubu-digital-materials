@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG=%TEMP%\BubuPet-install.log"
set "PET_SOURCE=%ROOT%\pet\bubu-office"
set "PET_SPRITE=spritesheet-win-v1.0.5.webp"

if defined CODEX_HOME (
  set "CODEX_DIR=%CODEX_HOME%"
) else (
  set "CODEX_DIR=%USERPROFILE%\.codex"
)
set "PET_DEST=%CODEX_DIR%\pets\bubu-office"
set "PET_STAGE=%CODEX_DIR%\pets\.bubu-office-installing"

>"%LOG%" echo Bubu Windows installer open-source V1.0.5
>>"%LOG%" echo Started: %DATE% %TIME%
>>"%LOG%" echo OS: %OS%
>>"%LOG%" echo Architecture: %PROCESSOR_ARCHITECTURE%
>>"%LOG%" echo Package files: runtime checked
>>"%LOG%" echo Codex home: configured for current user

echo.
echo Bubu Windows installer V1.0.5
echo ----------------------
if exist "%ROOT%\CODEX-ONLY.txt" (
  echo Panel: Codex quota only ^(no BTC/ETH^)
) else (
  echo Panel: Codex quota + BTC/ETH
)

if not defined USERPROFILE goto :no_profile
if not exist "%PET_SOURCE%\pet.json" goto :missing_files
if not exist "%PET_SOURCE%\%PET_SPRITE%" goto :missing_files

echo Closing ChatGPT/Codex so the new pet selection cannot be overwritten...
>>"%LOG%" echo Closing running desktop clients before pet replacement
taskkill.exe /F /T /IM ChatGPT.exe >>"%LOG%" 2>&1
taskkill.exe /F /T /IM Codex.exe >>"%LOG%" 2>&1
taskkill.exe /F /T /IM OpenAI.exe >>"%LOG%" 2>&1
timeout.exe /T 2 /NOBREAK >nul 2>&1
cmd.exe /d /c exit 0

if not exist "%CODEX_DIR%\pets" mkdir "%CODEX_DIR%\pets" >>"%LOG%" 2>&1
if errorlevel 1 goto :copy_failed
if exist "%PET_STAGE%" rmdir /S /Q "%PET_STAGE%" >>"%LOG%" 2>&1
if exist "%PET_STAGE%" goto :copy_failed
mkdir "%PET_STAGE%" >>"%LOG%" 2>&1
if errorlevel 1 goto :copy_failed

xcopy "%PET_SOURCE%\*" "%PET_STAGE%\" /E /I /H /R /Y >>"%LOG%" 2>&1
if errorlevel 1 goto :copy_failed

if not exist "%PET_STAGE%\pet.json" goto :copy_failed
if not exist "%PET_STAGE%\%PET_SPRITE%" goto :copy_failed
fc.exe /B "%PET_SOURCE%\pet.json" "%PET_STAGE%\pet.json" >nul 2>&1
if errorlevel 1 goto :copy_failed
fc.exe /B "%PET_SOURCE%\%PET_SPRITE%" "%PET_STAGE%\%PET_SPRITE%" >nul 2>&1
if errorlevel 1 goto :copy_failed

if exist "%PET_DEST%" rmdir /S /Q "%PET_DEST%" >>"%LOG%" 2>&1
if exist "%PET_DEST%" goto :copy_failed
move /Y "%PET_STAGE%" "%PET_DEST%" >>"%LOG%" 2>&1
if errorlevel 1 goto :copy_failed
if not exist "%PET_DEST%\pet.json" goto :copy_failed
if not exist "%PET_DEST%\%PET_SPRITE%" goto :copy_failed

echo [OK] Bubu pet files were replaced and verified.
>>"%LOG%" echo Pet install: replaced and binary verified

where powershell.exe >nul 2>&1
if errorlevel 1 goto :selection_skipped
if not exist "%ROOT%\windows\select-pet.ps1" goto :selection_skipped
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\windows\select-pet.ps1" -CodexHome "%CODEX_DIR%" >>"%LOG%" 2>&1
if errorlevel 1 goto :selection_skipped
echo [OK] Bubu was selected as the active pet.
>>"%LOG%" echo Pet selection: OK
goto :selection_done

:selection_skipped
echo [NOTE] Automatic pet selection was unavailable. Select Bubu once in the pet picker.
>>"%LOG%" echo Pet selection: SKIPPED

:selection_done

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
echo [OK] Pet-only compatibility mode finished.
echo Reopen ChatGPT/Codex. If needed, choose Bubu once in the pet picker.
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
echo Reopen ChatGPT/Codex. Bubu should already be selected.

:finish_ok
echo.
echo Log: %LOG%
echo.
if /I "%BUBU_INSTALL_NONINTERACTIVE%"=="1" exit /b 0
pause
exit /b 0

:no_profile
echo [ERROR] Windows USERPROFILE is unavailable.
>>"%LOG%" echo ERROR: USERPROFILE unavailable
goto :finish_error

:missing_files
echo [ERROR] Package files are incomplete. Extract the whole ZIP first.
echo Do not run the installer from inside the ZIP preview.
>>"%LOG%" echo ERROR: package files missing
goto :finish_error

:copy_failed
if exist "%PET_STAGE%" rmdir /S /Q "%PET_STAGE%" >>"%LOG%" 2>&1
echo [ERROR] Bubu could not be copied to the Codex pet folder.
echo Check free disk space and folder permissions.
>>"%LOG%" echo ERROR: pet copy failed with code %ERRORLEVEL%
goto :finish_error

:finish_error
echo Diagnostic log: %LOG%
echo.
if /I "%BUBU_INSTALL_NONINTERACTIVE%"=="1" exit /b 1
pause
exit /b 1
