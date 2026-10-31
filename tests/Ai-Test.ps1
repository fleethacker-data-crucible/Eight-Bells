param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# Optional AI endpoint (/api/ai/config, /api/ai/run) and vision transcription (/api/vision), against a fake local model.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$sandbox=New-TestSandbox
$svc=$null;$fake=$null;$bad=$null
try{
  $fake=Start-FakeLlm $Root $sandbox 'ok'
  $svc=Start-TestService $Root $sandbox 'synthetic-ai-test-token-456'
  $url=$svc.Url

  # ---- configuration rules ----
  Assert-True ((Invoke-RestMethod -Uri "$url/api/diagnostics" -Headers $svc.Headers).aiConfigured -eq $false) 'AI must be off until configured'
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId='x';consent=$true}} 400 'AI run before configuration'
  Assert-HttpStatus {Post-Json $svc '/api/vision' @{mime='image/png';base64='AAAA';consent=$true}} 400 'Vision before configuration'
  Assert-HttpStatus {Post-Json $svc '/api/ai/config' @{endpoint='not a url';model='m'}} 400 'Malformed endpoint'
  Assert-HttpStatus {Post-Json $svc '/api/ai/config' @{endpoint='http://example.invalid/v1/chat/completions';model='m'}} 400 'Plain HTTP to a non-loopback host'
  Assert-HttpStatus {Post-Json $svc '/api/ai/config' @{endpoint='ftp://127.0.0.1/x';model='m'}} 400 'Non-HTTP scheme'
  Assert-HttpStatus {Post-Json $svc '/api/ai/config' @{endpoint='https://user:pass@example.invalid/v1';model='m'}} 400 'Credentials embedded in the endpoint'
  $cfg=Post-Json $svc '/api/ai/config' @{endpoint='https://models.example.invalid/v1/chat/completions';model='m'}
  Assert-True ($cfg.configured -eq $true) 'HTTPS endpoint should be accepted'
  $cleared=Post-Json $svc '/api/ai/config' @{endpoint=''}
  Assert-True ($cleared.configured -eq $false) 'Empty endpoint clears the configuration'
  $cfg=Post-Json $svc '/api/ai/config' @{endpoint=$fake.Endpoint;model='synthetic-model';key='synthetic-key-123'}
  Assert-True ($cfg.configured -eq $true -and $cfg.model -eq 'synthetic-model') 'Loopback HTTP endpoint should be accepted'
  Assert-True (-not ($cfg|ConvertTo-Json).Contains('synthetic-key-123')) 'Config response must not echo the key'
  Write-Host 'PASS: AI endpoint configuration rules (HTTPS or loopback HTTP only, no embedded credentials, clearable)'

  # ---- /api/ai/run ----
  $entries=@(1..160|ForEach-Object {@{line=$_;time='08:00';text=('Synthetic watch entry number '+$_);issue=$false;resolution=$false}})
  $log=Post-Json $svc '/api/import' @{name='Synthetic long log';watch='Engineering';content='0800 Synthetic watch entry';format='text';entries=$entries;analysis=@{score=100;findings=@();open=@()};sourceType='digital-text'}
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId=$log.id}} 403 'AI run without consent'
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId=$log.id;consent='true'}} 403 'AI run with a non-boolean consent'
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId='does-not-exist';consent=$true}} 404 'AI run for an unknown log'
  Assert-True (@(Get-LlmRequests $fake).Count -eq 0) 'Nothing may reach the model before consent and a valid log'
  $run=Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}
  Assert-True ($run.verified -eq $false) 'AI output must be marked unverified'
  Assert-True ($run.model -eq 'synthetic-model' -and $run.text -like 'SYNTHETIC REPLY*') 'AI reply was not relayed'
  $seen=@(Get-LlmRequests $fake)
  Assert-True ($seen.Count -eq 1) 'Exactly one upstream call per consented request'
  Assert-True ($seen[0].auth -eq 'Bearer synthetic-key-123') 'Session key must be sent as a Bearer header'
  $prompt=[string]$seen[0].body.messages[1].content
  Assert-True ($prompt.Contains('Line 150: Synthetic watch entry number 150') -and -not $prompt.Contains('Line 151:')) 'Prompt must carry exactly the first 150 entries'
  Assert-True ($seen[0].body.model -eq 'synthetic-model' -and [double]$seen[0].body.temperature -le 0.2) 'Model name and low temperature expected'
  $state=Invoke-RestMethod -Uri "$url/api/state" -Headers $svc.Headers
  Assert-True (-not (($state|ConvertTo-Json -Depth 30).Contains('synthetic-key-123'))) 'The AI key must never be stored'
  $diag=(Invoke-RestMethod -Uri "$url/api/diagnostics" -Headers $svc.Headers).lines -join "`n"
  Assert-True ($diag -match 'Manual AI request succeeded' -and -not $diag.Contains('synthetic-key-123') -and -not $diag.Contains('Synthetic watch entry')) 'Diagnostics must log the call but not the key or content'
  Write-Host 'PASS: /api/ai/run (consent, unknown log, 150-entry cap, bearer key, unverified output, key never stored or logged)'

  # ---- /api/vision ----
  $png=[Convert]::ToBase64String([byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,1,2,3,4))
  Assert-HttpStatus {Post-Json $svc '/api/vision' @{mime='image/png';base64=$png}} 403 'Vision without consent'
  Assert-HttpStatus {Post-Json $svc '/api/vision' @{mime='image/gif';base64=$png;consent=$true}} 400 'Unsupported image type'
  Assert-HttpStatus {Post-Json $svc '/api/vision' @{mime='application/pdf';base64=$png;consent=$true}} 400 'PDF through the vision route'
  Assert-HttpStatus {Post-Json $svc '/api/vision' @{mime='image/png';base64='***not base64***';consent=$true}} 400 'Invalid base64'
  Assert-HttpStatus {Post-Json $svc '/api/vision' @{mime='image/png';base64='';consent=$true}} 413 'Empty image'
  $big=[Convert]::ToBase64String((New-Object byte[] 2000001))
  Assert-HttpStatus {Post-Json $svc '/api/vision' @{mime='image/png';base64=$big;consent=$true}} 413 'Image over 2 MB'
  $before=@(Get-LlmRequests $fake).Count
  $vision=Post-Json $svc '/api/vision' @{mime='image/png';base64=$png;consent=$true}
  Assert-True ($vision.verified -eq $false -and $vision.text -like 'SYNTHETIC REPLY*') 'Vision transcript must be relayed and marked unverified'
  $after=@(Get-LlmRequests $fake)
  Assert-True ($after.Count -eq $before+1) ('Rejected image requests must not reach the model (before='+$before+' after='+$after.Count+')')
  $last=$after[$after.Count-1].body
  Assert-True ([double]$last.temperature -eq 0) 'Vision transcription must use temperature 0'
  $parts=@($last.messages[0].content)
  Assert-True ($parts[0].text -match 'SYNTHETIC' -and $parts[0].text -match 'ILLEGIBLE') 'Vision prompt must forbid inventing illegible words'
  Assert-True ($parts[1].image_url.url -eq ('data:image/png;base64,'+$png)) 'Image must travel as a data URL'
  Assert-True ($after[$after.Count-1].auth -eq 'Bearer synthetic-key-123') 'Vision call must use the session key'
  Write-Host 'PASS: /api/vision (consent, type, size, encoding, unverified transcript, data URL, temperature 0)'

  # ---- upstream failure and empty reply ----
  Stop-TestProcess $svc;$svc=$null
  $bad=Start-FakeLlm $Root $sandbox 'fail'
  $svc=Start-TestService $Root $sandbox 'synthetic-ai-test-token-456'
  $null=Post-Json $svc '/api/ai/config' @{endpoint=$bad.Endpoint;model='m';key='synthetic-key-123'}
  $log=@((Invoke-RestMethod -Uri ($svc.Url+'/api/state') -Headers $svc.Headers).logs)[0]
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}} 500 'AI run when the upstream fails'
  Assert-HttpStatus {Post-Json $svc '/api/vision' @{mime='image/png';base64=$png;consent=$true}} 500 'Vision when the upstream fails'
  $diag=(Invoke-RestMethod -Uri ($svc.Url+'/api/diagnostics') -Headers $svc.Headers).lines -join "`n"
  Assert-True ($diag -match 'AI request failed' -and -not $diag.Contains('synthetic-key-123')) 'Failures are logged without credentials'
  Stop-TestProcess $bad;$bad=Start-FakeLlm $Root $sandbox 'empty'
  $null=Post-Json $svc '/api/ai/config' @{endpoint=$bad.Endpoint;model='m'}
  Assert-HttpStatus {Post-Json $svc '/api/ai/run' @{logId=$log.id;consent=$true}} 500 'AI run with an empty reply'
  Write-Host 'PASS: upstream failure and empty reply are rejected without leaking credentials'
}finally{
  Stop-TestProcess $svc;Stop-TestProcess $fake;Stop-TestProcess $bad
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
