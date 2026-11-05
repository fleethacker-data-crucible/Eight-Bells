param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# Opt-in intelligence router (Fairlead): off by default, local-only when on, manual endpoint unchanged.
# Uses a fake loopback model in place of the router; no live Fairlead is needed.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$sandbox=New-TestSandbox
$svc=$null;$fake=$null;$other=$null;$deny=$null;$nokey=$null
try{
  $fake=Start-FakeLlm $Root $sandbox 'ok'
  $svc=Start-TestService $Root $sandbox 'synthetic-router-test-token-321' @{EIGHTBELLS_FAIRLEAD_URL=$fake.Endpoint;EIGHTBELLS_TEST_FAIRLEAD_KEY='synthetic-fairlead-key-1'}
  $url=$svc.Url

  # ---- off by default and the manual endpoint still works ----
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId='x';consent=$true}} 400 'Model call before any configuration (router must be off by default)'
  $r=Post-Json $svc '/api/ai/config' @{router='true'}
  Assert-True ($r.configured -eq $false) 'A non-boolean router flag must not enable router mode'
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId='x';consent=$true}} 400 'Model call after a non-boolean router flag'
  Write-Host 'PASS: router is off by default and a non-boolean flag does not enable it'

  # ---- router mode: local address, default model name, no key ----
  $r=Post-Json $svc '/api/ai/config' @{router=$true}
  Assert-True ($r.configured -eq $true -and $r.router -eq $true -and $r.model -eq 'auto') 'Router mode should configure the default model name'
  Write-Host 'PASS: router mode configures from the local router address'

  # ---- consent still required; requests are local-only and keyless ----
  $log=Post-Json $svc '/api/import' @{name='Synthetic router log';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()};sourceType='digital-text'}
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId=$log.id}} 403 'Router run without consent'
  $run=Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}
  Assert-True ($run.verified -eq $false) 'Router output must be marked unverified'
  $seen=@(Get-LlmRequests $fake)
  Assert-True ($seen.Count -eq 1) 'Exactly one upstream call per consented router request'
  Assert-True ($seen[0].path -eq '/v1/chat/completions') 'Router requests go to the chat completions path'
  Assert-True ($seen[0].privacy -eq 'local') 'Router requests must carry the local-only privacy header'
  Assert-True ($seen[0].auth -eq 'Bearer synthetic-fairlead-key-1') 'Router mode sends this app''s own Fairlead key, never a provider key'
  Assert-True ($seen[0].body.model -eq 'auto') 'Router requests use the router model name'
  Write-Host 'PASS: router requests need consent, carry the app Fairlead key and are sent local-only by default'

  # ---- the page can allow cloud models for synthetic data: only an explicit false removes the local-only header ----
  $r=Post-Json $svc '/api/ai/config' @{router=$true;local='false'}
  Assert-True ($r.local -eq $true) 'A non-boolean local flag must keep local-only'
  $r=Post-Json $svc '/api/ai/config' @{router=$true;local=$false;model='gpt-synthetic'}
  Assert-True ($r.local -eq $false -and $r.model -eq 'gpt-synthetic') 'An explicit false allows cloud models and keeps the chosen model'
  $null=Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}
  $seen=@(Get-LlmRequests $fake);$last=$seen[$seen.Count-1]
  Assert-True ($last.privacy -eq '' -and $last.auth -eq 'Bearer synthetic-fairlead-key-1' -and $last.body.model -eq 'gpt-synthetic') 'Cloud-allowed router requests drop the local header but keep the app key'
  $st=Invoke-RestMethod -Uri ($svc.Url+'/api/ai/router') -Headers $svc.Headers
  Assert-True ($st.reachable -eq $true -and $st.keyInstalled -eq $true -and $st.active -eq $true -and $st.local -eq $false -and $st.keyTarget -eq 'Fairlead/EightBells') 'Router status reports reachable, key installed, active and the target name'
  Assert-True (-not (($st|ConvertTo-Json).Contains('synthetic-fairlead-key'))) 'Router status must never contain the key'
  Write-Host 'PASS: local-only is the default, cloud needs an explicit choice, and the status route never shows the key'
  $null=Post-Json $svc '/api/ai/config' @{router=$true}

  # ---- switching back to the manual endpoint removes the router header ----
  $m=Post-Json $svc '/api/ai/config' @{endpoint=$fake.Endpoint;model='synthetic-model';key='synthetic-key-123'}
  Assert-True ($m.configured -eq $true -and -not $m.router) 'Manual configuration must leave router mode'
  $null=Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}
  $seen=@(Get-LlmRequests $fake)
  $last=$seen[$seen.Count-1]
  Assert-True ($last.privacy -eq '' -and $last.auth -eq 'Bearer synthetic-key-123') 'The manual endpoint must not gain the router header'
  Write-Host 'PASS: manual endpoint is unchanged after router mode'

  # ---- a router address that is not local is refused ----
  Stop-TestProcess $svc;$svc=$null
  $other=Start-TestService $Root $sandbox 'synthetic-router-test-token-322' @{EIGHTBELLS_FAIRLEAD_URL='https://router.example.invalid/v1/chat/completions'}
  Assert-HttpStatus {Post-Json $other '/api/ai/config' @{router=$true}} 400 'A non-local router address'
  Write-Host 'PASS: a non-local router address is refused'

  # ---- no key installed: no Authorization header is sent; a refusal says how to install the key ----
  Stop-TestProcess $other;$other=$null;Start-Sleep -Milliseconds 500
  $deny=Start-FakeLlm $Root $sandbox 'deny'
  $nokey=Start-TestService $Root $sandbox 'synthetic-router-test-token-323' @{EIGHTBELLS_FAIRLEAD_URL=$deny.Endpoint;EIGHTBELLS_TEST_FAIRLEAD_KEY='(none)'}
  $st=Invoke-RestMethod -Uri ($nokey.Url+'/api/ai/router') -Headers $nokey.Headers
  Assert-True ($st.keyInstalled -eq $false) 'Status must say the key is not installed'
  $null=Post-Json $nokey '/api/ai/config' @{router=$true}
  $log2=Post-Json $nokey '/api/import' @{name='Synthetic router log 2';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()}}
  $msg=''
  try{Post-Json $nokey '/api/ai/run' @{logId=$log2.id;consent=$true}|Out-Null}catch{$msg=[string]$_.ErrorDetails.Message}
  Assert-True ($msg -match 'Install for this app' -and $msg -match 'EightBells') 'A refused router call must say how to install the key'
  Assert-True ($msg -notmatch 'synthetic key refused') 'The upstream error text must not be echoed'
  $seen=@(Get-LlmRequests $deny)
  Assert-True ($seen.Count -eq 1 -and $seen[0].auth -eq '') 'Without an installed key no Authorization header is sent'
  Write-Host 'PASS: no installed key sends no header, and a refusal explains how to install one'
}finally{
  Stop-TestProcess $svc;Stop-TestProcess $fake;Stop-TestProcess $other;Stop-TestProcess $deny;Stop-TestProcess $nokey
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
