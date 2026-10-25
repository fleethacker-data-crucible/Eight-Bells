# Dot-sourced helpers for the Eight Bells lifecycle: the browser-presence rule used by the server's
# auto-stop tick, and finding/stopping running Eight Bells servers (including ones started by an older
# LogHawk build). Used by Start-EightBells.ps1, Stop-EightBells.ps1 and tests/Smoke-Test.ps1. Windows PowerShell 5.1; keep this file ASCII.

# ---- browser presence (tab owns the server) ----
# $Tabs is a hashtable: tab id -> @{seen=[DateTime] UTC of last heartbeat; leaving=[DateTime] UTC of the
# pagehide beacon, or $null}. Every open tab heartbeats every 5 s with its own id, so a reload (new id) or a
# second tab keeps the server alive while the closed one ages out.

function Set-EightBellsPresence {
  param([hashtable]$Tabs,[string]$Tab,[bool]$Leaving,[DateTime]$Now)
  if([string]::IsNullOrEmpty($Tab) -or $Tab -notmatch '^[A-Za-z0-9_-]{1,64}$'){$Tab='default'}
  if(!$Tabs.ContainsKey($Tab)){
    if($Tabs.Count -ge 64){Remove-EightBellsGoneTabs -Tabs $Tabs -Now $Now}
    if($Tabs.Count -ge 64){return}
    $Tabs[$Tab]=@{seen=$Now;leaving=$null}
  }
  if($Leaving){$Tabs[$Tab].leaving=$Now}
  else{$Tabs[$Tab].seen=$Now;$Tabs[$Tab].leaving=$null}
}

function Test-EightBellsTabGone {
  param($Entry,[DateTime]$Now,[int]$TimeoutMs=20000,[int]$LeavingGraceMs=5000)
  if(($Now-[DateTime]$Entry.seen).TotalMilliseconds -ge $TimeoutMs){return $true}
  if($null -ne $Entry.leaving){return (($Now-[DateTime]$Entry.leaving).TotalMilliseconds -ge $LeavingGraceMs)}
  return $false
}

function Test-EightBellsBrowserGone {
  <#
  .SYNOPSIS
    True when every tab is gone and nothing is running, so the server should stop itself.
    A tab is gone 20 s after its last heartbeat, or 5 s after its leaving beacon with no newer heartbeat.
    Busy (a request such as a save or AI call still running) always means keep running.
    With no tab ever seen, it stops only after FirstContactMs (0 = never; used when no browser was opened).
  #>
  param([hashtable]$Tabs,[DateTime]$Now,[int]$Busy=0,[bool]$AutoStop=$true,[int]$TimeoutMs=20000,[int]$LeavingGraceMs=5000,[DateTime]$StartedAt=[DateTime]::MinValue,[int]$FirstContactMs=0)
  if(!$AutoStop -or $Busy -gt 0){return $false}
  if($null -eq $Tabs -or $Tabs.Count -eq 0){
    if($FirstContactMs -le 0 -or $StartedAt -eq [DateTime]::MinValue){return $false}
    return (($Now-$StartedAt).TotalMilliseconds -ge $FirstContactMs)
  }
  foreach($entry in $Tabs.Values){
    if(!(Test-EightBellsTabGone -Entry $entry -Now $Now -TimeoutMs $TimeoutMs -LeavingGraceMs $LeavingGraceMs)){return $false}
  }
  return $true
}

function Step-EightBellsPresenceAfterBusy {
  # The server answers one request at a time; after a long one (AI call, big import) it could not hear
  # heartbeats, so tabs that had not said they were leaving count as seen now.
  param([hashtable]$Tabs,[DateTime]$Now)
  foreach($entry in @($Tabs.Values)){if($null -eq $entry.leaving){$entry.seen=$Now}}
}

function Remove-EightBellsGoneTabs {
  # Drops closed tabs while another tab is still alive, so reloads do not grow the table.
  param([hashtable]$Tabs,[DateTime]$Now,[int]$TimeoutMs=20000,[int]$LeavingGraceMs=5000)
  foreach($key in @($Tabs.Keys)){
    if(Test-EightBellsTabGone -Entry $Tabs[$key] -Now $Now -TimeoutMs $TimeoutMs -LeavingGraceMs $LeavingGraceMs){$Tabs.Remove($key)}
  }
}

function Get-EightBellsAutoStopSetting {
  # EIGHTBELLS_AUTO_STOP is read first; the former LOGHAWK_AUTO_STOP name remains a fallback.
  if(![string]::IsNullOrEmpty($env:EIGHTBELLS_AUTO_STOP)){return $env:EIGHTBELLS_AUTO_STOP}
  return $env:LOGHAWK_AUTO_STOP
}

function Test-EightBellsAutoStopEnabled {
  # EIGHTBELLS_AUTO_STOP=0 (or false/off/no) turns auto-stop off. Eight Bells has no env/config file.
  param([string]$Value=(Get-EightBellsAutoStopSetting))
  if([string]::IsNullOrWhiteSpace($Value)){return $true}
  return ($Value.Trim() -notmatch '^(0|false|off|no)$')
}

