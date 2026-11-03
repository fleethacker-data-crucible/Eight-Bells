# Windows PowerShell 5.1 port of web/engine.js: parse (text, CSV, JSON), analyze, turnover and candidates.
# It exists so the command line and the server can parse and check a log without a browser or Node, and so the
# parse that is stored does not have to be trusted from the page. tests/golden/engine.golden.json is produced by the
# JavaScript engine (tools/gen-golden.js) and tests/Engine-Test.ps1 holds this port to it, entry by entry and finding by
# finding. If engine.js changes, regenerate the golden file and make this port agree. The e-log adapters (JSON Lines,
# tables, XML) and PDF reading are browser-side features and are not ported.
$script:EbIssue=[regex]::new('\b(abnormal|fault|failure|failed|alarm|leak|vibrat\w*|outage|inoperative|casualty|discrepanc\w*|overheat\w*|pending|degrad\w*|intermittent|issue|problem)\b','IgnoreCase')
$script:EbNegative=[regex]::new('\b(no new (?:discrepanc\w*|faults?|issues?|alarms?)|no (?:discrepanc\w*|faults?|issues?|alarms?) (?:observed|reported|noted)|without incident)\b','IgnoreCase')
$script:EbResolved=[regex]::new('\b(resolved|restored|repaired|cleared|returned to service|corrected|closed)\b','IgnoreCase')
$script:EbEntity=[regex]::new('\b(pump|loop|valve|sensor|generator|compressor|fan|gate|tag|alarm|motor|breaker)\s*(?:#|no\.?\s*)?([A-Z0-9-]+)?\b','IgnoreCase')
$script:EbTime1=[regex]::new('\b(?:20\d\d-\d\d-\d\d[T ]+)?([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\b')
$script:EbTime2=[regex]::new('^\s*([01]\d|2[0-3])([0-5]\d)\b')
$script:EbDot=[string][char]0x00B7

