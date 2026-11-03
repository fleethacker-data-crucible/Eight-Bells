# Fake Lazarette 5 for tests. It implements only the functions in Lazarette's INTEGRATION.md contract and holds no real
# secrets: every "secret" is the text fake-secret-for-<service>. State lives in environment variables because the real
# vault keeps its state across dot-sources and a fresh dot-source here must see the same state.
#   FAKE_ARC_UNLOCKED=1   the vault is already open
#   FAKE_ARC_PASS=ok      Unlock-ArcVaultInteractive succeeds (stands in for typing the right passphrase)
#   FAKE_ARC_MISSING      a service name that does not exist
#   FAKE_ARC_EMPTY        a service name whose secret is empty
function Test-ArcVaultUnlocked{return ($env:FAKE_ARC_UNLOCKED -eq '1')}
function Unlock-ArcVaultInteractive{
  if($env:FAKE_ARC_PASS -eq 'ok'){$env:FAKE_ARC_UNLOCKED='1';return $true}
  return $false
}
function Get-ArcSecret{
  param([Parameter(Mandatory=$true)][string]$Service,[string]$User,[string]$Field)
  if(!(Test-ArcVaultUnlocked)){throw 'Vault is locked'}
  if($Service -eq $env:FAKE_ARC_MISSING){throw 'No item matches'}
  if($Service -eq $env:FAKE_ARC_EMPTY){return ''}
  return ('fake-secret-for-'+$Service)
}
function Get-ArcItemNames{return @()}
function Lock-ArcVault{$env:FAKE_ARC_UNLOCKED='0'}
