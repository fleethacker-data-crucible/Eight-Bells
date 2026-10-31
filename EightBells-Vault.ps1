# Reads the AI key from Lazarette by item name, following Lazarette's contract (docs/INTEGRATION.md in that repo):
# find lib\Arc.ps1, dot-source it, unlock in the console, then Get-ArcSecret -Service <item name>.
# Config holds the item NAME only (EIGHTBELLS_LAZARETTE_ITEM_AI, default ai-api-key); the secret lives in memory and
# is never written to the store, a log, a response or a file. Unlocking is interactive by design, so this only
# prompts when asked to (a visible console), and otherwise needs a vault that is already unlocked.
function Find-EightBellsArcRoot{
  # First match wins: ARC_PATH, ARC_ROOT, ARC_HOME, an 'arc' folder beside this repo, then $HOME\Projects\arc.
  $candidates=@($env:ARC_PATH,$env:ARC_ROOT,$env:ARC_HOME,(Join-Path (Split-Path $PSScriptRoot -Parent) 'arc'),(Join-Path $env:USERPROFILE 'Projects\arc'))
  foreach($p in $candidates){
    if($p -and (Test-Path -LiteralPath (Join-Path $p 'lib\Arc.ps1'))){return (Resolve-Path -LiteralPath $p).Path}
  }
  return $null
}
# Returns the secret as a string. Throws a plain message (never containing the secret) when Lazarette cannot be used.
function Get-EightBellsVaultSecret([Parameter(Mandatory=$true)][string]$ItemName,[switch]$Interactive){
  $arcRoot=Find-EightBellsArcRoot
  if(!$arcRoot){throw 'Lazarette was not found (set ARC_PATH to its folder).'}
  . (Join-Path $arcRoot 'lib\Arc.ps1')
  if(!(Test-ArcVaultUnlocked)){
    if(!$Interactive){throw 'Lazarette is locked and this console cannot prompt. Start Eight Bells from a visible console (EightBells-CLI.bat -Lazarette) to unlock it.'}
    if(!(Unlock-ArcVaultInteractive)){throw 'Lazarette stayed locked.'}
  }
  try{$secret=Get-ArcSecret -Service $ItemName}
  catch{throw ('Lazarette item "'+$ItemName+'" could not be read (missing, ambiguous or locked).')}
  if([string]::IsNullOrEmpty([string]$secret)){throw ('Lazarette item "'+$ItemName+'" is empty.')}
  return [string]$secret
}
