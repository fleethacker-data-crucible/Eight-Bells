# Fake Lazarette 5 for tests. It implements only the functions in Lazarette's INTEGRATION.md contract and holds no real
# secrets: every "secret" is the text fake-secret-for-<service>. State lives in environment variables because the real
# vault keeps its state across dot-sources and a fresh dot-source here must see the same state.
#   FAKE_LAZARETTE_UNLOCKED=1   the vault is already open
#   FAKE_LAZARETTE_PASS=ok      Unlock-LazaretteVaultInteractive succeeds (stands in for typing the right passphrase)
#   FAKE_LAZARETTE_MISSING      a service name that does not exist
#   FAKE_LAZARETTE_EMPTY        a service name whose secret is empty
function Test-LazaretteVaultUnlocked{return ($env:FAKE_LAZARETTE_UNLOCKED -eq '1')}
function Unlock-LazaretteVaultInteractive{
  if($env:FAKE_LAZARETTE_PASS -eq 'ok'){$env:FAKE_LAZARETTE_UNLOCKED='1';return $true}
  return $false
}
function Get-LazaretteSecret{
  param([Parameter(Mandatory=$true)][string]$Service,[string]$User,[string]$Field)
  if(!(Test-LazaretteVaultUnlocked)){throw 'Vault is locked'}
  if($Service -eq $env:FAKE_LAZARETTE_MISSING){throw 'No item matches'}
  if($Service -eq $env:FAKE_LAZARETTE_EMPTY){return ''}
  return ('fake-secret-for-'+$Service)
}
function Get-LazaretteItemNames{return @()}
function Lock-LazaretteVault{$env:FAKE_LAZARETTE_UNLOCKED='0'}
