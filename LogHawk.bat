@echo off
setlocal
cd /d "%~dp0"
where powershell.exe >nul 2>nul
if errorlevel 1 (echo Windows PowerShell is required.& pause& exit /b 1)
start "" /min powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Start-LogHawk.ps1" -Background
exit /b 0
