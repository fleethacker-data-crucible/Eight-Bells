<#
.SYNOPSIS
  Stops every running LogHawk server for this Windows user.
.DESCRIPTION
  LogHawk normally stops itself shortly after its browser tab closes, or from End session in the UI.
  This is the fallback: it reads the runtime files each server writes under
  %LOCALAPPDATA%\LogHawk\logs and %LOCALAPPDATA%\LogHawk-LocalDev\logs (loghawk-server-<pid>.json),
  stops those processes, then looks for any other PowerShell still running Start-LogHawk.ps1.
  Stale runtime files (dead pid) are deleted.
.PARAMETER Quiet
  Print nothing unless something was stopped.
.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Stop-LogHawk.ps1
#>
[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LogHawk-Process.ps1')
$stopped=@(Stop-LogHawkProcesses)
if($stopped.Count -gt 0){
  foreach($p in $stopped){Write-Host ('Stopped LogHawk '+(Format-LogHawkProcess $p)+'.') -ForegroundColor Yellow}
}elseif(!$Quiet){
  Write-Host 'No LogHawk server is running.' -ForegroundColor DarkGray
}
