# eightbells <noun> <verb> [--option value ...] [--json] [--out file] [--yes] [--dry-run] [--data-dir folder] [--local-dev]
# eightbells commands [--json]
# Every UI action on the stored data is a command (see docs/CLI.md). It runs in its own process, opens no port and starts
# no server, and reads and writes the same encrypted store as the browser app. Exit codes: 0 ok, 1 the command ran and
# failed, 2 usage error (unknown command or option, missing or invalid option, destructive command without --yes).
# No param block on purpose: a [Parameter()] attribute makes this an advanced script, and PowerShell would then read
# --out (and --verbose, --debug) as its own common parameters. Plain $args keeps every token for this script.
$Rest=@($args)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'EightBells-Process.ps1')
. (Join-Path $root 'EightBells-Engine.ps1')
$auditFile=Join-Path $root 'EightBells-Audit.ps1'
if(Test-Path -LiteralPath $auditFile){. $auditFile}
. (Join-Path $root 'EightBells-Store.ps1')
. (Join-Path $root 'EightBells-Commands.ps1')
try{[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)}catch{}
$ResultSchema='eightbells.result/1';$CommandsSchema='eightbells.commands/1'
$boolFlags='json','yes','dry-run','local-dev','help';$valueFlags='out','data-dir'
$commandName='eightbells'
$wantJson=$false
function Stop-Usage([string]$m){throw ('USAGE: '+$m)}
function Out-EbText([string]$text,[string]$outFile){
  if($outFile){[IO.File]::WriteAllText($outFile,$text,(New-Object System.Text.UTF8Encoding($false)))}
  else{[Console]::Out.WriteLine($text)}
}
function Find-EbLog($state,[string]$id){
  $m=@(@($state.logs)|Where-Object {$_.id -eq $id})
  if(-not $m.Count){throw ('Log not found: '+$id)}
  return $m[0]
}
function Test-EbServerRunning([string]$dir){return (@(Get-EightBellsProcesses -DataDir @($dir) -NoProcessScan).Count -gt 0)}
function Format-EbHuman([string]$name,$r){
  switch($name){
    'turnover show'{return [string]$r.text}
    'status show'{return ((@('dataDir','storeExists','serverRunning','logs','lessons','reviews','audit')|ForEach-Object {$_+': '+$r.$_}) -join "`n")}
    'log list'{if(-not @($r.logs).Count){return 'No logs.'};return ((@($r.logs)|ForEach-Object {$_.id+'  '+$_.name+'  ['+$_.watch+']  '+$_.entries+' entries, '+$_.findings+' findings'}) -join "`n")}
    'finding list'{if(-not @($r.findings).Count){return 'No findings.'};return ((@($r.findings)|ForEach-Object {$_.id+'  '+$_.type+'  lines '+(@($_.lines) -join ',')+'  '+$_.detail+'  ('+$_.reviews+' reviews)'}) -join "`n")}
    'lesson list'{if(-not @($r.lessons).Count){return 'No lessons.'};return ((@($r.lessons)|ForEach-Object {$_.id+'  '+$_.status+'  '+$_.title}) -join "`n")}
    default{return (ConvertTo-Json -InputObject $r -Depth 8)}
  }
}
$exit=0
try{
  # ---- parse the command line ----
  $positional=New-Object System.Collections.ArrayList;$opts=@{};$tokens=@($Rest)
  for($i=0;$i -lt $tokens.Count;$i++){
    $t=[string]$tokens[$i]
    if($t.StartsWith('--') -and $t.Length -gt 2){
      $n=$t.Substring(2)
      if($boolFlags -contains $n){$opts[$n]=$true}
      else{
        if($i+1 -ge $tokens.Count -or ([string]$tokens[$i+1]).StartsWith('--')){$opts[$n]=$null;$opts['__missing__'+$n]=$true}
        else{$opts[$n]=[string]$tokens[$i+1];$i++}
      }
    }else{[void]$positional.Add($t)}
  }
  $wantJson=($opts.json -eq $true)
  $registry=@(Get-EightBellsCommands)
  if($positional.Count -eq 0 -or $opts.help -eq $true){
    $commandName='help'
    $lines=@('Usage: eightbells <noun> <verb> [--option value ...] [--json] [--out file] [--yes] [--dry-run] [--data-dir folder] [--local-dev]','       eightbells commands [--json]','','Commands:')+@($registry|ForEach-Object {'  '+$_.name.PadRight(18)+$_.summary})
    Out-EbText ($lines -join "`n") $null
    exit 0
  }
  # ---- commands --json ----
  if($positional[0] -eq 'commands' -and $positional.Count -eq 1){
    $commandName='commands'
    if($wantJson){
      Out-EbText (ConvertTo-Json -InputObject ([ordered]@{schema=$CommandsSchema;commands=[object[]]$registry;excluded=[object[]]@(Get-EightBellsExcludedRoutes)}) -Depth 8) $opts.out
    }else{
      Out-EbText ((@($registry|ForEach-Object {$_.name.PadRight(18)+$_.route.PadRight(26)+$_.summary})) -join "`n") $opts.out
    }
    exit 0
  }
  if($positional.Count -ne 2){Stop-Usage ('expected <noun> <verb>, got '+($positional -join ' '))}
  $name=$positional[0]+' '+$positional[1];$commandName=$name
  $cmd=$registry|Where-Object {$_.name -eq $name}|Select-Object -First 1
  if(-not $cmd){Stop-Usage ('unknown command "'+$name+'"; run "eightbells commands"')}
  # ---- validate options against the registry ----
  $known=@($cmd.inputs|ForEach-Object {$_.flag})+$boolFlags+$valueFlags
  foreach($k in @($opts.Keys)){
    if($k -like '__missing__*'){
      $flagName=$k.Substring(11)
      if($known -notcontains $flagName){Stop-Usage ('unknown option --'+$flagName+' for "'+$name+'"')}
      Stop-Usage ('option --'+$flagName+' needs a value')
    }
    if($known -notcontains $k){Stop-Usage ('unknown option --'+$k+' for "'+$name+'"')}
  }
  foreach($in in $cmd.inputs){
    $v=$opts[$in.flag]
    if($in.required -and [string]::IsNullOrEmpty([string]$v)){Stop-Usage ('missing required option --'+$in.flag)}
    if($null -ne $v){
      if($in.type -eq 'number'){$d=0.0;if(-not [double]::TryParse([string]$v,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$d) -or $d -lt 0){Stop-Usage ('--'+$in.flag+' must be a number of 0 or more')}}
      # Contains('values'): an ordered dictionary's own .Values property would otherwise stand in for a missing key.
      if($in.Contains('values') -and ($in['values'] -notcontains [string]$v)){Stop-Usage ('--'+$in.flag+' must be one of: '+($in['values'] -join ', '))}
    }
  }
  if($cmd.destructive -and $opts.yes -ne $true){Stop-Usage ('"'+$name+'" is destructive; add --yes')}
  if($name -eq 'export json' -and -not $opts.out){Stop-Usage '"export json" needs --out <file>'}
  $dataDir=Get-EightBellsDataDir ([string]$opts.'data-dir') -LocalDev:($opts.'local-dev' -eq $true)
  # ---- dry run: show the route and request, then stop ----
  if($opts.'dry-run' -eq $true){
    $req=[ordered]@{};foreach($in in $cmd.inputs){if($null -ne $opts[$in.flag]){$req[$in.flag]=$opts[$in.flag]}}
    $result=[ordered]@{dryRun=$true;route=$cmd.route;request=$req}
  }else{
    if($cmd.writes -and (Test-EbServerRunning $dataDir)){throw 'Eight Bells is running for this data folder. Stop it first (Stop-EightBells.ps1) or use the browser, so two writers do not overwrite each other.'}
    $state=Read-EightBellsStore $dataDir
    switch($name){
      'status show'{
        $result=[ordered]@{dataDir=$dataDir;storeExists=(Test-Path -LiteralPath (Join-Path $dataDir 'store.v2.dpapi'));serverRunning=(Test-EbServerRunning $dataDir);logs=@($state.logs).Count;lessons=@($state.lessons).Count;reviews=@($state.reviews).Count;audit=@($state.audit).Count}
      }
      'log list'{
        $list=@(@($state.logs)|ForEach-Object {[ordered]@{id=$_.id;name=$_.name;watch=$_.watch;format=$_.format;imported=$_.imported;entries=@($_.entries).Count;findings=@($_.analysis.findings).Count;open=@($_.analysis.open).Count}})
        $result=[ordered]@{logs=[object[]]$list}
      }
      'log show'{
        $l=Find-EbLog $state $opts.id
        $result=[ordered]@{id=$l.id;name=$l.name;watch=$l.watch;format=$l.format;sourceType=$l.sourceType;imported=$l.imported;entries=@($l.entries).Count;score=$l.analysis.score;findings=[object[]]@($l.analysis.findings);open=[object[]]@($l.analysis.open)}
      }
      'log import'{
        $file=[string]$opts.file
        if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw ('File not found: '+$file)}
        $info=Get-Item -LiteralPath $file
        if($info.Length -gt 1500000){throw 'Text too large (limit 1.5 MB)'}
        $content=[IO.File]::ReadAllText($info.FullName,(New-Object System.Text.UTF8Encoding($false)))
        if(-not $content.Trim()){throw 'The file is empty'}
        $fmt=$(if($opts.format){[string]$opts.format}else{'auto'})
        $parsed=Invoke-EightBellsParse $content $fmt
        if(@($parsed.entries).Count -gt 10000){throw 'Too many entries (limit 10000)'}
        $interval=$(if($opts.interval){[double]::Parse([string]$opts.interval,[Globalization.CultureInfo]::InvariantCulture)}else{0})
        $analysis=Invoke-EightBellsAnalyze $parsed.entries $interval
        $title=$(if($opts.name){[string]$opts.name}else{$info.Name});$title=$title.Substring(0,[Math]::Min(150,$title.Length))
        $id=[guid]::NewGuid().ToString('N')
        $item=[pscustomobject]@{id=$id;name=$title;format=$parsed.format;sourceType='digital-text';watch=$(if($opts.watch){[string]$opts.watch}else{'Other'});content=$content;entries=@($parsed.entries);analysis=$analysis;imported=[DateTime]::UtcNow.ToString('o')}
        $state.logs=@($state.logs)+@($item);Add-EightBellsStoreAudit $state 'import' $id;Write-EightBellsStore $dataDir $state
        $result=[ordered]@{id=$id;name=$title;format=$parsed.format;entries=@($parsed.entries).Count;findings=@($analysis.findings).Count;open=@($analysis.open).Count;score=$analysis.score}
      }
      'finding list'{
        $l=Find-EbLog $state $opts.log
        $list=@(@($l.analysis.findings)|ForEach-Object {$f=$_;[ordered]@{id=$f.id;type=$f.type;priority=$f.priority;detail=$f.detail;lines=[object[]]@($f.lines);reviews=@(@($state.reviews)|Where-Object {$_.logId -eq $l.id -and $_.findingId -eq $f.id}).Count}})
        $result=[ordered]@{log=$l.id;findings=[object[]]$list}
      }
      'finding review'{
        $l=Find-EbLog $state $opts.log
        if(-not @(@($l.analysis.findings)|Where-Object {$_.id -eq [string]$opts.finding}).Count){throw ('Finding not found: '+$opts.finding)}
        if([string]::IsNullOrWhiteSpace([string]$opts.note)){throw 'Explanation required'}
        $id=[guid]::NewGuid().ToString('N');$note=[string]$opts.note
        $state.reviews=@($state.reviews)+@(@{id=$id;logId=$l.id;findingId=[string]$opts.finding;disposition=[string]$opts.disposition;note=$note.Substring(0,[Math]::Min(2000,$note.Length));at=[DateTime]::UtcNow.ToString('o')})
        Add-EightBellsStoreAudit $state 'quality-review' $id;Write-EightBellsStore $dataDir $state
        $result=[ordered]@{id=$id;log=$l.id;finding=[string]$opts.finding;disposition=[string]$opts.disposition}
      }
      'turnover show'{
        $l=Find-EbLog $state $opts.log
        $result=[ordered]@{log=$l.id;text=(Get-EightBellsTurnover $l)}
      }
      'lesson list'{
        $list=@(@($state.lessons)|ForEach-Object {[ordered]@{id=$_.id;title=$_.title;status=$_.status;source=$_.source;created=$_.created}})
        $result=[ordered]@{lessons=[object[]]$list}
      }
      'lesson add'{
        $id=[guid]::NewGuid().ToString('N')
        $lesson=[pscustomobject]@{id=$id;title=[string]$opts.title;body=[string]$opts.body;source=[string]$opts.source;status='draft';created=[DateTime]::UtcNow.ToString('o')}
        $state.lessons=@($state.lessons)+@($lesson);Add-EightBellsStoreAudit $state 'lesson-draft' $id;Write-EightBellsStore $dataDir $state
        $result=[ordered]@{id=$id;title=$lesson.title;status='draft'}
      }
      'lesson review'{
        $found=$false
        foreach($lesson in @($state.lessons)){if($lesson.id -eq [string]$opts.id){$lesson.status='reviewed';$found=$true;break}}
        if(-not $found){throw ('Lesson not found: '+$opts.id)}
        Add-EightBellsStoreAudit $state 'lesson-reviewed' ([string]$opts.id);Write-EightBellsStore $dataDir $state
        $result=[ordered]@{id=[string]$opts.id;status='reviewed'}
      }
      'memory candidates'{
        $result=[ordered]@{candidates=[object[]]@(Get-EightBellsCandidates @($state.logs))}
      }
      'memory search'{
        $q=([string]$opts.q).ToLowerInvariant()
        $docs=@(@($state.lessons)|ForEach-Object {@{title=[string]$_.title;content=[string]$_.body;source='Lesson '+$_.status;id=$_.id}})+@(@($state.logs)|ForEach-Object {@{title=[string]$_.name;content=[string]$_.content;source='Log source';id=$_.id}})
        $hits=@($docs|Where-Object {-not $q -or (($_.title+' '+$_.content).ToLowerInvariant().Contains($q))}|Select-Object -First 12|ForEach-Object {[ordered]@{id=$_.id;title=$_.title;source=$_.source;snippet=$_.content.Substring(0,[Math]::Min(160,$_.content.Length))}})
        $result=[ordered]@{results=[object[]]$hits}
      }
      'export json'{
        $json=ConvertTo-Json -InputObject $state -Depth 70
        [IO.File]::WriteAllText([string]$opts.out,$json,(New-Object System.Text.UTF8Encoding($false)))
        $result=[ordered]@{path=[string]$opts.out;bytes=(Get-Item -LiteralPath ([string]$opts.out)).Length;encrypted=$false}
      }
    }
  }
  if($name -eq 'export json' -and $opts.'dry-run' -ne $true){
    $text=$(if($wantJson){ConvertTo-Json -InputObject ([ordered]@{schema=$ResultSchema;command=$name;ok=$true;result=$result}) -Depth 8}else{'Wrote an UNENCRYPTED export to '+$result.path})
    Out-EbText $text $null
  }else{
    $text=$(if($wantJson){ConvertTo-Json -InputObject ([ordered]@{schema=$ResultSchema;command=$name;ok=$true;result=$result}) -Depth 20}else{Format-EbHuman $name $result})
    Out-EbText $text $opts.out
  }
}catch{
  $msg=$_.Exception.Message
  $usage=$msg.StartsWith('USAGE: ')
  if($usage){$msg=$msg.Substring(7);$exit=2}else{$exit=1}
  if($wantJson){[Console]::Out.WriteLine((ConvertTo-Json -InputObject ([ordered]@{schema=$ResultSchema;command=$commandName;ok=$false;error=$msg;usage=$usage}) -Depth 4))}
  else{[Console]::Error.WriteLine('eightbells: '+$msg)}
}
exit $exit
