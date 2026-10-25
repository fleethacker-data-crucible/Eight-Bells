@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0" || exit /b 1
where powershell.exe >nul 2>&1 || (echo Windows PowerShell 5.1 is required. & exit /b 1)
echo [EIGHT BELLS LOCAL DEV] Isolated DPAPI test database. No CAC or live log data.
powershell.exe -NoProfile -NoLogo -STA -File "%~dp0Start-EightBells.ps1" -LocalDev -Diagnostics %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" pause
exit /b %RC%