function ConvertTo-EbClean($s){
  if($null -eq $s){return ''}
  return ([regex]::Replace([string]$s,'\s+',' ')).Trim()
}
function Test-EbRowHasText($row){foreach($c in $row){if(([string]$c).Trim() -ne ''){return $true}};return $false}
# Same quoting rules as engine.csv: doubled quotes, commas and line breaks inside quotes, blank rows skipped.
function Read-EbCsv([string]$text){
  $out=New-Object System.Collections.ArrayList
  $row=New-Object System.Collections.ArrayList
  $val=New-Object System.Text.StringBuilder
  $quote=$false
  for($i=0;$i -lt $text.Length;$i++){
    $c=$text[$i]
    if($c -eq [char]34){
      if($quote -and ($i+1) -lt $text.Length -and $text[$i+1] -eq [char]34){[void]$val.Append([char]34);$i++}
      else{$quote=-not $quote}
    }elseif($c -eq [char]44 -and -not $quote){
      [void]$row.Add($val.ToString());[void]$val.Clear()
    }elseif(($c -eq [char]10 -or $c -eq [char]13) -and -not $quote){
      if($c -eq [char]13 -and ($i+1) -lt $text.Length -and $text[$i+1] -eq [char]10){$i++}
      [void]$row.Add($val.ToString());[void]$val.Clear()
      if(Test-EbRowHasText $row){[void]$out.Add($row.ToArray())}
      $row=New-Object System.Collections.ArrayList
    }else{[void]$val.Append($c)}
  }
  if($quote){throw 'CSV has an unclosed quoted field'}
  [void]$row.Add($val.ToString())
  if(Test-EbRowHasText $row){[void]$out.Add($row.ToArray())}
  return $out.ToArray()
}
# Case-insensitive field lookup; like engine get(): the first key that exists decides, even when its value is empty.
function Get-EbField($o,[string[]]$keys){
  if($null -eq $o){return ''}
  $isDict=($o -is [System.Collections.IDictionary])
  $names=if($isDict){@($o.Keys)}else{@($o.PSObject.Properties|ForEach-Object {$_.Name})}
  foreach($k in $keys){
    $actual=$null
    foreach($n in $names){if(([string]$n).ToLowerInvariant() -eq $k.ToLowerInvariant()){$actual=$n;break}}
    if($null -ne $actual){
      $v=if($isDict){$o[$actual]}else{$o.$actual}
      if($null -ne $v){return (ConvertTo-EbClean $v)}
    }
  }
  return ''
}
function Get-EbTime($s){
  $s=[string]$s
  $m=$script:EbTime1.Match($s)
  if(-not $m.Success -and $s -notmatch '^\s*20\d\d[-/]'){$m=$script:EbTime2.Match($s)}
  if($m.Success){return $m.Groups[1].Value+':'+$m.Groups[2].Value}
  return $null
}
function ConvertTo-EbEntries($rows){
  $entries=New-Object System.Collections.ArrayList
  $i=0
  foreach($r in $rows){
    $i++
    $entity=[string]$r.equipment
    if(-not $entity){
      $m=$script:EbEntity.Match([string]$r.text);$parts=@()
      if($m.Success){for($g=1;$g -lt $m.Groups.Count;$g++){if($m.Groups[$g].Success -and $m.Groups[$g].Value){$parts+=$m.Groups[$g].Value}}}
      $entity=($parts -join ' ')
    }
    $t=[string]$r.text
    [void]$entries.Add([ordered]@{
      id=$i;line=$r.line;time=$r.time;text=$t
      equipment=$(if($entity){$entity}else{$null})
      issue=($script:EbIssue.IsMatch($t) -and -not $script:EbNegative.IsMatch($t))
      resolution=$script:EbResolved.IsMatch($t)
      raw=$r.raw
    })
  }
  return $entries.ToArray()
}
# Returns @{format; entries; warnings}. Formats: auto, text/log/md, csv, json (as engine.parse).
function Invoke-EightBellsParse([string]$Content,[string]$Format='auto'){
  $f=$Format.ToLowerInvariant()
  if($f -eq 'auto'){
    $x=$Content.Trim()
    if($x -match '^[\[{]'){$f='json'}
    elseif($Content -match '^[^\n]+,[^\n]+\n' -and $x -match '^(?i:date|time|timestamp|equipment|watch|entry)'){$f='csv'}
    else{$f='text'}
  }
  $rows=New-Object System.Collections.ArrayList
  if($f -eq 'json'){
    $obj=ConvertFrom-Json -InputObject $Content
    $data=$null
    if($obj -is [System.Array]){$data=$obj}
    else{
      foreach($key in 'entries','records','logs','items'){
        $p=$obj.PSObject.Properties|Where-Object {$_.Name -ceq $key}|Select-Object -First 1
        if($p -and $null -ne $p.Value){$data=$p.Value;break}
      }
      if($null -eq $data){$data=@()}
    }
    if($data -isnot [System.Array]){throw 'JSON requires an array or an entries/records/logs/items array'}
    $i=0
    foreach($r in $data){
      $i++
      $isString=($r -is [string])
      $s=if($isString){$r}else{Get-EbField $r @('text','description','observation','message','event','notes')}
      $e=if($isString){''}else{Get-EbField $r @('equipment','asset','component')}
      $t=if($isString){''}else{Get-EbField $r @('timestamp','datetime','time')}
      $text=ConvertTo-EbClean ((@($e,$s)|Where-Object {$_}) -join ': ')
      if(-not $text){$text=ConvertTo-Json -InputObject $r -Compress -Depth 8}
      $time=Get-EbTime $t;if(-not $time){$time=Get-EbTime $s}
      [void]$rows.Add(@{line=$i;text=$text;time=$time;equipment=$e;raw=$r})
    }
  }elseif($f -eq 'csv'){
    $table=@(Read-EbCsv $Content)
    if($table.Count -eq 0){throw 'CSV contains no header'}
    $head=@($table[0]|ForEach-Object {([string]$_).Trim()})
    for($i=1;$i -lt $table.Count;$i++){
      $values=@($table[$i]);$obj=[ordered]@{}
      for($j=0;$j -lt $head.Count;$j++){$obj[$head[$j]]=$(if($j -lt $values.Count -and $values[$j]){$values[$j]}else{''})}
      $t=Get-EbField $obj @('timestamp','datetime','time');$e=Get-EbField $obj @('equipment','asset','component')
      $val=Get-EbField $obj @('value');$unit=Get-EbField $obj @('unit');$type=Get-EbField $obj @('reading_type','metric','parameter')
      $d=Get-EbField $obj @('description','text','entry','observation','message','status')
      $reading=if($type){$type+': '+$val+$(if($unit){' '+$unit}else{''})}else{''}
      $s=ConvertTo-EbClean ((@($e,$reading,$d)|Where-Object {$_}) -join ' | ')
      [void]$rows.Add(@{line=$i+1;text=$(if($s){$s}else{$values -join ' | '});time=(Get-EbTime $t);equipment=$e;raw=$obj})
    }
  }elseif($f -in 'text','log','md'){
    $n=0
    foreach($line in ($Content -split '\r?\n')){
      $n++;$c=ConvertTo-EbClean $line
      if($c){[void]$rows.Add(@{line=$n;text=$c;time=(Get-EbTime $line);equipment='';raw=$line})}
    }
  }else{throw ('Unsupported format '+$f)}
  return @{format=$f;entries=@(ConvertTo-EbEntries $rows.ToArray());warnings=@()}
}
function Get-EbReadingKey([string]$text){
  $s=ConvertTo-EbClean $text
  $s=[regex]::Replace($s,'^(?:20\d\d-\d\d-\d\d[T ]+)?(?:[01]\d|2[0-3]):?[0-5]\d\s*[-:|]?\s*','')
  $s=[regex]::Replace($s,'^\s*(?:\d{4})\s*[-:|]?\s*','')
  return $s.ToLowerInvariant()
}
function Invoke-EightBellsAnalyze($Entries,[double]$IntervalMinutes=0){
  $entries=@($Entries);$findings=New-Object System.Collections.ArrayList;$open=New-Object System.Collections.ArrayList
  $add={param($type,$detail,$lines)[void]$findings.Add([ordered]@{id='f'+($findings.Count+1);type=$type;detail=$detail;lines=[object[]]@($lines);priority='review'})}
  $sig=[ordered]@{}
  foreach($e in $entries){
    $s=Get-EbReadingKey $e.text
    if($s.Length -lt 9){continue}
    if(-not $sig.Contains($s)){$sig[$s]=New-Object System.Collections.ArrayList}
    [void]$sig[$s].Add($e.line)
  }
  foreach($s in @($sig.Keys)){
    $lines=$sig[$s]
    if($lines.Count -ge 3){& $add 'copy-forward' ('Narrative or readings repeated '+$lines.Count+' times; verify against source instruments.') $lines.ToArray()}
  }
  $prev=$null
  foreach($e in $entries){
    if(-not $e.time){continue}
    $hm=([string]$e.time).Split(':');$n=[int]$hm[0]*60+[int]$hm[1]
    if($prev){
      $delta=$n-$prev.minutes
      if($delta -lt 0 -and $delta -ge -720){& $add 'chronology' 'Time moved backwards; check late entries and date boundary.' @($prev.line,$e.line)}
      if($delta -gt 1440){$delta=$delta % 1440}
      if($IntervalMinutes -gt 0 -and $delta -gt $IntervalMinutes*1.75 -and $delta -lt 600){& $add 'interval-gap' ('Observed '+$delta+' minute gap versus configured '+$IntervalMinutes+' minute interval.') @($prev.line,$e.line)}
    }
    $prev=@{minutes=$n;line=$e.line}
  }
  if(-not (@($entries|Where-Object {$_.time}).Count)){& $add 'timestamps' 'No machine-recognizable log timestamps. Human verification required.' @($entries|Select-Object -First 3|ForEach-Object {$_.line})}
  $byEntity=[ordered]@{}
  foreach($e in $entries){
    $key=$(if($e.equipment){[string]$e.equipment}else{'unattributed'}).ToLowerInvariant().Trim()
    if($e.issue -and -not $e.resolution){
      if(-not $byEntity.Contains($key)){$byEntity[$key]=New-Object System.Collections.ArrayList}
      [void]$byEntity[$key].Add($e)
    }
    if($e.resolution -and $e.equipment){if($byEntity.Contains($key)){$byEntity.Remove($key)}}
  }
  foreach($asset in @($byEntity.Keys)){
    $es=$byEntity[$asset]
    $lineNumbers=[object[]]@($es|ForEach-Object {$_.line})
    [void]$open.Add([ordered]@{equipment=$(if($asset -eq 'unattributed'){'Unattributed'}else{$es[0].equipment});lines=$lineNumbers;latest=$es[$es.Count-1].text})
    & $add 'disposition' ('Potential unresolved condition ('+$(if($asset){$asset}else{'unattributed'})+'); check actual equipment state and follow-up records.') $lineNumbers
  }
  $copy=@($findings|Where-Object {$_.type -eq 'copy-forward'}).Count;$other=$findings.Count-$copy
  return [ordered]@{findings=$findings.ToArray();open=$open.ToArray();score=[Math]::Max(0,100-$other*10-$copy*8);graded='Advisory only; score does not establish log truthfulness.'}
}
function Get-EightBellsTurnover($Log){
  $a=$Log.analysis;if(-not $a){$a=Invoke-EightBellsAnalyze @($Log.entries)}
  $events=@(@($Log.entries)|Where-Object {$_.issue -or $_.resolution})
  $name=$(if($Log.name){$Log.name}else{'Untitled'});$id=$(if($Log.id){$Log.id}else{'?'})
  $lines=New-Object System.Collections.ArrayList
  foreach($l in @(('WATCH TURNOVER '+$script:EbDot+' REVIEW DRAFT'),$name,('Source '+$id+' '+$script:EbDot+' '+[string]$Log.imported),'','RELEVANT OBSERVATIONS')){[void]$lines.Add($l)}
  foreach($e in $events){[void]$lines.Add('Line '+$e.line+' | '+$(if($e.time){$e.time}else{'Unknown time'})+' | '+$e.text)}
  if(-not $events.Count){[void]$lines.Add('No issue keywords detected; this does not establish there were no issues.')}
  [void]$lines.Add('');[void]$lines.Add('POTENTIALLY OPEN CONDITIONS')
  $openList=@($a.open)
  foreach($o in $openList){[void]$lines.Add($(if($o.equipment){$o.equipment}else{'Unknown'})+': '+$o.latest+' (source line '+@($o.lines)[-1]+')')}
  if(-not $openList.Count){[void]$lines.Add('None inferred. Verify against official status records.')}
  [void]$lines.Add('');[void]$lines.Add('DOCUMENT QUALITY REVIEW')
  $fl=@($a.findings)
  foreach($f in $fl){[void]$lines.Add($f.type+': '+$f.detail+' [lines '+(@($f.lines) -join ', ')+']')}
  if(-not $fl.Count){[void]$lines.Add('No heuristic findings; not an endorsement of completeness.')}
  [void]$lines.Add('');[void]$lines.Add('Watchstander verification required. This is not the official record.')
  return ($lines.ToArray() -join "`n")
}
# Recurring potentially-open equipment across at least two logs (as engine.candidates).
function Get-EightBellsCandidates($Logs){
  $map=[ordered]@{}
  foreach($log in @($Logs)){
    foreach($o in @($log.analysis.open)){
      $k=([string]$o.equipment).ToLowerInvariant()
      if(-not $k -or $k -eq 'unattributed'){continue}
      if(-not $map.Contains($k)){$map[$k]=@{name=$o.equipment;logs=(New-Object System.Collections.ArrayList);evidence=(New-Object System.Collections.ArrayList)}}
      if(-not $map[$k].logs.Contains($log.id)){[void]$map[$k].logs.Add($log.id)}
      [void]$map[$k].evidence.Add([ordered]@{logId=$log.id;lines=[object[]]@($o.lines)})
    }
  }
  $out=New-Object System.Collections.ArrayList
  foreach($x in $map.Values){
    if($x.logs.Count -ge 2){[void]$out.Add([ordered]@{title='Recurring condition: '+$x.name;description='Similar potentially open conditions appear across '+$x.logs.Count+' logs. Validate identity, dates and maintenance history before approving a lesson.';evidence=$x.evidence.ToArray();status='candidate'})}
  }
  return $out.ToArray()
}
