[CmdletBinding(PositionalBinding=$false)]
param([int]$Port=0,[switch]$NoBrowser,[switch]$Background,[switch]$Diagnostics,[string]$TestSessionToken='',[switch]$LocalDev,[switch]$Stay,[switch]$Replace,[int]$LauncherPid=0,[Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference='Stop'
# Launcher-style options (Launch-EightBells.bat --replace / --stay) arrive as remaining arguments.
foreach($a in @($Rest)){
  switch -Regex ($a){
    '^--?stay$'{$Stay=$true}
    '^--?replace$'{$Replace=$true}
    '^--?no-browser$'{$NoBrowser=$true}
    default{if($a){Write-Warning ('Ignoring unknown option '+$a)}}
  }
}
# Windows PowerShell 5.1 does not always preload the DPAPI ProtectedData assembly.
# This is a standard .NET Framework assembly; no install, policy change, or smart card bypass.
Add-Type -AssemblyName System.Security -ErrorAction Stop
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'EightBells-Process.ps1')
# EIGHTBELLS_* environment variables are read first; the former LOGHAWK_* names remain a fallback.
function Get-EnvSetting([string]$name){
  $value=[Environment]::GetEnvironmentVariable('EIGHTBELLS_'+$name)
  if([string]::IsNullOrEmpty($value)){$value=[Environment]::GetEnvironmentVariable('LOGHAWK_'+$name)}
  return $value
}
# One-time copy-forward from the former LogHawk data folder. The old folder is never modified or removed.
# Runs only when the new folder does not exist yet, so it is idempotent; a partial copy is staged and renamed.
# Runtime files of the old build (ready.json, logs\loghawk-server-*.json) are not carried over.
function Initialize-DataFolder([string]$newPath,[string]$oldPath){
  if((Test-Path -LiteralPath $newPath) -or !(Test-Path -LiteralPath $oldPath -PathType Container)){return}
  $stage=$newPath+'.migrating-'+[guid]::NewGuid().ToString('N')
  try{
    Copy-Item -LiteralPath $oldPath -Destination $stage -Recurse -Force -ErrorAction Stop
    Remove-Item -LiteralPath (Join-Path (Join-Path $stage 'runtime') 'ready.json') -Force -ErrorAction SilentlyContinue
    $stageLogs=Join-Path $stage 'logs'
    if(Test-Path -LiteralPath $stageLogs){Get-ChildItem -LiteralPath $stageLogs -Filter 'loghawk-server-*.json' -ErrorAction SilentlyContinue|Remove-Item -Force -ErrorAction SilentlyContinue}
    if(!(Test-Path -LiteralPath $newPath)){[IO.Directory]::Move($stage,$newPath)}
  }finally{
    if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
  }
}
$testMode=((Get-EnvSetting 'TEST_SESSION') -eq '1' -and $NoBrowser)
$testDataDir=Get-EnvSetting 'TEST_DATA_DIR'
$legacyBase=$null
if($LocalDev){
  $base=Join-Path $env:LOCALAPPDATA 'EightBells-LocalDev'
  $legacyBase=Join-Path $env:LOCALAPPDATA 'LogHawk-LocalDev'
}elseif($testMode -and $testDataDir){
  $base=$testDataDir
}else{
  $base=Join-Path $env:LOCALAPPDATA 'EightBells'
  $legacyBase=Join-Path $env:LOCALAPPDATA 'LogHawk'
}
$runtime=Join-Path $base 'runtime'
# Runtime files live beside the store and logs: <data dir>\logs\eightbells-server-<pid>.json
$runtimeLogs=Join-Path $base 'logs'
$runtimeFile=Get-EightBellsRuntimePath -DataDir $base -ProcessId $PID
$ready=Join-Path $runtime 'ready.json'
$log=Join-Path $runtime 'service.log'
$store=Join-Path $base 'store.v2.dpapi'
if($LocalDev){Write-Host '[LOCAL DEV] Isolated Eight Bells database; do not enter operational or sensitive records.' -ForegroundColor Yellow}
function Diag([string]$s){
  $line=[DateTime]::UtcNow.ToString('o')+' '+$s
  try{Add-Content -LiteralPath $log -Value $line -Encoding UTF8}catch{}
  if($Diagnostics){Write-Host $line}
}
function Confirm-EightBellsReplace([string]$where){
  if($Replace){return $true}
  $question='Eight Bells is already running: '+$where+'. Stop it and start a fresh session?'
  if($Background){
    # The background launcher window is minimised, so ask with a dialog the user can see.
    try{
      Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
      return ([string][Windows.Forms.MessageBox]::Show($question,'Eight Bells','YesNo','Question') -eq 'Yes')
    }catch{}
  }
  try{$answer=Read-Host ($question+' [Y/n]')}catch{return $false}
  return ($answer -eq '' -or $answer -match '^[Yy]')
}
# One instance: find running servers (runtime files, then a process scan) and offer to replace them.
if($testMode){
  $null=Get-EightBellsProcesses -DataDir @($base) -NoProcessScan
}else{
  # A hidden child started by -Background must not count (or stop) the launcher that is waiting for it.
  $existing=@(Get-EightBellsProcesses -Exclude @($LauncherPid))
  if($existing.Count -gt 0){
    $where=($existing|ForEach-Object {Format-EightBellsProcess $_}) -join ', '
    if(Confirm-EightBellsReplace $where){
      foreach($p in @(Stop-EightBellsProcesses -Exclude @($LauncherPid))){Write-Host ('Stopped running Eight Bells '+(Format-EightBellsProcess $p)+'.') -ForegroundColor Yellow;Diag ('Replaced running instance PID '+$p.Pid)}
    }else{
      Write-Host 'Leaving the running Eight Bells alone. Use its browser tab, End session, or Stop-EightBells.ps1.'
      return
    }
  }
}
# Copy forward from the former LogHawk folder only now, after any running LogHawk was stopped above,
# so the copy includes its last writes.
if($legacyBase){Initialize-DataFolder $base $legacyBase}
New-Item -ItemType Directory -Force -Path $base,$runtime,$runtimeLogs | Out-Null
if($Background){
  Remove-Item $ready -Force -ErrorAction SilentlyContinue
  # The user already answered the one-instance question here, so the hidden child must never prompt.
  $launchArgs='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$MyInvocation.MyCommand.Path+'" -Replace -LauncherPid '+$PID
  if($Port -gt 0){$launchArgs+=' -Port '+$Port}
  if($Stay){$launchArgs+=' -Stay'}
  if($LocalDev){$launchArgs+=' -LocalDev'}
  $child=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $launchArgs -WindowStyle Hidden -PassThru
  $ok=$false
  for($i=0;$i -lt 80;$i++){
    Start-Sleep -Milliseconds 250
    if($child.HasExited){throw 'Eight Bells startup failed; see '+$log}
    if(Test-Path $ready){
      try{
        $r=Get-Content $ready -Raw | ConvertFrom-Json
        if([int]$r.pid -eq $child.Id){
          $test=Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:'+$r.port+'/health') -TimeoutSec 2
          if($test.StatusCode -eq 200){$ok=$true;break}
        }
      }catch{}
    }
  }
  if(!$ok){throw 'Startup timeout; inspect '+$log}
  Write-Host ('Eight Bells started on port '+$r.port)
  return
}
$script:running=$true
# Tab owns the server: heartbeats from open tabs keep it alive (see EightBells-Process.ps1 for the rule).
$script:autoStop=((Test-EightBellsAutoStopEnabled) -and !$Stay)
$script:tabs=@{}
$script:startedAt=[DateTime]::UtcNow
# If a browser was opened but never sent a heartbeat (closed before loading, or failed to open), stop after 2 minutes.
$script:firstContactMs=if($NoBrowser){0}else{120000}
$script:ai=@{endpoint='';model='';key='';router=$false}
# Opt-in intelligence router (Fairlead). Off unless a client asks for it; the router holds the provider keys, so no key is sent.
$script:routerUrl=Get-EnvSetting 'FAIRLEAD_URL'
if([string]::IsNullOrEmpty($script:routerUrl)){$script:routerUrl='http://127.0.0.1:8776/v1/chat/completions'}
$bytes=New-Object byte[] 32
$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes);$rng.Dispose()
$script:token=[Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
if($testMode -and $TestSessionToken){$script:token=$TestSessionToken;Diag 'Synthetic test token enabled for isolated non-browser smoke test'}
function New-State{return @{version=2;logs=@();lessons=@();reviews=@();audit=@()}}
function Load-State{
  if(!(Test-Path $store)){return (New-State)}
  try{
    $raw=[IO.File]::ReadAllBytes($store)
    $plain=[Security.Cryptography.ProtectedData]::Unprotect($raw,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $value=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json
    if($value.version -ne 2){throw 'Unsupported database version'}
    return $value
  }catch{throw 'Encrypted local database cannot be opened by this Windows account: '+$_.Exception.Message}
}
function Save-State($state){
  $raw=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $state -Depth 70 -Compress))
  $cipher=[Security.Cryptography.ProtectedData]::Protect($raw,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $tmp=$store+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  [IO.File]::WriteAllBytes($tmp,$cipher)
  try{
    if(Test-Path $store){[IO.File]::Replace($tmp,$store,$store+'.backup',$true)}
    else{[IO.File]::Move($tmp,$store)}
  }finally{Remove-Item $tmp -Force -ErrorAction SilentlyContinue}
}
function Audit($s,[string]$action,[string]$target){
  $s.audit=@($s.audit)+@(@{at=[DateTime]::UtcNow.ToString('o');action=$action;target=$target})
  if(@($s.audit).Count -gt 2000){$s.audit=@($s.audit|Select-Object -Last 2000)}
}
function J($o){return (ConvertTo-Json -InputObject $o -Depth 70 -Compress)}
function Reply($stream,[int]$status,[string]$body,[string]$mime='application/json; charset=utf-8'){ReplyBytes $stream $status ([Text.Encoding]::UTF8.GetBytes($body)) $mime}
function ReplyBytes($stream,[int]$status,[byte[]]$data,[string]$mime){
  $reason=switch($status){200{'OK'}201{'Created'}400{'Bad Request'}401{'Unauthorized'}403{'Forbidden'}404{'Not Found'}413{'Payload Too Large'}500{'Internal Server Error'}default{'Error'}}
  $nl=[string][char]13+[char]10
  $head="HTTP/1.1 $status $reason"+$nl+"Content-Type: $mime"+$nl+"Content-Length: $($data.Length)"+$nl+"Cache-Control: no-store"+$nl+"X-Content-Type-Options: nosniff"+$nl+"X-Frame-Options: DENY"+$nl+"Referrer-Policy: no-referrer"+$nl+"Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob: data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"+$nl+"Connection: close"+$nl+$nl
  $h=[Text.Encoding]::ASCII.GetBytes($head)
  $stream.Write($h,0,$h.Length);$stream.Write($data,0,$data.Length);$stream.Flush()
}
function Reject($stream,[int]$status,[string]$msg){Reply $stream $status (J @{error=$msg})}
function Read-Http($stream){
  $head=New-Object 'System.Collections.Generic.List[byte]'
  while($head.Count -lt 16384){
    $b=$stream.ReadByte()
    if($b -lt 0){throw 'Closed connection'}
    $head.Add([byte]$b)
    $c=$head.Count
    if($c -ge 4 -and $head[$c-4] -eq 13 -and $head[$c-3] -eq 10 -and $head[$c-2] -eq 13 -and $head[$c-1] -eq 10){break}
  }
  if($head.Count -ge 16384){throw 'Oversized headers'}
  $lines=([Text.Encoding]::ASCII.GetString($head.ToArray()) -split '\r\n')
  $parts=$lines[0].Split(' ')
  if($parts.Count -ne 3){throw 'Invalid request line'}
  $headers=@{}
  foreach($line in $lines|Select-Object -Skip 1){
    $n=$line.IndexOf(':')
    if($n -gt 0){$key=$line.Substring(0,$n).Trim().ToLowerInvariant();if($headers.ContainsKey($key)){throw 'Duplicate HTTP header'};$headers[$key]=$line.Substring($n+1).Trim()}
  }
  if($headers.ContainsKey('transfer-encoding')){throw 'Chunked request unsupported'}
  $len=0
  if($headers.ContainsKey('content-length') -and ![int]::TryParse($headers['content-length'],[ref]$len)){throw 'Bad content length'}
  if($len -lt 0 -or $len -gt 4194304){throw 'Body too large'}
  $data=New-Object byte[] $len
  $offset=0
  while($offset -lt $len){$n=$stream.Read($data,$offset,$len-$offset);if($n -le 0){throw 'Truncated body'};$offset+=$n}
  return @{method=$parts[0];path=$parts[1].Split('?')[0];headers=$headers;body=[Text.Encoding]::UTF8.GetString($data)}
}
# The only files the UI may load: request path -> file under the repository root. Nothing else is served.
$script:uiFiles=@{
  '/'='web/index.html';'/engine.js'='web/engine.js';'/lifecycle.js'='web/lifecycle.js';'/app.js'='web/app.js';'/styles.css'='web/styles.css'
  '/shell.js'='web/shell.js';'/icons.js'='web/icons.js';'/vendor/fleet/fleet.css'='web/vendor/fleet/fleet.css';'/assets/brand/mark.svg'='assets/brand/mark.svg'
  '/halyard-export.js'='web/halyard-export.js'
  # The emblem (backdrop made transparent, one per theme) and the favicon / icon cut from its circle.
  '/brand/emblem-dark.png'='web/brand/emblem-dark.png';'/brand/emblem-light.png'='web/brand/emblem-light.png';'/brand/icon-256.png'='web/brand/icon-256.png'
  '/brand/favicon.ico'='web/brand/favicon.ico';'/favicon.ico'='web/brand/favicon.ico'
}
function Process-Http($req,$stream){
  $path=$req.path
  if($req.headers['host'] -ne ('127.0.0.1:'+$script:port)){Reject $stream 403 'Host rejected';return}
  if($req.method -eq 'GET' -and $path -eq '/health'){Reply $stream 200 (J @{status='ready';version=2});return}
  if($req.method -eq 'GET' -and $script:uiFiles.ContainsKey($path)){
    $name=$script:uiFiles[$path]
    $file=Join-Path $root $name
    if(!(Test-Path $file)){Reject $stream 404 'Missing UI asset';return}
    if($name.EndsWith('.png')){ReplyBytes $stream 200 ([IO.File]::ReadAllBytes($file)) 'image/png';return}
    if($name.EndsWith('.ico')){ReplyBytes $stream 200 ([IO.File]::ReadAllBytes($file)) 'image/x-icon';return}
    $mime=if($name.EndsWith('.js')){'application/javascript; charset=utf-8'}elseif($name.EndsWith('.css')){'text/css; charset=utf-8'}elseif($name.EndsWith('.svg')){'image/svg+xml; charset=utf-8'}else{'text/html; charset=utf-8'}
    Reply $stream 200 ([IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)) $mime;return
  }
  if($path -eq '/api/heartbeat'){
    if($req.method -ne 'POST'){Reject $stream 404 'Unknown route';return}
    if($req.headers.ContainsKey('origin') -and $req.headers['origin'] -ne ('http://127.0.0.1:'+$script:port)){Reject $stream 403 'Origin rejected';return}
    $beat=$null
    try{if($req.body){$beat=$req.body|ConvertFrom-Json}}catch{$beat=$null}
    # sendBeacon cannot set headers: on this route only, the token may travel in the JSON body (never the query string; bodies are never logged).
    $presented=if($req.headers.ContainsKey('x-eightbells-token')){[string]$req.headers['x-eightbells-token']}else{[string]$req.headers['x-loghawk-token']}
    if(!$presented -and $beat -and $beat.session){$presented=[string]$beat.session}
    if($presented -cne $script:token){Reject $stream 401 'Invalid session';return}
    $leaving=$false;$tab=''
    if($beat){$leaving=($beat.leaving -eq $true);$tab=[string]$beat.tab}
    Set-EightBellsPresence -Tabs $script:tabs -Tab $tab -Leaving $leaving -Now ([DateTime]::UtcNow)
    Reply $stream 200 (J @{autoStop=$script:autoStop;timeoutSeconds=20;leavingGraceSeconds=5});return
  }
  # X-EightBells-Token is current; X-LogHawk-Token is still accepted from pages served by an older build.
  $sessionToken=if($req.headers.ContainsKey('x-eightbells-token')){$req.headers['x-eightbells-token']}else{$req.headers['x-loghawk-token']}
  if($sessionToken -cne $script:token){Reject $stream 401 'Invalid session';return}
  if($req.method -eq 'POST' -and $req.headers.ContainsKey('origin') -and $req.headers['origin'] -ne ('http://127.0.0.1:'+$script:port)){Reject $stream 403 'Origin rejected';return}
  if($req.method -eq 'GET' -and $path -eq '/api/state'){Reply $stream 200 (J (Load-State));return}
  if($req.method -eq 'GET' -and $path -eq '/api/diagnostics'){
    # Plain strings only: Get-Content output carries path properties that ConvertTo-Json would walk at depth 70.
    $lines=if(Test-Path $log){@(Get-Content -LiteralPath $log -Tail 100 | ForEach-Object {[string]$_})}else{@()}
    Reply $stream 200 (J @{lines=$lines;storage='Windows CurrentUser DPAPI';aiConfigured=[bool]$script:ai.endpoint});return
  }
  if($req.method -ne 'POST'){Reject $stream 404 'Unknown route';return}
  try{$obj=$req.body|ConvertFrom-Json}catch{Reject $stream 400 'Malformed JSON';return}
  if($path -eq '/api/import'){
    $name=[string]$obj.name;$content=[string]$obj.content
    if(!$name -or !$content){Reject $stream 400 'Name and content required';return}
    if($content.Length -gt 1500000){Reject $stream 413 'Text too large';return}
    $entries=@($obj.entries)
    if($entries.Count -gt 10000 -or !$obj.analysis){Reject $stream 400 'Parsed entries and findings required';return}
    $s=Load-State;$id=[guid]::NewGuid().ToString('N')
    $item=[pscustomobject]@{id=$id;name=$name.Substring(0,[Math]::Min(150,$name.Length));format=[string]$obj.format;sourceType=[string]$obj.sourceType;watch=[string]$obj.watch;content=$content;entries=$entries;analysis=$obj.analysis;imported=[DateTime]::UtcNow.ToString('o')}
    $s.logs=@($s.logs)+@($item);Audit $s 'import' $id;Save-State $s
    Reply $stream 201 (J $item);return
  }
  if($path -eq '/api/review'){
    $s=Load-State
    $target=@($s.logs|Where-Object {$_.id -eq [string]$obj.logId})
    if(!$target){Reject $stream 404 'Log not found';return}
    $finding=@($target[0].analysis.findings|Where-Object {$_.id -eq [string]$obj.findingId})
    if(!$finding){Reject $stream 404 'Finding not found';return}
    if([string]$obj.disposition -notin @('acknowledged','follow-up','false-positive')){Reject $stream 400 'Invalid disposition';return}
    if([string]::IsNullOrWhiteSpace([string]$obj.note)){Reject $stream 400 'Explanation required';return}
    $id=[guid]::NewGuid().ToString('N')
    $s.reviews=@($s.reviews)+@(@{id=$id;logId=[string]$obj.logId;findingId=[string]$obj.findingId;disposition=[string]$obj.disposition;note=([string]$obj.note).Substring(0,[Math]::Min(2000,([string]$obj.note).Length));at=[DateTime]::UtcNow.ToString('o')})
    Audit $s 'quality-review' $id;Save-State $s;Reply $stream 201 (J @{id=$id});return
  }
  if($path -eq '/api/lesson'){
    if([string]::IsNullOrWhiteSpace([string]$obj.title) -or [string]::IsNullOrWhiteSpace([string]$obj.body)){Reject $stream 400 'Title and body required';return}
    $s=Load-State;$id=[guid]::NewGuid().ToString('N')
    $lesson=[pscustomobject]@{id=$id;title=[string]$obj.title;body=[string]$obj.body;source=[string]$obj.source;status='draft';created=[DateTime]::UtcNow.ToString('o')}
    $s.lessons=@($s.lessons)+@($lesson);Audit $s 'lesson-draft' $id;Save-State $s
    Reply $stream 201 (J $lesson);return
  }
  if($path -eq '/api/lesson/review'){
    $s=Load-State;$found=$false
    foreach($lesson in $s.lessons){if($lesson.id -eq [string]$obj.id){$lesson.status='reviewed';$found=$true;break}}
    if(!$found){Reject $stream 404 'Lesson not found';return}
    Audit $s 'lesson-reviewed' ([string]$obj.id);Save-State $s;Reply $stream 200 (J @{ok=$true});return
  }
  if($path -eq '/api/ai/config'){
    if($obj.router -is [bool] -and $obj.router){
      $ruri=$null
      if(![Uri]::TryCreate($script:routerUrl,[UriKind]::Absolute,[ref]$ruri) -or $ruri.Scheme -ne 'http' -or $ruri.Host -notin @('127.0.0.1','localhost')){Reject $stream 400 'The router address must be a local HTTP address';return}
      $script:ai=@{endpoint=$script:routerUrl;model=$(if([string]::IsNullOrEmpty([string]$obj.model)){'auto'}else{[string]$obj.model});key='';router=$true}
      Reply $stream 200 (J @{configured=$true;router=$true;model=$script:ai.model});return
    }
    $endpoint=[string]$obj.endpoint
    if(!$endpoint){$script:ai=@{endpoint='';model='';key='';router=$false};Reply $stream 200 (J @{configured=$false});return}
    $uri=$null
    if(![Uri]::TryCreate($endpoint,[UriKind]::Absolute,[ref]$uri)){Reject $stream 400 'Invalid endpoint';return}
    if($uri.Scheme -ne 'https' -and !(($uri.Scheme -eq 'http') -and ($uri.Host -in @('127.0.0.1','localhost')))){Reject $stream 400 'Only HTTPS or local HTTP AI endpoints are allowed';return}
    if($uri.UserInfo){Reject $stream 400 'Credentials in endpoint are prohibited';return}
    $script:ai=@{endpoint=$endpoint;model=[string]$obj.model;key=[string]$obj.key;router=$false}
    Reply $stream 200 (J @{configured=$true;model=$script:ai.model});return
  }
  if($path -eq '/api/vision'){
    if(!$script:ai.endpoint){Reject $stream 400 'Configure an approved vision-capable AI endpoint first';return}
    if($obj.consent -isnot [bool] -or $obj.consent -ne $true){Reject $stream 403 'Explicit image transmission consent is required';return}
    $mime=[string]$obj.mime
    if($mime -notin @('image/png','image/jpeg','image/webp')){Reject $stream 400 'Only PNG, JPEG and WebP are supported';return}
    $encoded=[string]$obj.base64
    if($encoded.Length -gt 2800000 -or !$encoded){Reject $stream 413 'Image is too large for vision request';return}
    try{$bytes=[Convert]::FromBase64String($encoded)}catch{Reject $stream 400 'Invalid image encoding';return}
    if($bytes.Length -gt 2000000){Reject $stream 413 'Image must be under 2MB';return}
    # The model's transcription is always unverified and must be corrected by the user.
    $url='data:'+$mime+';base64,'+$encoded
    $message=@{role='user';content=@(@{type='text';text='Transcribe this SYNTHETIC TRAINING watch log exactly, preserving line order and timestamps. Do not invent or normalize illegible words. Mark them [ILLEGIBLE]. Output ONLY the transcription.'},@{type='image_url';image_url=@{url=$url}})}
    $body=J @{model=$script:ai.model;messages=@($message);temperature=0.0;max_tokens=3000}
    $headers=@{}
    if($script:ai.key){$headers['Authorization']='Bearer '+$script:ai.key}
    if($script:ai.router){$headers['X-Fairlead-Privacy']='local'}
    try{
      $result=Invoke-RestMethod -Uri $script:ai.endpoint -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 90
      $transcript=[string]$result.choices[0].message.content
      if(!$transcript){throw 'No recognized transcription'}
      Diag 'Manual synthetic-image vision transcription completed; no content logged'
      Reply $stream 200 (J @{text=$transcript;verified=$false});return
    }catch{Diag 'Vision request failed (credentials and image excluded)';Reject $stream 500 'Vision transcription failed; verify endpoint vision support and configuration';return}
  }
  if($path -eq '/api/ai/run'){
    if(!$script:ai.endpoint){Reject $stream 400 'Configure an approved AI endpoint';return}
    if($obj.consent -isnot [bool] -or $obj.consent -ne $true){Reject $stream 403 'Explicit consent required';return}
    $s=Load-State;$item=@($s.logs|Where-Object {$_.id -eq [string]$obj.logId})
    if(!$item){Reject $stream 404 'Log not found';return}
    $lines=@($item[0].entries|Select-Object -First 150|ForEach-Object {'Line '+$_.line+': '+$_.text})
    $prompt="SYNTHETIC TRAINING LOG. Draft watch turnover, cite line numbers, do not invent resolutions. SOURCE:"+[Environment]::NewLine+($lines -join [Environment]::NewLine)
    $body=J @{model=$script:ai.model;temperature=0.1;messages=@(@{role='system';content='Create a cautious evidence-linked turnover draft, plain text.'},@{role='user';content=$prompt})}
    $headers=@{}
    if($script:ai.key){$headers['Authorization']='Bearer '+$script:ai.key}
    if($script:ai.router){$headers['X-Fairlead-Privacy']='local'}
    try{
      $response=Invoke-RestMethod -Uri $script:ai.endpoint -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 90
      $answer=[string]$response.choices[0].message.content
      if(!$answer){throw 'Empty response'}
      Diag 'Manual AI request succeeded (no content logged)'
      Reply $stream 200 (J @{text=$answer;model=$script:ai.model;verified=$false});return
    }catch{Diag 'Manual AI request failed (no credentials logged)';Reject $stream 500 'AI request failed; inspect endpoint and model settings';return}
  }
  if($path -eq '/api/shutdown'){$script:running=$false;Diag 'End session requested from the browser';Reply $stream 200 (J @{ok=$true});return}
  Reject $stream 404 'Unknown route'
}
function Invoke-PresenceTick{
  if(!$script:autoStop -or !$script:running){return}
  $now=[DateTime]::UtcNow
  # Requests run one at a time inside the loop, so a save/import/AI call is never interrupted by this tick.
  # Connections still queued (heartbeats that waited behind a long AI request) count as work in progress.
  $busy=0
  if($server -and $server.Pending()){$busy=1}
  if(Test-EightBellsBrowserGone -Tabs $script:tabs -Now $now -Busy $busy -AutoStop $script:autoStop -StartedAt $script:startedAt -FirstContactMs $script:firstContactMs){
    Diag 'No browser heartbeat; service stops itself (EIGHTBELLS_AUTO_STOP=0 or -Stay keeps it running)'
    $script:running=$false
  }elseif($busy -eq 0 -and $script:tabs.Count -gt 1){
    Remove-EightBellsGoneTabs -Tabs $script:tabs -Now $now
  }
}
$server=$null
$instanceMutex=$null
$instanceOwned=$false
try{
  # Mutex names keep the former LogHawk ID so an old LogHawk copy and Eight Bells cannot run at the same time.
  $mutexName=if($testMode){'Local\LogHawk-v2-test-instance'}else{'Local\LogHawk-v2-single-instance'}
  $instanceMutex=[System.Threading.Mutex]::new($false,$mutexName)
  # A server stopped with Stop-Process leaves the mutex abandoned; taking it over is expected.
  try{$instanceOwned=$instanceMutex.WaitOne(0)}
  catch{
    $abandoned=($_.Exception -is [System.Threading.AbandonedMutexException]) -or ($_.Exception.InnerException -is [System.Threading.AbandonedMutexException])
    if(!$abandoned){throw}
    $instanceOwned=$true
  }
  if(!$instanceOwned){throw 'Eight Bells is already running in this Windows session. Use the open browser tab, End session, or Stop-EightBells.ps1 before relaunching.'}
  $server=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
  $server.Server.ExclusiveAddressUse=$true
  $server.Start(24)
  $script:port=([Net.IPEndPoint]$server.LocalEndpoint).Port
  $null=Load-State
  if(!(Test-Path $store)){Save-State (New-State)}
  [IO.File]::WriteAllText($ready,(J @{pid=$PID;port=$script:port}),[Text.Encoding]::UTF8)
  # Runtime file for Stop-EightBells.ps1 and the launchers. Never contains the session token.
  [IO.File]::WriteAllText($runtimeFile,(J ([ordered]@{pid=$PID;port=$script:port;url=('http://127.0.0.1:'+$script:port+'/');startedAt=$script:startedAt.ToString('o')})),[Text.Encoding]::UTF8)
  Diag ('Service ready on 127.0.0.1:'+$script:port)
  if($script:autoStop){Diag 'Auto-stop on: the service stops 20 s after the last browser heartbeat (5 s after the tab closes)'}else{Diag 'Auto-stop off (-Stay or EIGHTBELLS_AUTO_STOP=0); use End session or Stop-EightBells.ps1'}
  if(!$NoBrowser){
    try{Start-Process ('http://127.0.0.1:'+$script:port+'/#token='+$script:token)}catch{Diag 'Browser auto-start failed'}
  }
  $accept=$null
  while($script:running){
    # Wait for a connection at most 1 s at a time so the presence tick runs (and Ctrl+C is honoured) while idle.
    if($null -eq $accept){$accept=$server.AcceptTcpClientAsync()}
    if(!$accept.Wait(1000)){Invoke-PresenceTick;continue}
    $client=$accept.Result
    $accept=$null
    try{
      $client.ReceiveTimeout=15000;$client.SendTimeout=15000
      $stream=$client.GetStream()
      $began=[DateTime]::UtcNow
      try{$req=Read-Http $stream;Process-Http $req $stream}
      catch{Diag ('Request error: '+$_.Exception.GetType().Name);try{Reject $stream 400 'Malformed request'}catch{}}
    }finally{$client.Close()}
    # Heartbeats cannot be answered while a long request (AI call, large import) runs, so that time does not count against open tabs.
    if(([DateTime]::UtcNow-$began).TotalMilliseconds -ge 2000){Step-EightBellsPresenceAfterBusy -Tabs $script:tabs -Now ([DateTime]::UtcNow)}
    Invoke-PresenceTick
  }
}catch{Diag ('Fatal: '+$_.Exception.Message);throw}
finally{
  if($server){$server.Stop()}
  Remove-Item -LiteralPath $runtimeFile -Force -ErrorAction SilentlyContinue
  if($instanceMutex){if($instanceOwned){try{$instanceMutex.ReleaseMutex()}catch{}};$instanceMutex.Dispose()}
  if(Test-Path $ready){
    try{$r=Get-Content $ready -Raw|ConvertFrom-Json;if([int]$r.pid -eq $PID){Remove-Item $ready -Force}}catch{}
  }
  Diag 'Service stopped'
}