# ---- runtime files and process discovery ----
# Each server writes <data dir>\logs\eightbells-server-<pid>.json (pid, port, url, startedAt; never the token).
# The data dir is %LOCALAPPDATA%\EightBells (or EightBells-LocalDev), where Eight Bells keeps its store and logs.
# Servers started by an older LogHawk build wrote loghawk-server-<pid>.json under %LOCALAPPDATA%\LogHawk
# (or LogHawk-LocalDev); those names and folders are still searched so such a server can be found and stopped.
$script:EightBellsRuntimePatterns=@('eightbells-server-*.json','loghawk-server-*.json')

function Get-EightBellsDataDirs {
  $dirs=@()
  if($env:LOCALAPPDATA){
    $dirs+=(Join-Path $env:LOCALAPPDATA 'EightBells')
    $dirs+=(Join-Path $env:LOCALAPPDATA 'EightBells-LocalDev')
    # Former LogHawk data dirs, where an instance started by an older build keeps its runtime file.
    $dirs+=(Join-Path $env:LOCALAPPDATA 'LogHawk')
    $dirs+=(Join-Path $env:LOCALAPPDATA 'LogHawk-LocalDev')
  }
  return $dirs
}

function Get-EightBellsRuntimePath {
  param([string]$DataDir,[int]$ProcessId)
  return (Join-Path (Join-Path $DataDir 'logs') ('eightbells-server-'+$ProcessId+'.json'))
}

function Get-EightBellsProcesses {
  <#
  .SYNOPSIS
    Running Eight Bells servers (Pid, Port, Url, Started, RuntimeFile) from the runtime files in each data
    dir (current eightbells-server-*.json and former loghawk-server-*.json), plus, unless -NoProcessScan,
    any PowerShell whose command line runs Start-EightBells.ps1 or the former Start-LogHawk.ps1.
    Runtime files whose pid is dead (or not PowerShell) are deleted on sight.
  #>
  param([string[]]$DataDir=(Get-EightBellsDataDirs),[switch]$NoProcessScan,[int[]]$Exclude=@())
  $found=@{}
  $skip=@($PID)+@($Exclude)
  foreach($dir in @($DataDir)){
    if(!$dir){continue}
    $logs=Join-Path $dir 'logs'
    if(!(Test-Path -LiteralPath $logs)){continue}
    $files=@();foreach($pattern in $script:EightBellsRuntimePatterns){$files+=@(Get-ChildItem -LiteralPath $logs -Filter $pattern -ErrorAction SilentlyContinue)}
    foreach($f in $files){
      try{
        $info=Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        $id=[int]$info.pid
        if($skip -contains $id){continue}
        $proc=Get-Process -Id $id -ErrorAction SilentlyContinue
        if($proc -and $proc.ProcessName -match '^(powershell|pwsh)$'){
          $found[$id]=[pscustomobject]@{Pid=$id;Port=$info.port;Url=[string]$info.url;Started=[string]$info.startedAt;RuntimeFile=$f.FullName}
        }else{
          Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        }
      }catch{Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue}
    }
  }
  if(!$NoProcessScan){
    try{
      $procs=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue)
      foreach($p in $procs){
        $id=[int]$p.ProcessId
        if($skip -contains $id -or $found.ContainsKey($id)){continue}
        if($p.CommandLine -and $p.CommandLine -match 'Start-(EightBells|LogHawk)\.ps1'){
          $found[$id]=[pscustomobject]@{Pid=$id;Port=$null;Url=$null;Started=[string]$p.CreationDate;RuntimeFile=$null}
        }
      }
    }catch{}
  }
  return @($found.Values | Sort-Object Pid)
}

function Format-EightBellsProcess {
  param($Process)
  if($Process.Url){return ($Process.Url+' (PID '+$Process.Pid+')')}
  return ('PID '+$Process.Pid)
}

function Stop-EightBellsProcesses {
  <#
  .SYNOPSIS
    Stops every running Eight Bells server (or older LogHawk server) found by Get-EightBellsProcesses, deletes its runtime file and
    returns what was stopped. Failures are reported as warnings, not thrown.
  #>
  param([string[]]$DataDir=(Get-EightBellsDataDirs),[switch]$NoProcessScan,[int[]]$Exclude=@())
  $stopped=@()
  foreach($p in @(Get-EightBellsProcesses -DataDir $DataDir -NoProcessScan:$NoProcessScan -Exclude $Exclude)){
    try{
      Stop-Process -Id $p.Pid -Force -ErrorAction Stop
      try{Wait-Process -Id $p.Pid -Timeout 5 -ErrorAction SilentlyContinue}catch{}
      $stopped+=$p
    }catch{
      if(Get-Process -Id $p.Pid -ErrorAction SilentlyContinue){Write-Warning ('Could not stop Eight Bells PID '+$p.Pid+': '+$_.Exception.Message);continue}
      $stopped+=$p
    }
    # A killed process skips its own cleanup, so remove its runtime file here.
    if($p.RuntimeFile){Remove-Item -LiteralPath $p.RuntimeFile -Force -ErrorAction SilentlyContinue}
    foreach($dir in @($DataDir)){
      if($dir){
        Remove-Item -LiteralPath (Get-EightBellsRuntimePath -DataDir $dir -ProcessId $p.Pid) -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path (Join-Path $dir 'logs') ('loghawk-server-'+$p.Pid+'.json')) -Force -ErrorAction SilentlyContinue
      }
    }
  }
  return $stopped
}
