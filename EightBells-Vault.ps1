# Reads the AI key from Lazarette by item name, following Lazarette 5's contract (docs/INTEGRATION.md in that repo):
# find lib\Lazarette.ps1, dot-source it, unlock in the console, then Get-LazaretteSecret -Service <item name>.
# Config holds the item NAME only (EIGHTBELLS_LAZARETTE_ITEM_AI, default ai-api-key); the secret lives in memory and
# is never written to the store, a log, a response or a file. Unlocking is interactive by design, so this only
# prompts when asked to (a visible console), and otherwise needs a vault that is already unlocked.
function Find-EightBellsLazaretteRoot{
  # First match wins: LAZARETTE_PATH, a Lazarette folder beside this repo, then $USERPROFILE\Projects\Lazarette.
  $candidates=@($env:LAZARETTE_PATH,(Join-Path (Split-Path $PSScriptRoot -Parent) 'Lazarette'),(Join-Path $env:USERPROFILE 'Projects\Lazarette'))
  foreach($p in $candidates){
    if($p -and (Test-Path -LiteralPath (Join-Path $p 'lib\Lazarette.ps1'))){return (Resolve-Path -LiteralPath $p).Path}
  }
  return $null
}
# Returns the secret as a string. Throws a plain message (never containing the secret) when Lazarette cannot be used.
function Get-EightBellsVaultSecret([Parameter(Mandatory=$true)][string]$ItemName,[switch]$Interactive){
  $root=Find-EightBellsLazaretteRoot
  if(!$root){throw 'Lazarette was not found (set LAZARETTE_PATH to its folder).'}
  . (Join-Path $root 'lib\Lazarette.ps1')
  if(!(Test-LazaretteVaultUnlocked)){
    if(!$Interactive){throw 'Lazarette is locked and this console cannot prompt. Start Eight Bells from a visible console (EightBells-CLI.bat -Lazarette) to unlock it.'}
    if(!(Unlock-LazaretteVaultInteractive)){throw 'Lazarette stayed locked.'}
  }
  try{$secret=Get-LazaretteSecret -Service $ItemName}
  catch{throw ('Lazarette item "'+$ItemName+'" could not be read (missing, ambiguous or locked).')}
  if([string]::IsNullOrEmpty([string]$secret)){throw ('Lazarette item "'+$ItemName+'" is empty.')}
  return [string]$secret
}
