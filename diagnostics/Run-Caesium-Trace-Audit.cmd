@echo off
setlocal
cd /d "%~dp0"
echo Caesium Portable Trace Audit - no automatic cleanup/deletion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Audit-CaesiumPortable.ps1"
set "result=%ERRORLEVEL%"
if not "%result%"=="0" echo Audit stopped with error code %result%.
echo.
pause
exit /b %result%
