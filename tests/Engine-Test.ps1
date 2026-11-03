param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# Holds the PowerShell engine port (EightBells-Engine.ps1) to tests/golden/engine.golden.json, which is produced by web/engine.js.
$ErrorActionPreference='Stop'
. (Join-Path $Root 'EightBells-Engine.ps1')
$golden=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'golden\engine.golden.json'),(New-Object Text.UTF8Encoding($false)))|ConvertFrom-Json
function Compare-Deep($expected,$actual,[string]$path){
  if($null -eq $expected){if($null -ne $actual){throw ($path+': expected null but got '+$actual)};return}
  if($expected -is [System.Array] -or ($actual -is [System.Array] -and $expected -isnot [string])){
    $e=@($expected);$a=@($actual)
    if($e.Count -ne $a.Count){throw ($path+': expected '+$e.Count+' items but got '+$a.Count)}
    for($i=0;$i -lt $e.Count;$i++){Compare-Deep $e[$i] $a[$i] ($path+'['+$i+']')}
    return
  }
  if($expected -is [System.Management.Automation.PSCustomObject]){
    foreach($p in $expected.PSObject.Properties){
      # No "$v=if(...)": an empty array assigned through an if-expression unrolls to $null.
      if($actual -is [System.Collections.IDictionary]){$v=$actual[$p.Name]}else{$v=$actual.($p.Name)}
      Compare-Deep $p.Value $v ($path+'.'+$p.Name)
    }
    return
  }
  if($expected -is [bool]){if($actual -isnot [bool] -or $actual -ne $expected){throw ($path+': expected '+$expected+' but got '+$actual)};return}
  if($expected -is [string]){if([string]$actual -cne $expected){throw ($path+": expected '"+$expected+"' but got '"+$actual+"'")};return}
  if([double]$expected -ne [double]$actual){throw ($path+': expected '+$expected+' but got '+$actual)}
}
$count=0
foreach($case in $golden.cases){
  $content=if($null -ne $case.content){[string]$case.content}else{[IO.File]::ReadAllText((Join-Path $Root ('samples\'+$case.file)),(New-Object Text.UTF8Encoding($false)))}
  try{
    $parsed=Invoke-EightBellsParse $content $case.format
    $analysis=Invoke-EightBellsAnalyze $parsed.entries ([double]$case.intervalMinutes)
    $log=@{id='golden-'+$case.name;name=$case.name;imported='2026-10-30T00:00:00Z';entries=$parsed.entries;analysis=$analysis}
    $actual=[ordered]@{format=$parsed.format;entries=$parsed.entries;analysis=$analysis;turnover=(Get-EightBellsTurnover $log)}
    Compare-Deep $case.expect $actual $case.name
  }catch{throw ('FAIL parity: '+$_.Exception.Message)}
  $count++
}
foreach($set in $golden.candidates){
  $logs=@()
  foreach($pair in $set.logs){
    $file=$pair[0];$id=$pair[1]
    $content=[IO.File]::ReadAllText((Join-Path $Root ('samples\'+$file)),(New-Object Text.UTF8Encoding($false)))
    $p=Invoke-EightBellsParse $content 'auto'
    $logs+=@(@{id=$id;entries=$p.entries;analysis=(Invoke-EightBellsAnalyze $p.entries)})
  }
  try{Compare-Deep $set.expect @(Get-EightBellsCandidates $logs) ('candidates: '+$set.name)}catch{throw ('FAIL parity: '+$_.Exception.Message)}
}
# Engine errors match too.
foreach($bad in @(@('{bad','json'),@('"unclosed',  'csv'),@('x','nonsense'))){
  $threw=$false;try{Invoke-EightBellsParse $bad[0] $bad[1]|Out-Null}catch{$threw=$true}
  if(-not $threw){throw ('FAIL parity: parse of '+$bad[0]+' as '+$bad[1]+' should have thrown')}
}
Write-Host ('PASS: PowerShell engine port matches the JavaScript engine ('+$count+' cases, '+@($golden.candidates).Count+' candidate sets, error cases)')
