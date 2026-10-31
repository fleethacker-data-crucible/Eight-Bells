param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# CLI and API parity: the command registry, exit codes, every command against an isolated store, and a round trip with the server.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$cli=Join-Path $Root 'eightbells.ps1'
$samples=Join-Path $Root 'samples'
$sandbox=New-TestSandbox
$data=Join-Path $sandbox 'data'
$errFile=Join-Path $sandbox 'stderr.txt'
$svc=$null
function Run([string[]]$CliArgs,[string]$Dir=$data){
  $ErrorActionPreference='Continue'   # PowerShell 5.1 turns a native command's stderr into an error under Stop
  $out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli @CliArgs --data-dir $Dir 2>$errFile
  $code=$LASTEXITCODE
  $text=($out -join "`n")
  $json=$null;try{if($text.TrimStart().StartsWith('{')){$json=$text|ConvertFrom-Json}}catch{}
  return [pscustomobject]@{Code=$code;Text=$text;Json=$json;Err=$(if(Test-Path $errFile){(Get-Content $errFile -Raw)}else{''})}
}
function Expect([string[]]$CliArgs,[int]$Code,[string]$What){
  $r=Run $CliArgs
  if($r.Code -ne $Code){throw ('FAIL: '+$What+' - expected exit '+$Code+' but got '+$r.Code+"`n"+$r.Text+"`n"+$r.Err)}
  return $r
}
try{
  # ---- registry ----
  $r=Expect @('commands','--json') 0 'commands --json'
  Assert-True ($r.Json.schema -eq 'eightbells.commands/1') 'commands schema is versioned'
  $cmds=@($r.Json.commands)
  Assert-True ($cmds.Count -ge 13) 'the registry lists the commands'
  Assert-True ((@($cmds|ForEach-Object {$_.name}|Select-Object -Unique)).Count -eq $cmds.Count) 'command names are unique'
  foreach($c in $cmds){Assert-True ($c.route -match '^(GET|POST) /' -and $c.summary -and $null -ne $c.destructive -and $null -ne $c.inputs) ('command '+$c.name+' is fully described')}
  Assert-True (@($r.Json.excluded).Count -ge 5 -and -not @($r.Json.excluded|Where-Object {-not $_.reason}).Count) 'every excluded route has a reason'
  $text=Expect @('commands') 0 'commands (text)'
  Assert-True ($text.Text -match 'log import' -and $text.Text -match 'finding review') 'text listing names the commands'
  Assert-True ((Expect @() 0 'no arguments').Text -match 'Usage: eightbells') 'no arguments prints usage'

  # ---- parity: every server route is mirrored by a command or excluded with a reason ----
  $server=Get-Content -LiteralPath (Join-Path $Root 'Start-EightBells.ps1') -Raw
  $serverPaths=@([regex]::Matches($server,'\$path\s+-eq\s+''(/[^'']+)''')|ForEach-Object {$_.Groups[1].Value}|Select-Object -Unique)
  Assert-True ($serverPaths.Count -ge 10) 'the server routes were found'
  $mirrored=@($cmds|ForEach-Object {($_.route -split ' ')[1]}|Select-Object -Unique)
  $excluded=@($r.Json.excluded|ForEach-Object {($_.route -split ' ')[1]})
  foreach($p in $serverPaths){Assert-True (($mirrored -contains $p) -or ($excluded -contains $p)) ('server route '+$p+' has no command and no documented exclusion')}
  foreach($p in ($mirrored+$excluded)){Assert-True ($serverPaths -contains $p) ('registry names a route that the server does not have: '+$p)}
  Write-Host ('PASS: command registry (versioned schema, '+$cmds.Count+' commands) and parity with '+$serverPaths.Count+' server routes')

  # ---- usage errors exit 2 ----
  $u=Expect @('nope','cmd','--json') 2 'unknown command'
  Assert-True ($u.Json.ok -eq $false -and $u.Json.usage -eq $true) 'usage errors are marked in JSON'
  $null=Expect @('log','list','--bogus') 2 'unknown option'
  $null=Expect @('log','show') 2 'missing required option'
  $null=Expect @('log','list','extra') 2 'extra word'
  $null=Expect @('finding','review','--log','x','--finding','f1','--disposition','maybe','--note','n') 2 'invalid disposition'
  $null=Expect @('log','import','--file','x','--interval','abc') 2 'non-numeric interval'
  $null=Expect @('log','import','--file','x','--format','xml') 2 'unsupported format'
  $null=Expect @('export','json') 2 'destructive command without --yes'
  $null=Expect @('export','json','--yes') 2 'export without --out'
  Write-Host 'PASS: usage errors exit 2 with a plain message'

  # ---- empty store, import, list, show ----
  $s=(Expect @('status','show','--json') 0 'status on an empty folder').Json.result
  Assert-True ($s.storeExists -eq $false -and $s.logs -eq 0 -and $s.serverRunning -eq $false) 'an empty folder reports an empty store'
  $imp=(Expect @('log','import','--file',(Join-Path $samples 'engineering_discrepancy.txt'),'--name','Synthetic discrepancy','--watch','Engineering','--json') 0 'import text').Json
  Assert-True ($imp.ok -eq $true -and $imp.result.entries -gt 3 -and $imp.result.findings -ge 1 -and $imp.result.id) 'import stores entries and findings'
  $id1=$imp.result.id
  $id2=(Expect @('log','import','--file',(Join-Path $samples 'engineering_discrepancy.txt'),'--name','Second watch','--json') 0 'import again').Json.result.id
  $csv=(Expect @('log','import','--file',(Join-Path $samples 'readings.csv'),'--format','csv','--interval','30','--json') 0 'import csv').Json.result
  Assert-True ($csv.format -eq 'csv' -and $csv.entries -eq 8) 'CSV import parses rows'
  $list=@((Expect @('log','list','--json') 0 'list').Json.result.logs)
  Assert-True ($list.Count -eq 3 -and $list[0].name -eq 'Synthetic discrepancy' -and $list[1].watch -eq 'Other') 'list shows the three logs with defaults'
  $show=(Expect @('log','show','--id',$id1,'--json') 0 'show').Json.result
  Assert-True ($show.id -eq $id1 -and $show.entries -eq $imp.result.entries -and @($show.findings).Count -eq $imp.result.findings) 'show matches the import'
  $nf=Expect @('log','show','--id','nope','--json') 1 'unknown log'
  Assert-True ($nf.Json.ok -eq $false -and $nf.Json.usage -eq $false -and $nf.Json.error -match 'not found') 'runtime failures exit 1 with ok:false'
  $null=Expect @('log','import','--file',(Join-Path $sandbox 'missing.txt')) 1 'missing file'
  Write-Host 'PASS: import, list and show against an isolated store'

  # ---- findings, turnover, lessons, memory ----
  $fl=(Expect @('finding','list','--log',$id1,'--json') 0 'finding list').Json.result
  $disp=@($fl.findings|Where-Object {$_.type -eq 'disposition'})[0]
  Assert-True ($null -ne $disp -and $disp.reviews -eq 0) 'the unresolved condition is a finding with no reviews'
  $null=Expect @('finding','review','--log',$id1,'--finding',$disp.id,'--disposition','follow-up','--note','Synthetic verification only') 0 'review'
  Assert-True (@((Expect @('finding','list','--log',$id1,'--json') 0 'finding list').Json.result.findings|Where-Object {$_.id -eq $disp.id})[0].reviews -eq 1) 'the review is counted'
  $null=Expect @('finding','review','--log',$id1,'--finding','f999','--disposition','follow-up','--note','x') 1 'unknown finding'
  $null=Expect @('finding','review','--log',$id1,'--finding',$disp.id,'--disposition','follow-up','--note',' ') 1 'blank explanation'
  $tf=Join-Path $sandbox 'turnover.txt'
  $null=Expect @('turnover','show','--log',$id1,'--out',$tf) 0 'turnover'
  $bytes=[IO.File]::ReadAllBytes($tf)
  Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) '--out writes UTF-8 without a BOM'
  $tt=[IO.File]::ReadAllText($tf,[Text.Encoding]::UTF8)
  Assert-True ($tt -match 'WATCH TURNOVER' -and $tt -match 'Line \d+ \|' -and $tt -match 'POTENTIALLY OPEN CONDITIONS') 'the turnover draft has its sections and line references'
  $lid=(Expect @('lesson','add','--title','Synthetic lesson','--body','Evidence: Pump B, log one.','--source',$id1,'--json') 0 'lesson add').Json.result.id
  Assert-True (@((Expect @('lesson','list','--json') 0 'lesson list').Json.result.lessons)[0].status -eq 'draft') 'a new lesson is a draft'
  $null=Expect @('lesson','review','--id',$lid) 0 'lesson review'
  Assert-True (@((Expect @('lesson','list','--json') 0 'lesson list').Json.result.lessons)[0].status -eq 'reviewed') 'review marks it reviewed'
  $null=Expect @('lesson','review','--id','nope') 1 'unknown lesson'
  $cand=@((Expect @('memory','candidates','--json') 0 'candidates').Json.result.candidates)
  Assert-True ($cand.Count -ge 1 -and $cand[0].title -match 'Recurring condition') 'the same open condition in two logs is a candidate'
  Assert-True (@((Expect @('memory','search','--q','pump','--json') 0 'search').Json.result.results).Count -ge 1) 'search finds the log text'
  Assert-True ((Expect @('status','show','--json') 0 'status').Json.result.audit -ge 6) 'every write left an audit entry'
  Write-Host 'PASS: findings, reviews, turnover, lessons and memory'

  # ---- audit chain: the CLI's writes are chained, verify passes, and an edit to the store is caught ----
  $av=(Expect @('audit','verify','--json') 0 'audit verify').Json.result
  Assert-True ($av.valid -eq $true -and $av.chained -ge 6 -and $av.entries -ge $av.chained) 'the CLI''s own writes form a valid hash chain'
  $data2=Join-Path $sandbox 'data-tampered'
  New-Item -ItemType Directory -Force -Path $data2|Out-Null
  Copy-Item -LiteralPath (Join-Path $data 'store.v2.dpapi') -Destination $data2
  Add-Type -AssemblyName System.Security
  $store2=Join-Path $data2 'store.v2.dpapi'
  $plain=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($store2),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $state2=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json
  $state2.audit[0].target='rewritten-target'
  [IO.File]::WriteAllBytes($store2,[Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $state2 -Depth 70 -Compress)),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
  $bad=Run @('audit','verify','--json') $data2
  Assert-True ($bad.Code -eq 1 -and $bad.Json.ok -eq $false -and $bad.Json.usage -eq $false -and $bad.Json.error -match 'broken at entry 1') 'an edited audit entry makes audit verify exit 1 and name the entry'
  Write-Host 'PASS: audit verify (valid chain from the CLI''s own writes, edited entry detected)'

  # ---- dry run, --out, export ----
  $before=@((Expect @('log','list','--json') 0 'list').Json.result.logs).Count
  $dry=(Expect @('log','import','--file',(Join-Path $samples 'readings.csv'),'--dry-run','--json') 0 'dry run').Json.result
  Assert-True ($dry.dryRun -eq $true -and $dry.route -eq 'POST /api/import') 'dry run shows the route and request'
  Assert-True (@((Expect @('log','list','--json') 0 'list').Json.result.logs).Count -eq $before) 'dry run changes nothing'
  $of=Join-Path $sandbox 'list.json'
  $o=Expect @('log','list','--json','--out',$of) 0 '--out with --json'
  Assert-True ($o.Text -eq '' -and (Get-Content $of -Raw|ConvertFrom-Json).ok -eq $true) '--out sends the output to the file'
  $ef=Join-Path $sandbox 'export.json'
  $ex=(Expect @('export','json','--out',$ef,'--yes','--json') 0 'export').Json.result
  Assert-True ($ex.encrypted -eq $false -and (Get-Content $ef -Raw|ConvertFrom-Json).logs.Count -eq 3) 'export writes all records, unencrypted, and says so'
  Write-Host 'PASS: dry run, --out (no BOM) and the unencrypted export gate'

  # ---- round trip with the server on the same folder ----
  $svc=Start-TestService $Root $data 'synthetic-cli-test-token-987'
  $st=Invoke-RestMethod -Uri ($svc.Url+'/api/state') -Headers $svc.Headers
  Assert-True (@($st.logs).Count -eq 3 -and @($st.lessons).Count -eq 1 -and @($st.reviews).Count -eq 1) 'the server opens the store the CLI wrote'
  Assert-True ($st.logs[0].entries[0].line -ge 1 -and $st.logs[0].analysis.findings[0].id -match '^f\d+$') 'CLI records have the fields the page expects'
  $run=(Expect @('status','show','--json') 0 'status while the server runs').Json.result
  Assert-True ($run.serverRunning -eq $true) 'status sees the running server'
  $w=Expect @('lesson','add','--title','x','--body','y','--json') 1 'write while the server runs'
  Assert-True ($w.Json.error -match 'running') 'writes are refused while the server runs'
  $null=Expect @('log','list') 0 'read while the server runs'
  $null=Post-Json $svc '/api/lesson' @{title='Server lesson';body='Written by the page';source=''}
  Assert-True (@((Expect @('lesson','list','--json') 0 'list').Json.result.lessons).Count -eq 2) 'the CLI reads what the server wrote'
  Stop-TestProcess $svc;$svc=$null
  $null=Expect @('lesson','add','--title','After stop','--body','Allowed again') 0 'write after the server stops'
  Write-Host 'PASS: the CLI and the server share one store; writes wait for the server to stop'
}finally{
  Stop-TestProcess $svc
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
