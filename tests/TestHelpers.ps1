# Shared helpers for the service-level PowerShell tests (dot-source from a test; set $script:Root first).
# Every helper uses an isolated temp data directory and a synthetic session token; nothing touches the user's store.
function New-TestSandbox{
  $dir=Join-Path $env:TEMP ('EightBells-test-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return $dir
}
function Get-FreeLoopbackPort{
  # Reserve-and-release is used only to select a test port; production binds port 0 atomically.
  $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $probe.Start();$port=([Net.IPEndPoint]$probe.LocalEndpoint).Port;$probe.Stop()
  return $port
}
function Start-TestService([string]$Root,[string]$DataDir,[string]$Token,[hashtable]$Env=@{}){
  $port=Get-FreeLoopbackPort
  $saved=@{}
  $Env['EIGHTBELLS_TEST_SESSION']='1';$Env['EIGHTBELLS_TEST_DATA_DIR']=$DataDir
  foreach($k in $Env.Keys){$saved[$k]=[Environment]::GetEnvironmentVariable($k);[Environment]::SetEnvironmentVariable($k,[string]$Env[$k])}
  try{
    $source=Join-Path $Root 'Start-EightBells.ps1'
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$source+'" -NoBrowser -Port '+$port+' -TestSessionToken '+$Token
    $stdout=Join-Path $DataDir ('service-stdout-'+$port+'.log');$stderr=Join-Path $DataDir ('service-stderr-'+$port+'.log')
    $proc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  }finally{foreach($k in $saved.Keys){[Environment]::SetEnvironmentVariable($k,$saved[$k])}}
  $url='http://127.0.0.1:'+$port
  for($i=0;$i -lt 80;$i++){
    Start-Sleep -Milliseconds 250
    if($proc.HasExited){
      $details='';foreach($file in @($stdout,$stderr,(Join-Path $DataDir 'runtime/service.log'))){if(Test-Path $file){$details += "`n[$file]`n"+(Get-Content $file -Tail 50|Out-String)}}
      throw ('Server exited during startup, exit '+$proc.ExitCode+': '+$details)
    }
    try{if((Invoke-WebRequest -UseBasicParsing -Uri "$url/health" -TimeoutSec 2).StatusCode -eq 200){return [pscustomobject]@{Process=$proc;Port=$port;Url=$url;Token=$Token;Headers=@{'X-EightBells-Token'=$Token;'Origin'=$url}}}}catch{}
  }
  throw 'Server did not become ready'
}
function Start-FakeLlm([string]$Root,[string]$DataDir,[string]$Mode='ok'){
  $port=Get-FreeLoopbackPort
  $record=Join-Path $DataDir ('llm-'+$port+'.jsonl')
  $script=Join-Path $Root 'tests\fixtures\Fake-LlmServer.ps1'
  $proc=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$script+'" -Port '+$port+' -Record "'+$record+'" -Mode '+$Mode) -PassThru -WindowStyle Hidden
  for($i=0;$i -lt 40;$i++){
    Start-Sleep -Milliseconds 250
    if($proc.HasExited){throw 'Fake LLM server exited during startup'}
    $c=[Net.Sockets.TcpClient]::new()
    try{$c.Connect('127.0.0.1',$port);$c.Close();return [pscustomobject]@{Process=$proc;Port=$port;Endpoint=('http://127.0.0.1:'+$port+'/v1/chat/completions');Record=$record}}catch{}
  }
  throw 'Fake LLM server did not become ready'
}
function Get-LlmRequests($fake){
  if(!(Test-Path $fake.Record)){return @()}
  return @(Get-Content -LiteralPath $fake.Record -Encoding UTF8|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json})
}
function Stop-TestProcess($p){if($p -and $p.Process -and !$p.Process.HasExited){Stop-Process -Id $p.Process.Id -Force -ErrorAction SilentlyContinue}}
function Assert-HttpStatus([scriptblock]$Call,[int]$Status,[string]$What){
  try{& $Call|Out-Null}catch{
    if($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq $Status){return}
    throw ($What+': expected HTTP '+$Status+' but got '+$_.Exception.Message)
  }
  throw ($What+' was incorrectly allowed (expected HTTP '+$Status+')')
}
function Post-Json($Svc,[string]$Path,$Body){
  return Invoke-RestMethod -Uri ($Svc.Url+$Path) -Method Post -Headers $Svc.Headers -ContentType 'application/json' -Body (ConvertTo-Json -InputObject $Body -Depth 30)
}
function Assert-True($Cond,[string]$Message){if(!$Cond){throw ('FAIL: '+$Message)}}
