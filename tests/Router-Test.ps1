param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# Intelligence router (Fairlead): on by default, local-only, manual endpoint is the override.
# Uses a fake loopback model in place of the router; no live Fairlead is needed.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$sandbox=New-TestSandbox
$svc=$null;$fake=$null;$other=$null;$deny=$null;$nokey=$null;$over=$null;$tok=$null;$imp=$null;$impSvc=$null;$red=$null;$redSvc=$null;$named=$null
try{
  $fake=Start-FakeLlm $Root $sandbox 'ok'
  $svc=Start-TestService $Root $sandbox 'synthetic-router-test-token-321' @{EIGHTBELLS_FAIRLEAD_URL=$fake.Endpoint;EIGHTBELLS_TEST_FAIRLEAD_KEY='synthetic-fairlead-key-1'}
  $url=$svc.Url

  # ---- the router is the provider at start; a non-boolean flag does not change it ----
  $st=Invoke-RestMethod -Uri ($svc.Url+'/api/ai/router') -Headers $svc.Headers
  Assert-True ($st.active -eq $true -and $st.local -eq $true -and $st.model -eq 'auto' -and $st.url -eq $fake.Endpoint -and $st.keySource -eq 'credential-manager') 'The router is the provider at start'
  $r=Post-Json $svc '/api/ai/config' @{router='true'}
  Assert-True ($r.configured -eq $true -and $r.router -eq $true) 'A non-boolean router flag must not leave the router'
  Write-Host 'PASS: router is the default and a non-boolean flag does not change it'

  # ---- router mode: local address, default model name, no provider key ----
  $r=Post-Json $svc '/api/ai/config' @{router=$true}
  Assert-True ($r.configured -eq $true -and $r.router -eq $true -and $r.model -eq 'auto') 'Router mode should configure the default model name'
  Write-Host 'PASS: router mode configures from the local router address'

  # ---- consent still required; requests are local-only and keyless ----
  $log=Post-Json $svc '/api/import' @{name='Synthetic router log';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()};sourceType='digital-text'}
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId=$log.id}} 403 'Router run without consent'
  $run=Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}
  Assert-True ($run.verified -eq $false) 'Router output must be marked unverified'
  $seen=@(Get-LlmRequests $fake)
  $calls=@($seen|Where-Object {$_.path -eq '/v1/chat/completions'})
  $id=@($seen|Where-Object {$_.path -eq '/__fleethacker/id'})
  Assert-True ($calls.Count -eq 1) 'Exactly one chat call per consented router request'
  Assert-True ($id.Count -ge 1 -and $id[0].auth -eq '') 'The identity check is made with no key'
  Assert-True ($calls[0].privacy -eq 'local') 'Router requests must carry the local-only privacy header'
  Assert-True ($calls[0].auth -eq 'Bearer synthetic-fairlead-key-1') 'Router mode sends this app''s own Fairlead key, never a provider key'
  Assert-True ($calls[0].body.model -eq 'auto') 'Router requests use the router model name'
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
  Assert-True ($st.keyInstalled -eq $false -and $st.keySource -eq 'none') 'Status must say the key is not installed'
  $null=Post-Json $nokey '/api/ai/config' @{router=$true}
  $log2=Post-Json $nokey '/api/import' @{name='Synthetic router log 2';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()}}
  $msg=''
  try{Post-Json $nokey '/api/ai/run' @{logId=$log2.id;consent=$true}|Out-Null}catch{$msg=[string]$_.ErrorDetails.Message}
  Assert-True ($msg -match 'Install for this app' -and $msg -match 'EightBells') 'A refused router call must say how to install the key'
  Assert-True ($msg -notmatch 'synthetic key refused') 'The upstream error text must not be echoed'
  $seen=@(Get-LlmRequests $deny)
  $calls=@($seen|Where-Object {$_.path -eq '/v1/chat/completions'})
  Assert-True ($calls.Count -eq 1 -and $calls[0].auth -eq '' -and -not @($seen|Where-Object {$_.auth -match 'Bearer'})) 'Without an installed key no Authorization header is sent'
  Write-Host 'PASS: no installed key sends no header, and a refusal explains how to install one'

  # ---- a manual endpoint override replaces the router; the app-specific name beats LLM_URL ----
  $before=@(Get-LlmRequests $fake).Count
  $over=Start-TestService $Root $sandbox 'synthetic-router-test-token-324' @{EIGHTBELLS_FAIRLEAD_URL='http://127.0.0.1:9/v1/chat/completions';EIGHTBELLS_AI_ENDPOINT_URL=$fake.Endpoint;LLM_URL='http://127.0.0.1:9/v1/chat/completions';EIGHTBELLS_TEST_FAIRLEAD_KEY='synthetic-fairlead-key-1'}
  $st=Invoke-RestMethod -Uri ($over.Url+'/api/ai/router') -Headers $over.Headers
  Assert-True ($st.active -eq $false) 'An endpoint override leaves the router inactive'
  $log3=Post-Json $over '/api/import' @{name='Synthetic override log';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()}}
  $null=Post-Json $over '/api/ai/run' @{logId=$log3.id;consent=$true}
  $seen=@(Get-LlmRequests $fake)
  Assert-True ($seen.Count -eq ($before+1)) 'The override is the only new upstream call'
  $last=$seen[$seen.Count-1]
  Assert-True ($last.path -eq '/v1/chat/completions' -and $last.privacy -eq '' -and $last.auth -eq '') 'The override sends no Fairlead header and no client key'
  Write-Host 'PASS: EIGHTBELLS_AI_ENDPOINT_URL overrides the router and beats LLM_URL'

  # ---- the local token is the client key when Credential Manager has none ----
  $tokenFile=Join-Path $sandbox 'local-token.txt'
  Set-Content -LiteralPath $tokenFile -Value 'synthetic-local-token-1' -Encoding ascii
  $tok=Start-TestService $Root $sandbox 'synthetic-router-test-token-325' @{EIGHTBELLS_FAIRLEAD_URL=$fake.Endpoint;EIGHTBELLS_TEST_FAIRLEAD_KEY='(none)';EIGHTBELLS_TEST_LOCAL_TOKEN_FILE=$tokenFile}
  $st=Invoke-RestMethod -Uri ($tok.Url+'/api/ai/router') -Headers $tok.Headers
  Assert-True ($st.keyInstalled -eq $true -and $st.keySource -eq 'local-token') 'The local token counts as an installed key'
  Assert-True (-not (($st|ConvertTo-Json).Contains('synthetic-local-token'))) 'Router status must never contain the local token'
  $log4=Post-Json $tok '/api/import' @{name='Synthetic token log';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()}}
  $null=Post-Json $tok '/api/ai/run' @{logId=$log4.id;consent=$true}
  $seen=@(Get-LlmRequests $fake)
  Assert-True ($seen[$seen.Count-1].auth -eq 'Bearer synthetic-local-token-1' -and $seen[$seen.Count-1].label -eq 'EightBells') 'Router mode sends the local token and the app label'
  Write-Host 'PASS: local token is used when no credential is installed'

  # ---- an impostor on the port does not receive the key ----
  $imp=Start-FakeLlm $Root $sandbox 'impostor'
  $impSvc=Start-TestService $Root $sandbox 'synthetic-router-test-token-326' @{EIGHTBELLS_FAIRLEAD_URL=$imp.Endpoint;EIGHTBELLS_TEST_FAIRLEAD_KEY='synthetic-fairlead-key-1'}
  $log5=Post-Json $impSvc '/api/import' @{name='Synthetic impostor log';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()}}
  $msg=''
  try{Post-Json $impSvc '/api/ai/run' @{logId=$log5.id;consent=$true}|Out-Null}catch{$msg=[string]$_.ErrorDetails.Message}
  Assert-True ($msg -match 'key was not sent' -and $msg -match 'not Fairlead') 'An impostor is refused before the key is sent'
  Assert-True ($msg -notmatch 'synthetic-fairlead-key') 'The refusal must not contain the key'
  $seen=@(Get-LlmRequests $imp)
  Assert-True (-not @($seen|Where-Object {$_.auth -match 'Bearer'})) 'No request to the impostor carries the key'
  Assert-True (@($seen|Where-Object {$_.path -eq '/__fleethacker/id' -and $_.auth -eq ''}).Count -ge 1) 'The identity request is unauthenticated'
  Write-Host 'PASS: the key is not sent unless the listener identifies itself as Fairlead'

  # ---- a redirect is not followed ----
  $red=Start-FakeLlm $Root $sandbox 'redirect'
  $redSvc=Start-TestService $Root $sandbox 'synthetic-router-test-token-327' @{EIGHTBELLS_FAIRLEAD_URL=$red.Endpoint;EIGHTBELLS_TEST_FAIRLEAD_KEY='synthetic-fairlead-key-1'}
  $log6=Post-Json $redSvc '/api/import' @{name='Synthetic redirect log';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()}}
  $msg=''
  try{Post-Json $redSvc '/api/ai/run' @{logId=$log6.id;consent=$true}|Out-Null}catch{$msg=[string]$_.ErrorDetails.Message}
  Assert-True ($msg -match 'not followed') 'A Fairlead redirect is a failure'
  $chat=@($(Get-LlmRequests $red)|Where-Object {$_.path -eq '/v1/chat/completions'})
  Assert-True ($chat.Count -eq 1 -and $chat[0].auth -eq 'Bearer synthetic-fairlead-key-1') 'The key goes to the identified listener once and the redirect is not requested'
  Write-Host 'PASS: router calls do not follow redirects'

  # ---- localhost is not a router address ----
  $named=Start-TestService $Root $sandbox 'synthetic-router-test-token-328' @{EIGHTBELLS_FAIRLEAD_URL='http://localhost:8776/v1/chat/completions';EIGHTBELLS_TEST_FAIRLEAD_KEY='synthetic-fairlead-key-1'}
  $st=Invoke-RestMethod -Uri ($named.Url+'/api/ai/router') -Headers $named.Headers
  Assert-True ($st.active -eq $false) 'A localhost router address is not used'
  Assert-HttpStatus {Post-Json $named '/api/ai/config' @{router=$true}} 400 'localhost is refused as the router address'
  Write-Host 'PASS: the router address must be the literal 127.0.0.1'
}finally{
  Stop-TestProcess $svc;Stop-TestProcess $fake;Stop-TestProcess $other;Stop-TestProcess $deny;Stop-TestProcess $nokey;Stop-TestProcess $over;Stop-TestProcess $tok
  Stop-TestProcess $imp;Stop-TestProcess $impSvc;Stop-TestProcess $red;Stop-TestProcess $redSvc;Stop-TestProcess $named
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
