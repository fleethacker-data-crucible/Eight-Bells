# Fake Lazarette Lite for tests. It mirrors the Lite provider's semantics only: secrets come from a fake
# backend keyed by service name (no Windows Credential Manager, no real secret), there is no vault and
# therefore no lock - Test-LazaretteVaultUnlocked is deliberately NOT defined, exactly as in real Lite's
# lib\Lazarette.ps1 - and Unlock-LazaretteVaultInteractive is a no-op success. Custom fields are refused,
# as Lite's Get-LiteSecret throws for any -Field. State lives in environment variables, like fake-lazarette.
#   FAKE_LITE_MISSING      a service name that does not exist
#   FAKE_LITE_EMPTY        a service name whose secret is empty
# Real Lite's lib\Lazarette.ps1 also Import-Modules its manifest on dot-source; this fixture does not,
# because there is no module here - the loader under test only needs the three functions below.
function Unlock-LazaretteVaultInteractive{
  param([string]$DataDir)
  if($DataDir){throw 'Lazarette Lite uses Windows Credential Manager and has no vault directory.'}
  return $true
}
function Get-LazaretteSecret{
  param([Parameter(Mandatory=$true)][string]$Service,[string]$User,[string]$Field)
  if($Field){throw ("Lazarette Lite item '"+$Service+"' has no field '"+$Field+"'. Lite keeps one secret per item; custom fields are a Lazarette feature.")}
  if($Service -eq $env:FAKE_LITE_MISSING){throw 'No item matches'}
  if($Service -eq $env:FAKE_LITE_EMPTY){return ''}
  return ('fake-lite-secret-for-'+$Service)
}
function Get-LazaretteItemNames{return @()}