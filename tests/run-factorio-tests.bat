@echo off
setlocal EnableExtensions

set "REPO=%~dp0.."
set "FACTORIO_EXE=D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe"
set "TEST_ROOT=%LOCALAPPDATA%\FactorioFarmingProductionTests"
set "RUN_ROOT=%TEST_ROOT%\current"
set "MOD_ROOT=%RUN_ROOT%\mods"
set "WRITE_ROOT=%RUN_ROOT%\write-data"
set "RESULT=%WRITE_ROOT%\script-output\factorio-farming-tests\result.json"

if not exist "%FACTORIO_EXE%" (
  echo Factorio was not found at %FACTORIO_EXE%
  exit /b 1
)

if exist "%RUN_ROOT%" rmdir /s /q "%RUN_ROOT%"
mkdir "%MOD_ROOT%\factorio-farming_0.1.0" || exit /b 1
mkdir "%MOD_ROOT%\factorio-farming-tests_0.1.0" || exit /b 1
mkdir "%WRITE_ROOT%" || exit /b 1

robocopy "%REPO%" "%MOD_ROOT%\factorio-farming_0.1.0" /E /XD .git tests /XF dashboard.html >nul
if errorlevel 8 exit /b 1
robocopy "%REPO%\tests\factorio-farming-tests" "%MOD_ROOT%\factorio-farming-tests_0.1.0" /E >nul
if errorlevel 8 exit /b 1

>"%MOD_ROOT%\mod-list.json" echo {"mods":[{"name":"base","enabled":true},{"name":"factorio-farming","enabled":true},{"name":"factorio-farming-tests","enabled":true}]}
>"%RUN_ROOT%\config.ini" echo [path]
>>"%RUN_ROOT%\config.ini" echo read-data=__PATH__executable__/../../data
>>"%RUN_ROOT%\config.ini" echo write-data=%WRITE_ROOT:\=/%

"%FACTORIO_EXE%" --config "%RUN_ROOT%\config.ini" --mod-directory "%MOD_ROOT%" --disable-audio --create "%RUN_ROOT%\slice-test.zip"
if errorlevel 1 exit /b 1

"%FACTORIO_EXE%" --config "%RUN_ROOT%\config.ini" --mod-directory "%MOD_ROOT%" --disable-audio --benchmark "%RUN_ROOT%\slice-test.zip" --benchmark-ticks 12000 --benchmark-runs 1 >"%RUN_ROOT%\benchmark.log" 2>&1
if errorlevel 1 (
  type "%RUN_ROOT%\benchmark.log"
  exit /b 1
)

if not exist "%RESULT%" (
  type "%RUN_ROOT%\benchmark.log"
  echo Test result was not written.
  exit /b 1
)

findstr /C:"\"passed\":true" "%RESULT%" >nul
if errorlevel 1 (
  type "%RESULT%"
  exit /b 1
)

type "%RESULT%"
echo.
echo Factorio production slice tests passed.
