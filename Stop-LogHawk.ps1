# Former LogHawk stop script name, kept so existing scripts and shortcuts keep working.
# Use Stop-EightBells.ps1; it also stops servers started by an older LogHawk build.
[CmdletBinding()]
param([switch]$Quiet)
& (Join-Path $PSScriptRoot 'Stop-EightBells.ps1') -Quiet:$Quiet
