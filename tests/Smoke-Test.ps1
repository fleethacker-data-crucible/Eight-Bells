param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$source=Join-Path $Root 'Start-EightBells.ps1'
$isolated=Join-Path $env:TEMP ('EightBells-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $isolated | Out-Null
$env:EIGHTBELLS_TEST_SESSION='1'
$env:EIGHTBELLS_TEST_DATA_DIR=$isolated
$token='synthetic-smoke-test-token-123'
$process=$null
Remove-Item Env:\EIGHTBELLS_AUTO_STOP -ErrorAction SilentlyContinue
Remove-Item Env:\LOGHAWK_AUTO_STOP -ErrorAction SilentlyContinue
. (Join-Path $Root 'EightBells-Process.ps1')
function Start-TestServer([string]$label){
  # Reserve-and-release is used only to select a test port; production binds port 0 atomically.
  $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $probe.Start();$port=([Net.IPEndPoint]$probe.LocalEndpoint).Port;$probe.Stop()
  $exe=Join-Path $PSHOME 'powershell.exe'
  $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$source+'" -NoBrowser -Port '+$port+' -TestSessionToken '+$token
  $stdout=Join-Path $isolated ('service-stdout-'+$label+'.log');$stderr=Join-Path $isolated ('service-stderr-'+$label+'.log')
  $proc=Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $url='http://127.0.0.1:'+$port
  $ready=$false
  for($i=0;$i -lt 60;$i++){
    Start-Sleep -Milliseconds 250
    if($proc.HasExited){
      $details='';foreach($file in @($stdout,$stderr,(Join-Path $isolated 'runtime/service.log'))){if(Test-Path $file){$details += "`n[$file]`n"+(Get-Content $file -Tail 50|Out-String)}}
      throw ('Server exited during startup, exit '+$proc.ExitCode+': '+$details)
    }
    try{if((Invoke-WebRequest -UseBasicParsing -Uri "$url/health" -TimeoutSec 2).StatusCode -eq 200){$ready=$true;break}}catch{}
  }
  if(!$ready){throw 'Server did not become ready'}
  return [pscustomobject]@{Process=$proc;Port=$port;Url=$url;RuntimeFile=(Get-EightBellsRuntimePath -DataDir $isolated -ProcessId $proc.Id)}
}
function Wait-TestExit($proc,[int]$ms){
  $deadline=[DateTime]::UtcNow.AddMilliseconds($ms)
  while([DateTime]::UtcNow -lt $deadline){if($proc.HasExited){return $true};Start-Sleep -Milliseconds 250}
  return $proc.HasExited
}
function Assert-Status([scriptblock]$call,[int]$status,[string]$what){
  try{& $call;throw ($what+' was incorrectly allowed')}
  catch{if(!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne $status){throw}}
}
try {
  # Build/serve rule: a test server left over from an earlier run of this checkout holds the test mutex
  # and the checkout's files, so stop it first and say so. The user's own Eight Bells is never touched.
  try{
    $escaped=[regex]::Escape($source)
    foreach($old in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue)){
      if($old.ProcessId -ne $PID -and $old.CommandLine -and $old.CommandLine -match $escaped -and $old.CommandLine -match '-TestSessionToken'){
        Stop-Process -Id $old.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host ('Stopped leftover Eight Bells test server PID '+$old.ProcessId)
      }
    }
  }catch{}

  # ---- presence rule with simulated time (no sleeping) ----
  $t0=[DateTime]::new(2026,1,1,8,0,0,[DateTimeKind]::Utc)
  $tabs=@{}
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddHours(1)){throw 'Presence: no tab ever seen and no browser opened must not stop'}
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(119) -StartedAt $t0 -FirstContactMs 120000){throw 'Presence: first-contact window stopped early'}
  if(!(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(120) -StartedAt $t0 -FirstContactMs 120000)){throw 'Presence: browser that never connected should stop after the first-contact window'}
  Set-EightBellsPresence -Tabs $tabs -Tab 'a' -Leaving $false -Now $t0
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(19)){throw 'Presence: stopped before 20 s without heartbeat'}
  if(!(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(20))){throw 'Presence: still running 20 s after last heartbeat'}
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(60) -AutoStop $false){throw 'Presence: EIGHTBELLS_AUTO_STOP=0 / -Stay must keep running'}
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(60) -Busy 1){throw 'Presence: stopped while a job was running'}
  Set-EightBellsPresence -Tabs $tabs -Tab 'a' -Leaving $true -Now $t0.AddSeconds(2)
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(6)){throw 'Presence: stopped inside the 5 s leaving grace'}
  if(!(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(7))){throw 'Presence: still running 5 s after leaving signal'}
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(7) -Busy 1){throw 'Presence: stopped mid-job after leaving signal'}
  # Reload: the old page says leaving, the new page heartbeats with a new tab id inside the grace.
  $tabs=@{}
  Set-EightBellsPresence -Tabs $tabs -Tab 'old' -Leaving $false -Now $t0
  Set-EightBellsPresence -Tabs $tabs -Tab 'old' -Leaving $true -Now $t0.AddSeconds(1)
  Set-EightBellsPresence -Tabs $tabs -Tab 'new' -Leaving $false -Now $t0.AddSeconds(2)
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(10)){throw 'Presence: a reload stopped the server'}
  Remove-EightBellsGoneTabs -Tabs $tabs -Now $t0.AddSeconds(10)
  if($tabs.ContainsKey('old') -or !$tabs.ContainsKey('new')){throw 'Presence: closed tab was not pruned'}
  # Same tab id heartbeating again after a leaving signal (bfcache restore) cancels the leaving.
  Set-EightBellsPresence -Tabs $tabs -Tab 'new' -Leaving $true -Now $t0.AddSeconds(11)
  Set-EightBellsPresence -Tabs $tabs -Tab 'new' -Leaving $false -Now $t0.AddSeconds(12)
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(20)){throw 'Presence: heartbeat after leaving did not cancel it'}
  # Two tabs: closing one keeps the server; only when none is alive does it stop.
  $tabs=@{}
  Set-EightBellsPresence -Tabs $tabs -Tab 'one' -Leaving $false -Now $t0
  Set-EightBellsPresence -Tabs $tabs -Tab 'two' -Leaving $false -Now $t0
  Set-EightBellsPresence -Tabs $tabs -Tab 'one' -Leaving $true -Now $t0.AddSeconds(1)
  Set-EightBellsPresence -Tabs $tabs -Tab 'two' -Leaving $false -Now $t0.AddSeconds(15)
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(30)){throw 'Presence: stopped while a second tab is alive'}
  if(!(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(35))){throw 'Presence: did not stop once every tab was gone'}
  # A long request (AI call) blocks heartbeats; afterwards open tabs count as seen, leaving tabs do not.
  $tabs=@{}
  Set-EightBellsPresence -Tabs $tabs -Tab 'open' -Leaving $false -Now $t0
  Step-EightBellsPresenceAfterBusy -Tabs $tabs -Now $t0.AddSeconds(90)
  if(Test-EightBellsBrowserGone -Tabs $tabs -Now $t0.AddSeconds(91)){throw 'Presence: a long request counted against the open tab'}
  if(!(Test-EightBellsAutoStopEnabled -Value '') -or !(Test-EightBellsAutoStopEnabled -Value '1') -or (Test-EightBellsAutoStopEnabled -Value '0') -or (Test-EightBellsAutoStopEnabled -Value 'false')){throw 'Off switch: EIGHTBELLS_AUTO_STOP parsing is wrong'}
  # EIGHTBELLS_AUTO_STOP wins; the former LOGHAWK_AUTO_STOP is the fallback.
  try{
    $env:LOGHAWK_AUTO_STOP='0'
    if(Test-EightBellsAutoStopEnabled){throw 'Off switch: LOGHAWK_AUTO_STOP fallback was ignored'}
    $env:EIGHTBELLS_AUTO_STOP='1'
    if(!(Test-EightBellsAutoStopEnabled)){throw 'Off switch: EIGHTBELLS_AUTO_STOP did not take precedence'}
  }finally{Remove-Item Env:\EIGHTBELLS_AUTO_STOP -ErrorAction SilentlyContinue;Remove-Item Env:\LOGHAWK_AUTO_STOP -ErrorAction SilentlyContinue}
  Write-Host 'PASS: presence rule (20 s timeout, 5 s leaving grace, reload, multiple tabs, busy, off switch)'

  $server=Start-TestServer 'main'
  $process=$server.Process;$port=$server.Port;$url=$server.Url
  $headers=@{'X-EightBells-Token'=$token;'Origin'=$url}
  try{
    $null=Invoke-WebRequest -UseBasicParsing -Uri "$url/api/state" -TimeoutSec 5
    throw 'Unauthenticated state request was incorrectly allowed'
  }catch{
    if(!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 401){throw}
  }
  $page=Invoke-WebRequest -UseBasicParsing -Uri "$url/" -TimeoutSec 5
  if($page.Content -notmatch 'EIGHT BELLS'){throw 'UI did not load'}
  # Fleet UI files (docs/UNIFIED-UI.md section 10) are on the served allow-list; anything else is not.
  foreach($asset in @(@('/vendor/fleet/fleet.css','text/css'),@('/shell.js','application/javascript'),@('/icons.js','application/javascript'),@('/assets/brand/mark.svg','image/svg+xml'))){
    $r=Invoke-WebRequest -UseBasicParsing -Uri ($url+$asset[0]) -TimeoutSec 5
    if($r.StatusCode -ne 200 -or ([string]$r.Headers['Content-Type']) -notlike ($asset[1]+'*')){throw ('UI asset not served: '+$asset[0])}
  }
  if((Invoke-WebRequest -UseBasicParsing -Uri "$url/vendor/fleet/fleet.css" -TimeoutSec 5).Content -notmatch '--fl-background'){throw 'fleet.css content is wrong'}
  Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$url/Start-EightBells.ps1" -TimeoutSec 5} 401 'Serving a file outside the UI allow-list'
  # Pages served by an older LogHawk build send the former header name; it must keep working.
  $legacy=Invoke-RestMethod -Uri "$url/api/state" -Headers @{'X-LogHawk-Token'=$token}
  if($null -eq $legacy.logs){throw 'Legacy X-LogHawk-Token header was rejected'}
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
  $forged=@{'X-EightBells-Token'=$token;'Origin'='http://malicious.invalid'}
  try{
    $null=Invoke-WebRequest -UseBasicParsing -Uri "$url/api/lesson" -Method Post -Headers $forged -ContentType 'application/json' -Body $lesson
    throw 'Cross-origin request was incorrectly allowed'
  }catch{
    if(!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 403){throw}
  }
  Write-Host 'PASS: boot, UI, session auth, typed import, encrypted persistence, quality review, lessons, origin guard'

  # ---- runtime file ----
  if(!(Test-Path -LiteralPath $server.RuntimeFile)){throw 'Runtime file was not written'}
  $runtimeText=Get-Content -LiteralPath $server.RuntimeFile -Raw
  $runtimeInfo=$runtimeText|ConvertFrom-Json
  if([int]$runtimeInfo.pid -ne $process.Id -or [int]$runtimeInfo.port -ne $port -or [string]$runtimeInfo.url -ne ($url+'/') -or !$runtimeInfo.startedAt){throw 'Runtime file is missing pid/port/url/startedAt'}
  if($runtimeText.Contains($token)){throw 'Runtime file contains the session token'}
  $listed=@(Get-EightBellsProcesses -DataDir @($isolated) -NoProcessScan)
  if(@($listed|Where-Object {$_.Pid -eq $process.Id}).Count -ne 1){throw 'Get-EightBellsProcesses did not find the server from its runtime file'}
  $stale=Get-EightBellsRuntimePath -DataDir $isolated -ProcessId 999999
  Set-Content -LiteralPath $stale -Value '{"pid":999999,"port":1,"url":"http://127.0.0.1:1/","startedAt":"2026-01-01T00:00:00Z"}'
  $null=Get-EightBellsProcesses -DataDir @($isolated) -NoProcessScan
  if(Test-Path -LiteralPath $stale){throw 'Stale runtime file (dead pid) was not removed'}
  # A runtime file written by an older LogHawk build is still found (live pid) and cleaned up (dead pid).
  $legacyRuntime=Join-Path (Join-Path $isolated 'logs') ('loghawk-server-'+$process.Id+'.json')
  Move-Item -LiteralPath $server.RuntimeFile -Destination $legacyRuntime
  $listed=@(Get-EightBellsProcesses -DataDir @($isolated) -NoProcessScan)
  if(@($listed|Where-Object {$_.Pid -eq $process.Id}).Count -ne 1){throw 'Former loghawk-server-<pid>.json runtime file was not found'}
  Move-Item -LiteralPath $legacyRuntime -Destination $server.RuntimeFile
  $legacyStale=Join-Path (Join-Path $isolated 'logs') 'loghawk-server-999999.json'
  Set-Content -LiteralPath $legacyStale -Value '{"pid":999999,"port":1,"url":"http://127.0.0.1:1/","startedAt":"2026-01-01T00:00:00Z"}'
  $null=Get-EightBellsProcesses -DataDir @($isolated) -NoProcessScan
  if(Test-Path -LiteralPath $legacyStale){throw 'Stale former runtime file (dead pid) was not removed'}

  # ---- heartbeat route ----
  $legacyBeat=Invoke-RestMethod -Uri "$url/api/heartbeat" -Method Post -Headers @{'X-LogHawk-Token'=$token;'Origin'=$url} -ContentType 'application/json' -Body (@{tab='smoke-tab';leaving=$false}|ConvertTo-Json)
  if($null -eq $legacyBeat.autoStop){throw 'Heartbeat with the former X-LogHawk-Token header was rejected'}
  $beat=@{tab='smoke-tab';leaving=$false}|ConvertTo-Json
  $presence=Invoke-RestMethod -Uri "$url/api/heartbeat" -Method Post -Headers $headers -ContentType 'application/json' -Body $beat
  if($presence.autoStop -ne $true){throw 'Heartbeat did not report auto-stop on'}
  Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$url/api/heartbeat" -Method Post -ContentType 'application/json' -Body $beat -TimeoutSec 5} 401 'Heartbeat without a token'
  Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri ("$url/api/heartbeat?session="+$token) -Method Post -ContentType 'application/json' -Body $beat -TimeoutSec 5} 401 'Heartbeat with the token in the query string'
  $bodyToken=@{tab='smoke-tab';leaving=$false;session=$token}|ConvertTo-Json
  Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$url/api/heartbeat" -Method Post -Headers @{'Origin'='http://malicious.invalid'} -ContentType 'application/json' -Body $bodyToken -TimeoutSec 5} 403 'Cross-origin heartbeat'
  Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$url/api/state" -Method Post -Headers @{'Origin'=$url} -ContentType 'application/json' -Body $bodyToken -TimeoutSec 5} 401 'Body token on a route other than the heartbeat'
  $null=Invoke-RestMethod -Uri "$url/api/heartbeat" -Method Post -Headers @{'Origin'=$url} -ContentType 'application/json' -Body $bodyToken
  # ---- tab owns the server: a leaving beacon (token in body, as sendBeacon sends it) stops it about 5 s later ----
  $leaving=@{tab='smoke-tab';leaving=$true;session=$token}|ConvertTo-Json
  $null=Invoke-RestMethod -Uri "$url/api/heartbeat" -Method Post -Headers @{'Origin'=$url} -ContentType 'application/json' -Body $leaving
  Start-Sleep -Milliseconds 2500
  if($process.HasExited){throw 'Server stopped inside the 5 s leaving grace'}
  if(!(Wait-TestExit $process 12000)){throw 'Server did not stop itself after the tab left'}
  if(Test-Path -LiteralPath $server.RuntimeFile){throw 'Runtime file was not deleted on auto-stop'}
  Write-Host 'PASS: runtime file, heartbeat auth (header or body, never query), origin guard, auto-stop after leaving'

  # ---- off switch, End session ----
  $env:EIGHTBELLS_AUTO_STOP='0'
  try{$server=Start-TestServer 'stay'}finally{Remove-Item Env:\EIGHTBELLS_AUTO_STOP -ErrorAction SilentlyContinue}
  $process=$server.Process;$url=$server.Url
  $presence=Invoke-RestMethod -Uri "$url/api/heartbeat" -Method Post -Headers @{'Origin'=$url} -ContentType 'application/json' -Body $leaving
  if($presence.autoStop -ne $false){throw 'EIGHTBELLS_AUTO_STOP=0 was not honoured'}
  Start-Sleep -Milliseconds 7500
  if($process.HasExited){throw 'Server stopped itself with EIGHTBELLS_AUTO_STOP=0'}
  $null=Invoke-RestMethod -Uri "$url/api/shutdown" -Headers @{'X-EightBells-Token'=$token;'Origin'=$url} -Method Post -ContentType 'application/json' -Body '{}'
  if(!(Wait-TestExit $process 10000)){throw 'End session did not stop the server'}
  if(Test-Path -LiteralPath $server.RuntimeFile){throw 'Runtime file was not deleted on End session'}

  # ---- Stop-EightBells logic: finds the server from its runtime file without knowing the PID ----
  $server=Start-TestServer 'stop'
  $process=$server.Process
  $stopped=@(Stop-EightBellsProcesses -DataDir @($isolated) -NoProcessScan)
  if(@($stopped|Where-Object {$_.Pid -eq $process.Id}).Count -ne 1){throw 'Stop-EightBellsProcesses did not stop the server'}
  if(!(Wait-TestExit $process 5000)){throw 'Server still running after Stop-EightBellsProcesses'}
  if(Test-Path -LiteralPath $server.RuntimeFile){throw 'Stop did not delete the runtime file'}
  Write-Host 'PASS: EIGHTBELLS_AUTO_STOP=0 off switch, End session, stop without PID'
}finally{
 if($process -and !$process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
 Remove-Item Env:\EIGHTBELLS_TEST_SESSION -ErrorAction SilentlyContinue
 Remove-Item Env:\EIGHTBELLS_AUTO_STOP -ErrorAction SilentlyContinue
 Remove-Item Env:\LOGHAWK_AUTO_STOP -ErrorAction SilentlyContinue
 Remove-Item Env:\EIGHTBELLS_TEST_DATA_DIR -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $isolated -Recurse -Force -ErrorAction SilentlyContinue
}
