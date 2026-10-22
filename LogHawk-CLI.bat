@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Start-LogHawk.ps1" -Diagnostics %*
pause
