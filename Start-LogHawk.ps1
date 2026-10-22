param([int]$Port = 0, [switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$web = Join-Path $root 'web'
$data = Join-Path $root 'data'
New-Item -ItemType Directory -Force -Path $data | Out-Null
$dbPath = Join-Path $data 'records.json'
if (!(Test-Path $dbPath)) { '{"logs":[],"lessons":[],"audit":[]}' | Set-Content -Path $dbPath -Encoding UTF8 }
function Read-Db { return (Get-Content -LiteralPath $dbPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
function Save-Db($db) {
  $tmp = "$dbPath.tmp"
  $db | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $tmp -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $dbPath -Force
}
function Reply($ctx, [int]$status, [string]$body, [string]$mime='application/json') {
  $bytes=[Text.Encoding]::UTF8.GetBytes($body)
  $ctx.Response.StatusCode=$status
  $ctx.Response.ContentType="$mime; charset=utf-8"
  $ctx.Response.Headers.Add('Cache-Control','no-store')
  $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
  $ctx.Response.Close()
}
function Json($obj) { return ConvertTo-Json -InputObject $obj -Depth 40 -Compress }
function Parse-Entries([string]$content) {
  $lines=$content -split '\r?\n'
  $out=@()
  $n=0
  foreach($line in $lines) {
    $n++
    if ([string]::IsNullOrWhiteSpace($line)) {continue}
    $time=$null
    if ($line -match '\b(?<h>[01]\d|2[0-3]):(?<m>[0-5]\d)\b') { $time="$($Matches.h):$($Matches.m)" }
    elseif ($line -match '^\s*(?<h>[01]\d|2[0-3])(?<m>[0-5]\d)\b') { $time="$($Matches.h):$($Matches.m)" }
    $issue= $line -match '(?i)\b(fail(?:ure|ed)?|fault|alarm|abnormal|leak|vibrat\w*|outage|inoperative|casualty|discrepancy|overheat\w*)\b'
    $resolution= $line -match '(?i)\b(restored|resolved|repaired|cleared|returned to service)\b'
    $out+= [pscustomobject]@{line=$n;time=$time;text=$line.Trim();issue=[bool]$issue;resolution=[bool]$resolution}
  }
  return ,$out
}
function Quality($entries) {
  $findings=@()
  $timed=@($entries | Where-Object { $_.time })
  $groups=@($entries | Group-Object text | Where-Object Count -ge 3)
  foreach($g in $groups) { $findings+=@{type='repetition';severity='review';detail="$($g.Count) identical entries: $($g.Name.Substring(0,[Math]::Min(90,$g.Name.Length)))"} }
  $previous=-1
  foreach($e in $timed) {
    $parts=$e.time.Split(':');$minutes=[int]$parts[0]*60+[int]$parts[1]
    if($previous -ge 0 -and $minutes -lt $previous) {$findings+=@{type='chronology';severity='review';detail="Timestamp moved backward at line $($e.line). Confirm date/watch boundary."}}
    $previous=$minutes
  }
  if ($timed.Count -eq 0) {$findings+=@{type='timestamp';severity='review';detail='No recognizable HHMM or HH:MM timestamps found.'}}
  $issues=@($entries | Where-Object issue)
  if($issues.Count -gt 0 -and @($entries | Where-Object resolution).Count -eq 0) {$findings+=@{type='disposition';severity='review';detail='Issue-related entries found without recognizable resolution language; verify manually.'}}
  return ,$findings
}
$listener=[Net.HttpListener]::new()
if($Port -eq 0) {
  $socket=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $socket.Start();$Port=([Net.IPEndPoint]$socket.LocalEndpoint).Port;$socket.Stop()
}
$prefix="http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "LogHawk running at $prefix (Ctrl+C to stop)"
if (!$NoBrowser) { Start-Process $prefix }
try {
 while($listener.IsListening) {
  $ctx=$listener.GetContext()
  try {
   $path=$ctx.Request.Url.AbsolutePath
   if ($ctx.Request.HttpMethod -eq 'GET' -and $path -eq '/') {
     Reply $ctx 200 ([IO.File]::ReadAllText((Join-Path $web 'index.html'))) 'text/html';continue
   }
   if ($ctx.Request.HttpMethod -eq 'GET' -and $path -eq '/api/state') {
     Reply $ctx 200 (Json (Read-Db));continue
   }
   if ($ctx.Request.HttpMethod -eq 'POST' -and $path -in @('/api/import','/api/lesson')) {
     if($ctx.Request.ContentLength64 -gt 2097152) {Reply $ctx 413 '{"error":"2MB maximum"}';continue}
     $reader=[IO.StreamReader]::new($ctx.Request.InputStream,[Text.Encoding]::UTF8)
     $raw=$reader.ReadToEnd();$reader.Close()
     if($raw.Length -gt 2097152) {Reply $ctx 413 '{"error":"2MB maximum"}';continue}
     $req=$raw | ConvertFrom-Json
     $db=Read-Db
     $id=[guid]::NewGuid().ToString('N')
     $now=[DateTime]::UtcNow.ToString('o')
     if($path -eq '/api/import') {
       $name=[string]$req.name;$content=[string]$req.content
       if(!$name -or !$content) {Reply $ctx 400 '{"error":"name and content required"}';continue}
       $entries=@(Parse-Entries $content)
       $findings=@(Quality $entries)
       $log=[pscustomobject]@{id=$id;name=$name.Substring(0,[Math]::Min(180,$name.Length));imported=$now;content=$content;entries=$entries;findings=$findings}
       $db.logs=@($db.logs)+@($log)
       $db.audit=@($db.audit)+@(@{at=$now;action='import';target=$id})
       Save-Db $db
       Reply $ctx 200 (Json $log);continue
     } else {
       $title=[string]$req.title;$body=[string]$req.body
       if(!$title -or !$body) {Reply $ctx 400 '{"error":"title and body required"}';continue}
       $lesson=[pscustomobject]@{id=$id;title=$title;body=$body;source=[string]$req.source;status='draft';created=$now}
       $db.lessons=@($db.lessons)+@($lesson)
       $db.audit=@($db.audit)+@(@{at=$now;action='lesson-draft';target=$id})
       Save-Db $db
       Reply $ctx 200 (Json $lesson);continue
     }
   }
   Reply $ctx 404 '{"error":"Not found"}'
  } catch {
   try {Reply $ctx 500 (Json @{error=$_.Exception.Message})} catch {}
  }
 }
} finally { $listener.Stop();$listener.Close() }
