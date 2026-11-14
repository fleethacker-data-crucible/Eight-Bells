param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# Turnover speech and dictation go through Fairlead's audio routes. A fake loopback stands in for Fairlead.
# No live Fairlead, TalkForge or microphone is used.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$sandbox=New-TestSandbox
$svc=$null;$fake=$null;$deny=$null;$nokey=$null
try{
  $fake=Start-FakeLlm $Root $sandbox 'ok'
  $svc=Start-TestService $Root $sandbox 'synthetic-voice-test-token-901' @{EIGHTBELLS_FAIRLEAD_URL=$fake.Endpoint;EIGHTBELLS_TEST_FAIRLEAD_KEY='synthetic-fairlead-key-1'}

  Assert-HttpStatus {Post-Json $svc '/api/voice/speech' @{text='Hello watch'}} 403 'Speech without consent'
  Assert-HttpStatus {Post-Json $svc '/api/voice/speech' @{text='  ';consent=$true}} 400 'Speech with nothing to read'
  Assert-HttpStatus {Post-Json $svc '/api/voice/transcriptions' @{mime='audio/webm';base64='UklGRg=='}} 403 'Transcription without consent'

  $spoken=Post-Json $svc '/api/voice/speech' @{text='Line 1 synthetic turnover';consent=$true}
  Assert-True ($spoken.verified -eq $false -and $spoken.via -eq 'fairlead' -and $spoken.mime -eq 'audio/wav') 'Speech is marked unverified and named as Fairlead audio'
  Assert-True ([Text.Encoding]::ASCII.GetString([Convert]::FromBase64String([string]$spoken.audio)) -eq 'RIFF') 'Speech returns the upstream audio bytes'
  Assert-True (-not (($spoken|ConvertTo-Json).Contains('synthetic-fairlead-key'))) 'Speech response must not contain the client key'
  $seen=@(Get-LlmRequests $fake)
  Assert-True ($seen.Count -eq 1 -and $seen[0].path -eq '/v1/audio/speech') 'Speech posts to Fairlead /v1/audio/speech'
  Assert-True ($seen[0].privacy -eq 'local' -and $seen[0].label -eq 'EightBells' -and $seen[0].auth -eq 'Bearer synthetic-fairlead-key-1') 'Speech is local-only and carries this app''s Fairlead key'
  Assert-True ($seen[0].body.model -eq 'auto' -and $seen[0].body.input -eq 'Line 1 synthetic turnover') 'Speech sends the draft text and lets Fairlead choose the model'

  $clip=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('RIFF'))
  $heard=Post-Json $svc '/api/voice/transcriptions' @{mime='audio/webm;codecs=opus';base64=$clip;consent=$true}
  Assert-True ($heard.text -eq 'synthetic dictated line' -and $heard.verified -eq $false) 'Transcription is unverified text from Fairlead'
  Assert-True (-not (($heard|ConvertTo-Json).Contains('synthetic-fairlead-key'))) 'Transcription response must not contain the client key'
  $seen=@(Get-LlmRequests $fake)
  Assert-True ($seen.Count -eq 2 -and $seen[1].path -eq '/v1/audio/transcriptions' -and $seen[1].privacy -eq 'local' -and $seen[1].auth -eq 'Bearer synthetic-fairlead-key-1') 'Transcription posts local-only to Fairlead /v1/audio/transcriptions'
  Write-Host 'PASS: speech and transcription go through Fairlead, local-only, with consent, and never return the key'

  Stop-TestProcess $svc;$svc=$null
  $deny=Start-FakeLlm $Root $sandbox 'deny'
  $nokey=Start-TestService $Root $sandbox 'synthetic-voice-test-token-902' @{EIGHTBELLS_FAIRLEAD_URL=$deny.Endpoint;EIGHTBELLS_TEST_FAIRLEAD_KEY='(none)'}
  $msg=''
  try{Post-Json $nokey '/api/voice/speech' @{text='Hello';consent=$true}|Out-Null}catch{$msg=[string]$_.ErrorDetails.Message}
  Assert-True ($msg -match 'Install for this app' -and $msg -match 'EightBells' -and $msg -notmatch 'synthetic key refused') 'A refused speech call explains how to install the key and does not echo the upstream error'
  Write-Host 'PASS: a refused speech call explains how to install the key'
}finally{
  Stop-TestProcess $svc;Stop-TestProcess $fake;Stop-TestProcess $deny;Stop-TestProcess $nokey
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
