<#
.SYNOPSIS
  Stops every running Eight Bells server for this Windows user.
.DESCRIPTION
  Eight Bells normally stops itself shortly after its browser tab closes, or from End session in the UI.
  This is the fallback: it reads the runtime files each server writes under
  %LOCALAPPDATA%\EightBells\logs and %LOCALAPPDATA%\EightBells-LocalDev\logs (eightbells-server-<pid>.json),
  stops those processes, then looks for any other PowerShell still running Start-EightBells.ps1.
  A server started by an older LogHawk build is found too: its loghawk-server-<pid>.json under
  %LOCALAPPDATA%\LogHawk(-LocalDev)\logs, or a PowerShell running Start-LogHawk.ps1.
  Stale runtime files (dead pid) are deleted.
.PARAMETER Quiet
  Print nothing unless something was stopped.
.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Stop-EightBells.ps1
#>
[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'EightBells-Process.ps1')
$stopped=@(Stop-EightBellsProcesses)
if($stopped.Count -gt 0){
  foreach($p in $stopped){Write-Host ('Stopped Eight Bells '+(Format-EightBellsProcess $p)+'.') -ForegroundColor Yellow}
}elseif(!$Quiet){
  Write-Host 'No Eight Bells server is running.' -ForegroundColor DarkGray
}
