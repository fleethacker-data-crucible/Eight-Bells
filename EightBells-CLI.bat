@echo off
rem Options: --replace, --stay (see Launch-EightBells.bat)
cd /d "%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Start-EightBells.ps1" -Diagnostics %*
pause
