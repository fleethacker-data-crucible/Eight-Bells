@echo off
rem eightbells <noun> <verb> [--option value ...] [--json] [--out file] [--yes] [--dry-run]   (see docs\CLI.md)
rem Runs in its own process. It opens no port and starts no server.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0eightbells.ps1" %*
exit /b %ERRORLEVEL%
