param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$source=Join-Path $Root 'Start-LogHawk.ps1'
$isolated=Join-Path $env:TEMP ('LogHawk-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $isolated | Out-Null
$env:LOGHAWK_TEST_SESSION='1'
$env:LOGHAWK_TEST_DATA_DIR=$isolated
$token='synthetic-smoke-test-token-123'
$process=$null
try {
  # Reserve-and-release is used only to select a test port; production binds port 0 atomically.
  $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $probe.Start();$port=([Net.IPEndPoint]$probe.LocalEndpoint).Port;$probe.Stop()
  $exe=Join-Path $PSHOME 'powershell.exe'
  $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$source+'" -NoBrowser -Port '+$port+' -TestSessionToken '+$token
  $process=Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -WindowStyle Hidden
  $url='http://127.0.0.1:'+$port
  $ready=$false
  for($i=0;$i -lt 60;$i++){
    Start-Sleep -Milliseconds 250
    if($process.HasExited){throw 'Server exited during startup'}
    try{if((Invoke-WebRequest -UseBasicParsing -Uri "$url/health" -TimeoutSec 2).StatusCode -eq 200){$ready=$true;break}}catch{}
  }
  if(!$ready){throw 'Server did not become ready'}
  $headers=@{'X-LogHawk-Token'=$token;'Origin'=$url}
  try{
    $null=Invoke-WebRequest -UseBasicParsing -Uri "$url/api/state" -TimeoutSec 5
    throw 'Unauthenticated state request was incorrectly allowed'
  }catch{
    if(!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 401){throw}
  }
  $page=Invoke-WebRequest -UseBasicParsing -Uri "$url/" -TimeoutSec 5
  if($page.Content -notmatch 'LOGHAWK'){throw 'UI did not load'}
  $state=Invoke-RestMethod -Uri "$url/api/state" -Headers $headers
  if($null -eq $state.logs){throw 'No logs collection'}
  $entries=@(@{line=1;time='08:00';text='Pump B abnormal vibration';equipment='Pump B';issue=$true;resolution=$false},@{line=2;time='08:30';text='Supervisor notified';issue=$false;resolution=$false})
  $analysis=@{score=90;findings=@(@{id='f1';type='disposition';detail='Check unresolved state';lines=@(1);priority='review'});open=@(@{equipment='Pump B';lines=@(1);latest='Pump B abnormal vibration'})}
  $body=@{name='Synthetic Engineering Test';watch='Engineering';content="0800 Pump B abnormal vibration`n0830 Supervisor notified";format='text';entries=$entries;analysis=$analysis;sourceType='digital-text'}|ConvertTo-Json -Depth 16
  $saved=Invoke-RestMethod -Uri "$url/api/import" -Method Post -Headers $headers -ContentType 'application/json' -Body $body
  if(!$saved.id){throw 'Import did not return record ID'}
  $review=@{logId=$saved.id;findingId='f1';disposition='follow-up';note='Synthetic regression verification only'}|ConvertTo-Json
  $null=Invoke-RestMethod -Uri "$url/api/review" -Method Post -Headers $headers -ContentType 'application/json' -Body $review
  $lesson=@{title='Synthetic test lesson';body='Only a testing memory';source=$saved.id}|ConvertTo-Json
  $null=Invoke-RestMethod -Uri "$url/api/lesson" -Method Post -Headers $headers -ContentType 'application/json' -Body $lesson
  $state=Invoke-RestMethod -Uri "$url/api/state" -Headers $headers
  if(@($state.logs).Count -ne 1 -or @($state.reviews).Count -ne 1 -or @($state.lessons).Count -ne 1){throw 'Persistence or review roundtrip failed'}
  $cipher=[IO.File]::ReadAllBytes((Join-Path $isolated 'store.v2.dpapi'))
  $text=[Text.Encoding]::UTF8.GetString($cipher)
  if($text.Contains('Synthetic Engineering Test') -or $text.Contains('Synthetic test lesson')){throw 'Database is not encrypted'}
  # Confirm a forged cross-origin write is forbidden even with a valid token.
  $forged=@{'X-LogHawk-Token'=$token;'Origin'='http://malicious.invalid'}
  try{
    $null=Invoke-WebRequest -UseBasicParsing -Uri "$url/api/lesson" -Method Post -Headers $forged -ContentType 'application/json' -Body $lesson
    throw 'Cross-origin request was incorrectly allowed'
  }catch{
    if(!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 403){throw}
  }
  Write-Host 'PASS: boot, UI, session auth, typed import, encrypted persistence, quality review, lessons, origin guard'
  $null=Invoke-RestMethod -Uri "$url/api/shutdown" -Headers $headers -Method Post -ContentType 'application/json' -Body '{}'
}finally{
 if($process -and !$process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
 Remove-Item Env:\LOGHAWK_TEST_SESSION -ErrorAction SilentlyContinue
 Remove-Item Env:\LOGHAWK_TEST_DATA_DIR -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $isolated -Recurse -Force -ErrorAction SilentlyContinue
}
