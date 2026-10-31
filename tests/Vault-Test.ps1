param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# Lazarette key lookup by item name, against a fake Lazarette (tests\fixtures\fake-arc). No real vault and no real secret.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $Root 'EightBells-Vault.ps1')
$fakeArc=Join-Path $PSScriptRoot 'fixtures\fake-arc'
$names='ARC_PATH','ARC_ROOT','ARC_HOME','FAKE_ARC_UNLOCKED','FAKE_ARC_PASS','FAKE_ARC_MISSING','FAKE_ARC_EMPTY'
$saved=@{};foreach($n in $names){$saved[$n]=[Environment]::GetEnvironmentVariable($n)}
function Reset-FakeArc{foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$null)};$env:ARC_PATH=$fakeArc}
function Get-Message([scriptblock]$Call){try{& $Call|Out-Null}catch{return $_.Exception.Message};return $null}
$sandbox=New-TestSandbox
$svc=$null;$fake=$null
try{
  # ---- unit: the contract ----
  Reset-FakeArc
  Assert-True ((Find-EightBellsArcRoot) -eq (Resolve-Path $fakeArc).Path) 'ARC_PATH must be found first'
  $env:FAKE_ARC_UNLOCKED='1'
  Assert-True ((Get-EightBellsVaultSecret -ItemName 'ai-api-key') -eq 'fake-secret-for-ai-api-key') 'An unlocked vault returns the item by name'
  Reset-FakeArc
  $m=Get-Message {Get-EightBellsVaultSecret -ItemName 'ai-api-key'}
  Assert-True ($m -match 'locked' -and $m -notmatch 'fake-secret') 'A locked vault without a console must fail with a plain message'
  $env:FAKE_ARC_PASS='ok'
  Assert-True ((Get-EightBellsVaultSecret -ItemName 'ai-api-key' -Interactive) -eq 'fake-secret-for-ai-api-key') 'Interactive unlock then read'
  Reset-FakeArc;$env:FAKE_ARC_PASS='wrong'
  $m=Get-Message {Get-EightBellsVaultSecret -ItemName 'ai-api-key' -Interactive}
  Assert-True ($m -match 'stayed locked') 'A failed unlock must stop, never fall back'
  Reset-FakeArc;$env:FAKE_ARC_UNLOCKED='1';$env:FAKE_ARC_MISSING='gone-item'
  $m=Get-Message {Get-EightBellsVaultSecret -ItemName 'gone-item'}
  Assert-True ($m -match 'gone-item' -and $m -match 'could not be read') 'A missing item names the item, not a secret'
  Reset-FakeArc;$env:FAKE_ARC_UNLOCKED='1';$env:FAKE_ARC_EMPTY='blank-item'
  $m=Get-Message {Get-EightBellsVaultSecret -ItemName 'blank-item'}
  Assert-True ($m -match 'is empty') 'An empty secret is refused'
  # Nothing found: child process with no ARC_* variables and an empty profile folder.
  $empty=Join-Path $sandbox 'empty-profile';New-Item -ItemType Directory -Force -Path $empty|Out-Null
  $child=Join-Path $sandbox 'child.ps1'
  Set-Content -LiteralPath $child -Value ('. "'+(Join-Path $Root 'EightBells-Vault.ps1')+'"; $env:USERPROFILE="'+$empty+'"; foreach($n in "ARC_PATH","ARC_ROOT","ARC_HOME"){Remove-Item "Env:\$n" -ErrorAction SilentlyContinue}; try{Get-EightBellsVaultSecret -ItemName x}catch{$_.Exception.Message}')
  $msg=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $child) -join ' '
  Assert-True ($msg -match 'was not found') 'Without Lazarette the message says so'
  Write-Host 'PASS: vault lookup follows the Lazarette contract (find, unlock rules, read by name, missing, empty, not found)'

  # ---- service: key read at start, used for the model call, never stored ----
  $fake=Start-FakeLlm $Root $sandbox 'ok'
  Reset-FakeArc;$env:FAKE_ARC_UNLOCKED='1'
  $svc=Start-TestService $Root $sandbox 'synthetic-vault-test-token-654' @{EIGHTBELLS_LAZARETTE='1';EIGHTBELLS_LAZARETTE_ITEM_AI='test-item';ARC_PATH=$fakeArc;FAKE_ARC_UNLOCKED='1'}
  $cfg=Post-Json $svc '/api/ai/config' @{endpoint=$fake.Endpoint;model='synthetic-model';useVault=$true}
  Assert-True ($cfg.configured -eq $true) 'Vault key should configure the endpoint'
  Assert-True (-not ($cfg|ConvertTo-Json).Contains('fake-secret')) 'The response must not echo the vault key'
  $log=Post-Json $svc '/api/import' @{name='Synthetic vault log';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()};sourceType='digital-text'}
  $null=Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}
  $seen=@(Get-LlmRequests $fake)
  Assert-True ($seen[$seen.Count-1].auth -eq 'Bearer fake-secret-for-test-item') 'The model call must carry the key from the configured item name'
  $state=Invoke-RestMethod -Uri ($svc.Url+'/api/state') -Headers $svc.Headers
  Assert-True (-not (($state|ConvertTo-Json -Depth 30).Contains('fake-secret'))) 'The vault key must never be stored'
  # A hand-typed key still works, and a non-boolean flag does not select the vault.
  $null=Post-Json $svc '/api/ai/config' @{endpoint=$fake.Endpoint;model='m';key='manual-key'}
  $null=Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}
  $seen=@(Get-LlmRequests $fake);Assert-True ($seen[$seen.Count-1].auth -eq 'Bearer manual-key') 'The manual key path is unchanged'
  $null=Post-Json $svc '/api/ai/config' @{endpoint=$fake.Endpoint;model='m';useVault='true'}
  $null=Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}
  $seen=@(Get-LlmRequests $fake);Assert-True ($seen[$seen.Count-1].auth -eq '') 'A non-boolean useVault must not select the vault key'
  Write-Host 'PASS: service reads the key by item name, sends it to the model, never echoes or stores it, manual key unchanged'

  # ---- service: locked vault and feature off ----
  Stop-TestProcess $svc;$svc=$null
  $svc=Start-TestService $Root $sandbox 'synthetic-vault-test-token-654' @{EIGHTBELLS_LAZARETTE='1';ARC_PATH=$fakeArc;FAKE_ARC_UNLOCKED='0'}
  Assert-HttpStatus {Post-Json $svc '/api/ai/config' @{endpoint=$fake.Endpoint;model='m';useVault=$true}} 400 'Vault key requested while Lazarette was locked at start'
  Stop-TestProcess $svc;$svc=$null
  $svc=Start-TestService $Root $sandbox 'synthetic-vault-test-token-654' @{ARC_PATH=$fakeArc;FAKE_ARC_UNLOCKED='1'}
  Assert-HttpStatus {Post-Json $svc '/api/ai/config' @{endpoint=$fake.Endpoint;model='m';useVault=$true}} 400 'Vault key requested while the feature is off'
  Write-Host 'PASS: a locked vault or the feature being off gives a clear 400 and the server still starts'
}finally{
  foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$saved[$n])}
  Stop-TestProcess $svc;Stop-TestProcess $fake
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
