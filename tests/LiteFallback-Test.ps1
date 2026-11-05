param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# Lazarette Lite fallback for the AI key: the vault loader against a Lite-shaped provider
# (tests\fixtures\fake-lazarette-lite). No real vault, no real Credential Manager, no real secret.
# Lite keeps one secret per item in Windows Credential Manager, has no lock, and its unlock is a
# no-op success - so the loader must read without a Test-LazaretteVaultUnlocked command existing.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $Root 'EightBells-Vault.ps1')
$fakeLite=Join-Path $PSScriptRoot 'fixtures\fake-lazarette-lite'
$names='LAZARETTE_PATH','FAKE_LITE_MISSING','FAKE_LITE_EMPTY'
$saved=@{};foreach($n in $names){$saved[$n]=[Environment]::GetEnvironmentVariable($n)}
function Reset-FakeLite{foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$null)};$env:LAZARETTE_PATH=$fakeLite}
function Get-Message([scriptblock]$Call){try{& $Call|Out-Null}catch{return $_.Exception.Message};return $null}
try{
  Reset-FakeLite
  Assert-True ((Find-EightBellsLazaretteRoot) -eq (Resolve-Path $fakeLite).Path) 'LAZARETTE_PATH must find the Lite folder first'
  . (Join-Path $fakeLite 'lib\Lazarette.ps1')
  Assert-True (-not (Get-Command Test-LazaretteVaultUnlocked -ErrorAction SilentlyContinue)) 'A Lite-shaped provider defines no lock check'
  Assert-True ((Get-EightBellsVaultSecret -ItemName 'ai-api-key') -eq 'fake-lite-secret-for-ai-api-key') 'Lite fallback returns the item by name with no unlock step'
  Assert-True ((Get-EightBellsVaultSecret -ItemName 'ai-api-key' -Interactive) -eq 'fake-lite-secret-for-ai-api-key') 'Interactive read against Lite also returns the item (unlock is a no-op)'
  Reset-FakeLite;$env:FAKE_LITE_MISSING='gone-item'
  $m=Get-Message {Get-EightBellsVaultSecret -ItemName 'gone-item'}
  Assert-True ($m -match 'gone-item' -and $m -match 'could not be read' -and $m -notmatch 'fake-lite-secret') 'A missing Lite item names the item, not a secret'
  Reset-FakeLite;$env:FAKE_LITE_EMPTY='blank-item'
  $m=Get-Message {Get-EightBellsVaultSecret -ItemName 'blank-item'}
  Assert-True ($m -match 'is empty') 'An empty Lite secret is refused'
  # Boundary: Lite keeps one secret per item. A field read must fail, never silently return the secret.
  . (Join-Path $fakeLite 'lib\Lazarette.ps1')
  $m=Get-Message {Get-LazaretteSecret -Service 'ai-api-key' -Field 'Username'}
  Assert-True ($m -match 'field' -and $m -notmatch 'fake-lite-secret') 'A -Field read against Lite fails without revealing the secret'
  Write-Host 'PASS: vault loader reads the AI key from a Lite-shaped provider (no lock, secret-only, field refused)'
}finally{
  foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$saved[$n])}
}