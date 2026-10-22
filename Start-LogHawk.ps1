param([int]$Port=0,[switch]$NoBrowser,[switch]$Background,[switch]$Diagnostics,[string]$TestSessionToken='',[switch]$LocalDev)
$ErrorActionPreference='Stop'
# Windows PowerShell 5.1 does not always preload the DPAPI ProtectedData assembly.
# This is a standard .NET Framework assembly; no install, policy change, or CAC bypass.
Add-Type -AssemblyName System.Security -ErrorAction Stop
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$testMode=($env:LOGHAWK_TEST_SESSION -eq '1' -and $NoBrowser)
$base=if($LocalDev){Join-Path $env:LOCALAPPDATA 'LogHawk-LocalDev'}elseif($testMode -and $env:LOGHAWK_TEST_DATA_DIR){$env:LOGHAWK_TEST_DATA_DIR}else{Join-Path $env:LOCALAPPDATA 'LogHawk'}
$runtime=Join-Path $base 'runtime'
New-Item -ItemType Directory -Force -Path $base,$runtime | Out-Null
$ready=Join-Path $runtime 'ready.json'
$log=Join-Path $runtime 'service.log'
$store=Join-Path $base 'store.v2.dpapi'
if($LocalDev){Write-Host '[LOCAL DEV] Isolated LogHawk database; do not enter operational or sensitive records.' -ForegroundColor Yellow}
function Diag([string]$s){
  $line=[DateTime]::UtcNow.ToString('o')+' '+$s
  try{Add-Content -LiteralPath $log -Value $line -Encoding UTF8}catch{}
  if($Diagnostics){Write-Host $line}
}
if($Background){
  Remove-Item $ready -Force -ErrorAction SilentlyContinue
  $launchArgs='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$MyInvocation.MyCommand.Path+'"'
  if($Port -gt 0){$launchArgs+=' -Port '+$Port}
  $child=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $launchArgs -WindowStyle Hidden -PassThru
  $ok=$false
  for($i=0;$i -lt 80;$i++){
    Start-Sleep -Milliseconds 250
    if($child.HasExited){throw 'LogHawk startup failed; see '+$log}
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
  Write-Host ('LogHawk started on port '+$r.port)
  return
}
$script:running=$true
$script:ai=@{endpoint='';model='';key=''}
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
function Reply($stream,[int]$status,[string]$body,[string]$mime='application/json; charset=utf-8'){
  $reason=switch($status){200{'OK'}201{'Created'}400{'Bad Request'}401{'Unauthorized'}403{'Forbidden'}404{'Not Found'}413{'Payload Too Large'}500{'Internal Server Error'}default{'Error'}}
  $data=[Text.Encoding]::UTF8.GetBytes($body)
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
function Process-Http($req,$stream){
  $path=$req.path
  if($req.headers['host'] -ne ('127.0.0.1:'+$script:port)){Reject $stream 403 'Host rejected';return}
  if($req.method -eq 'GET' -and $path -eq '/health'){Reply $stream 200 (J @{status='ready';version=2});return}
  if($req.method -eq 'GET' -and $path -in @('/','/engine.js','/app.js','/styles.css')){
    $name=switch($path){'/'{'index.html'}'/engine.js'{'engine.js'}'/app.js'{'app.js'}'/styles.css'{'styles.css'}}
    $file=Join-Path (Join-Path $root 'web') $name
    if(!(Test-Path $file)){Reject $stream 404 'Missing UI asset';return}
    $mime=if($name.EndsWith('.js')){'application/javascript; charset=utf-8'}elseif($name.EndsWith('.css')){'text/css; charset=utf-8'}else{'text/html; charset=utf-8'}
    Reply $stream 200 ([IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)) $mime;return
  }
  if($req.headers['x-loghawk-token'] -cne $script:token){Reject $stream 401 'Invalid session';return}
  if($req.method -eq 'POST' -and $req.headers.ContainsKey('origin') -and $req.headers['origin'] -ne ('http://127.0.0.1:'+$script:port)){Reject $stream 403 'Origin rejected';return}
  if($req.method -eq 'GET' -and $path -eq '/api/state'){Reply $stream 200 (J (Load-State));return}
  if($req.method -eq 'GET' -and $path -eq '/api/diagnostics'){
    $lines=if(Test-Path $log){@(Get-Content $log -Tail 100)}else{@()}
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
    $endpoint=[string]$obj.endpoint
    if(!$endpoint){$script:ai=@{endpoint='';model='';key=''};Reply $stream 200 (J @{configured=$false});return}
    $uri=$null
    if(![Uri]::TryCreate($endpoint,[UriKind]::Absolute,[ref]$uri)){Reject $stream 400 'Invalid endpoint';return}
    if($uri.Scheme -ne 'https' -and !(($uri.Scheme -eq 'http') -and ($uri.Host -in @('127.0.0.1','localhost')))){Reject $stream 400 'Only HTTPS or local HTTP AI endpoints are allowed';return}
    if($uri.UserInfo){Reject $stream 400 'Credentials in endpoint are prohibited';return}
    $script:ai=@{endpoint=$endpoint;model=[string]$obj.model;key=[string]$obj.key}
    Reply $stream 200 (J @{configured=$true;model=$script:ai.model});return
  }
  if($path -eq '/api/vision'){
    if(!$script:ai.endpoint){Reject $stream 400 'Configure an approved vision-capable AI endpoint first';return}
    if($obj.consent -ne $true){Reject $stream 403 'Explicit image transmission consent is required';return}
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
    if($obj.consent -ne $true){Reject $stream 403 'Explicit consent required';return}
    $s=Load-State;$item=@($s.logs|Where-Object {$_.id -eq [string]$obj.logId})
    if(!$item){Reject $stream 404 'Log not found';return}
    $lines=@($item[0].entries|Select-Object -First 150|ForEach-Object {'Line '+$_.line+': '+$_.text})
    $prompt="SYNTHETIC TRAINING LOG. Draft watch turnover, cite line numbers, do not invent resolutions. SOURCE:"+[Environment]::NewLine+($lines -join [Environment]::NewLine)
    $body=J @{model=$script:ai.model;temperature=0.1;messages=@(@{role='system';content='Create a cautious evidence-linked turnover draft, plain text.'},@{role='user';content=$prompt})}
    $headers=@{}
    if($script:ai.key){$headers['Authorization']='Bearer '+$script:ai.key}
    try{
      $response=Invoke-RestMethod -Uri $script:ai.endpoint -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 90
      $answer=[string]$response.choices[0].message.content
      if(!$answer){throw 'Empty response'}
      Diag 'Manual AI request succeeded (no content logged)'
      Reply $stream 200 (J @{text=$answer;model=$script:ai.model;verified=$false});return
    }catch{Diag 'Manual AI request failed (no credentials logged)';Reject $stream 500 'AI request failed; inspect endpoint and model settings';return}
  }
  if($path -eq '/api/shutdown'){$script:running=$false;Reply $stream 200 (J @{ok=$true});return}
  Reject $stream 404 'Unknown route'
}
$server=$null
try{
  $server=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
  $server.Server.ExclusiveAddressUse=$true
  $server.Start(24)
  $script:port=([Net.IPEndPoint]$server.LocalEndpoint).Port
  $null=Load-State
  if(!(Test-Path $store)){Save-State (New-State)}
  [IO.File]::WriteAllText($ready,(J @{pid=$PID;port=$script:port}),[Text.Encoding]::UTF8)
  Diag ('Service ready on 127.0.0.1:'+$script:port)
  if(!$NoBrowser){
    try{Start-Process ('http://127.0.0.1:'+$script:port+'/#token='+$script:token)}catch{Diag 'Browser auto-start failed'}
  }
  while($script:running){
    $client=$server.AcceptTcpClient()
    try{
      $client.ReceiveTimeout=15000;$client.SendTimeout=15000
      $stream=$client.GetStream()
      try{$req=Read-Http $stream;Process-Http $req $stream}
      catch{Diag ('Request error: '+$_.Exception.GetType().Name);try{Reject $stream 400 'Malformed request'}catch{}}
    }finally{$client.Close()}
  }
}catch{Diag ('Fatal: '+$_.Exception.Message);throw}
finally{
  if($server){$server.Stop()}
  if(Test-Path $ready){
    try{$r=Get-Content $ready -Raw|ConvertFrom-Json;if([int]$r.pid -eq $PID){Remove-Item $ready -Force}}catch{}
  }
  Diag 'Service stopped'
}
