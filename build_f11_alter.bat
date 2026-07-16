@echo off
REM ---------------------------------------------------------------------------
REM FRENTE 11 - Safe Alter Column - build + test runner (Win32/Debug)
REM ---------------------------------------------------------------------------
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"

set "DUnitX=C:\Program Files (x86)\Embarcadero\Studio\37.0\source\DUnitX"
set "WT=D:\Ecossistema-Axial\developer-friends-backend\.modules\MetaDbDiff\.claude\worktrees\agent-adf15c75296c05eb7"
set "DE=D:\Ecossistema-Axial\developer-friends-backend\.modules\DataEngine"
set "DCC_UnitSearchPath=%DE%\Source\Core;%DE%\Source\Drivers;%WT%\Source\Core;%WT%\Source\Drivers"

msbuild "%WT%\Test Delphi\TestMetaDbDiff.dproj" /t:Build /p:Config=Debug /p:Platform=Win32
if errorlevel 1 (
  echo.
  echo *** BUILD FAILED ***
  exit /b 1
)

echo.
echo *** BUILD OK - running suite ***
"%WT%\Test Delphi\TestMetaDbDiff.exe"
exit /b %errorlevel%
