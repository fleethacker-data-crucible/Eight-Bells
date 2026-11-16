# Proves the process on the router port is Fairlead before Eight Bells sends its client key.
# Same check as SnapShackle and PacketRat: unauthenticated GET /__fleethacker/id (no proxy, no redirects),
# tool is fairlead, the reported pid owns the port, and the reported path is that process's executable or -File script.
# Any failure returns a sentence and the caller must not send the key. The sentence never contains a key.
# Tests may replace the TCP-table and process lookups; they never replace the id request.
$script:EightBellsPortOwnerSource=@'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class EightBellsPortOwner {
    [DllImport("iphlpapi.dll", SetLastError = true)]
    static extern uint GetExtendedTcpTable(IntPtr pTcpTable, ref int dwOutBufLen, bool sort, int ipVersion, int tableClass, uint reserved);
    const int TcpTableOwnerPidListener = 3;
    const uint ErrorInsufficientBuffer = 122;
    static int Port(int raw) { return ((raw & 0xFF) << 8) | ((raw >> 8) & 0xFF); }
    static bool Loopback(IntPtr row, int family) {
        if (family == 2) {
            byte first = Marshal.ReadByte(row, 4);
            return first == 127 || Marshal.ReadInt32(row, 4) == 0;
        }
        for (int i = 0; i < 15; i++) { if (Marshal.ReadByte(row, i) != 0) return false; }
        byte last = Marshal.ReadByte(row, 15);
        return last == 0 || last == 1;
    }
    static void Scan(int family, int rowSize, int portOffset, int pidOffset, int port, List<int> pids) {
        for (int attempt = 0; attempt < 4; attempt++) {
            int len = 0;
            GetExtendedTcpTable(IntPtr.Zero, ref len, false, family, TcpTableOwnerPidListener, 0);
            if (len <= 0) throw new InvalidOperationException("GetExtendedTcpTable gave no table size.");
            len += 4096;
            IntPtr buf = Marshal.AllocHGlobal(len);
            try {
                uint rc = GetExtendedTcpTable(buf, ref len, false, family, TcpTableOwnerPidListener, 0);
                if (rc == ErrorInsufficientBuffer) continue;
                if (rc != 0) throw new InvalidOperationException("GetExtendedTcpTable failed with error " + rc + ".");
                int n = Marshal.ReadInt32(buf);
                for (int i = 0; i < n; i++) {
                    IntPtr row = new IntPtr(buf.ToInt64() + 4 + (long)i * rowSize);
                    if (Port(Marshal.ReadInt32(row, portOffset)) != port) continue;
                    if (!Loopback(row, family)) continue;
                    int pid = Marshal.ReadInt32(row, pidOffset);
                    if (!pids.Contains(pid)) pids.Add(pid);
                }
                return;
            } finally { Marshal.FreeHGlobal(buf); }
        }
        throw new InvalidOperationException("The TCP table kept changing while it was read.");
    }
    public static int[] GetListenerPids(int port) {
        List<int> pids = new List<int>();
        Scan(2, 24, 8, 20, port, pids);
        Scan(23, 56, 20, 52, port, pids);
        return pids.ToArray();
    }
}
'@
# $null when this process can tell who listens, else a sentence and the key is not sent. Compiled once.
function Initialize-EightBellsPortCheck{
  if('EightBellsPortOwner' -as [type]){return $null}
  if($script:EightBellsPortCheckProblem){return [string]$script:EightBellsPortCheckProblem}
  $problem=$null
  if([Environment]::OSVersion.Platform -ne 'Win32NT'){
    $problem='Eight Bells can check which program holds the router port only on Windows, so the key was not sent.'
  }else{
    try{Add-Type -TypeDefinition $script:EightBellsPortOwnerSource -Language CSharp -ErrorAction Stop}
    catch{$problem='Windows did not let Eight Bells compile its port check, so the key was not sent.'}
  }
  if($problem){$script:EightBellsPortCheckProblem=$problem}
  return $problem
}
# Tests replace this with { param($Port) -> int[] }. The real one reads the TCP table.
function Get-EightBellsListenerPids([int]$Port){
  if($script:EightBellsListenerLookup){return @(& $script:EightBellsListenerLookup $Port)}
  return @([EightBellsPortOwner]::GetListenerPids($Port))
}
# The -File / -f script on a PowerShell command line, or '' when there is none. Never a substring of a longer path.
function Get-EightBellsScriptPathFromCommandLine([string]$CommandLine){
  if(-not $CommandLine){return ''}
  $m=[regex]::Match($CommandLine,'(?i)(?:^|\s)[-/](?:file|f)\s+(?:"([^"]+)"|(\S+))')
  if(-not $m.Success){return ''}
  if($m.Groups[1].Success){return $m.Groups[1].Value}
  return $m.Groups[2].Value
}
# Tests replace this with { param($ProcessId) -> @{ ExecutablePath; ScriptPath } }.
function Get-EightBellsProcessPaths([int]$ProcessId){
  if($script:EightBellsProcessLookup){return (& $script:EightBellsProcessLookup $ProcessId)}
  $p=$null
  try{$p=Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = '+$ProcessId) -ErrorAction Stop}catch{$p=$null}
  if(-not $p){return @{ExecutablePath='';ScriptPath=''}}
  return @{ExecutablePath=[string]$p.ExecutablePath;ScriptPath=(Get-EightBellsScriptPathFromCommandLine ([string]$p.CommandLine))}
}
# An absolute Windows path, normalized, or '' when it is not one. Never a bare name.
function ConvertTo-EightBellsNormalPath([string]$Path){
  if(-not $Path){return ''}
  $p=$Path.Trim().Trim('"').Replace('/','\')
  if($p -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\?.]+\\[^\\]+)'){return ''}
  if([Environment]::OSVersion.Platform -eq 'Win32NT'){
    try{return [IO.Path]::GetFullPath($p).TrimEnd('\')}catch{return ''}
  }
  return $p.TrimEnd('\')
}
# $true only when the id path is exactly that process's executable or -File script. Never a substring.
function Test-EightBellsProcessPath([int]$ProcessId,[string]$Path){
  $want=ConvertTo-EightBellsNormalPath $Path
  if(-not $want){return $false}
  $paths=Get-EightBellsProcessPaths -ProcessId $ProcessId
  foreach($candidate in @($paths.ExecutablePath,$paths.ScriptPath)){
    $c=ConvertTo-EightBellsNormalPath $candidate
    if($c -and [string]::Equals($c,$want,[StringComparison]::OrdinalIgnoreCase)){return $true}
  }
  return $false
}
# $null when the address is Fairlead, else a sentence. The request carries no key, no proxy and no redirect.
function Test-EightBellsFairleadIdentity([string]$Url){
  $u=$null
  if(![Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$u)){return 'The router address is not a URL, so the key was not sent.'}
  $port=$u.Port
  $notFairlead='Something other than Fairlead is answering on port '+$port+', so the key was not sent.'
  if(-not $script:EightBellsListenerLookup){
    $problem=Initialize-EightBellsPortCheck
    if($problem){return $problem}
  }
  try{$pids=@(Get-EightBellsListenerPids -Port $port|Where-Object {$null -ne $_})}
  catch{return ('Eight Bells could not read which program listens on port '+$port+', so the key was not sent.')}
  if($pids.Count -eq 0){return ('Fairlead is not running at '+$Url+', so the key was not sent.')}
  if($pids.Count -gt 1){return $notFairlead}
  $owner=0
  if(-not [int]::TryParse([string]$pids[0],[ref]$owner)){return $notFairlead}
  # Always the literal loopback address, so a name in the router URL cannot move this request.
  $req=[Net.HttpWebRequest]::Create('http://127.0.0.1:'+$port+'/__fleethacker/id')
  $req.Method='GET';$req.Timeout=3000;$req.ReadWriteTimeout=3000;$req.Proxy=$null
  $req.AllowAutoRedirect=$false;$req.Accept='application/json';$req.UserAgent='EightBells';$req.KeepAlive=$false
  try{$req.ServicePoint.Expect100Continue=$false}catch{}
  $resp=$null
  try{
    try{$resp=$req.GetResponse()}catch [Net.WebException]{
      if($null -ne $_.Exception.Response){try{$_.Exception.Response.Close()}catch{}}
      return ('The program at 127.0.0.1:'+$port+' did not identify itself as Fairlead, so the key was not sent.')
    }
    if([int]$resp.StatusCode -ne 200){return ('The program at 127.0.0.1:'+$port+' did not identify itself as Fairlead, so the key was not sent.')}
    $reader=New-Object IO.StreamReader($resp.GetResponseStream(),[Text.Encoding]::UTF8)
    try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
    if($text.Length -gt 4096){return $notFairlead}
    $id=$null
    try{$id=$text.TrimStart([char]0xFEFF).Trim()|ConvertFrom-Json}catch{return $notFairlead}
    $names=@($id.PSObject.Properties.Name)
    $tool=if($names -contains 'tool'){[string]$id.tool}else{''}
    if($tool -cne 'fairlead'){
      $who='something else'
      if($tool -cmatch '\A[A-Za-z0-9._-]{1,40}\z'){$who='"'+$tool+'"'}
      return ('The program at 127.0.0.1:'+$port+' is '+$who+', not Fairlead, so the key was not sent.')
    }
    $idPid=0
    $pidText=if($names -contains 'pid'){[string]$id.pid}else{''}
    if(-not [int]::TryParse($pidText,[ref]$idPid) -or $idPid -ne $owner){
      return ('The program on port '+$port+' is not the one that answered the identity check, so the key was not sent.')
    }
    $reported=if($names -contains 'path'){[string]$id.path}else{''}
    if(-not $reported -or -not (Test-EightBellsProcessPath -ProcessId $owner -Path $reported)){
      return ('The program on port '+$port+' reported a path that is not the program holding the port, so the key was not sent.')
    }
    return $null
  }catch{
    return ('The program at 127.0.0.1:'+$port+' did not identify itself as Fairlead, so the key was not sent.')
  }finally{if($null -ne $resp){try{$resp.Close()}catch{}}}
}
# Why a Fairlead HTTP status is not a usable answer. 3xx is a failure: the request is not followed, so the key stays on the first host.
function Get-EightBellsRouterFailure([int]$Status,[string]$What){
  if($Status -ge 300 -and $Status -lt 400){return 'Fairlead redirected the request, so it was not followed.'}
  if($Status -in 401,403){return 'Fairlead refused the request. In Fairlead open Clients, choose Install for this app and name it EightBells, or start Fairlead once so this account''s local token exists, then try again.'}
  if($Status -eq 0){return 'Fairlead did not answer on this PC. Start Fairlead, then try again.'}
  return $What+' failed through Fairlead (HTTP '+$Status+'). Check the Fairlead request log.'
}
# Identity check first. The key is attached only when that returns nothing. No proxy and no redirect.
# Get-EightBellsFairleadHeaders is defined by the server and is not called when the check fails.
function Invoke-EightBellsRouterRequest([string]$Url,[byte[]]$Body,[string]$ContentType,[bool]$Local,[int]$MaxBytes){
  $why=Test-EightBellsFairleadIdentity -Url $script:routerUrl
  if($why){return @{ok=$false;status=0;bytes=(New-Object byte[] 0);contentType='';message=$why}}
  $posted=Invoke-EightBellsFairleadPost $Url $Body $ContentType (Get-EightBellsFairleadHeaders $Local) $MaxBytes
  $msg=''
  if($posted.status -ne 200){$msg=Get-EightBellsRouterFailure $posted.status 'The request'}
  return @{ok=($posted.status -eq 200);status=$posted.status;bytes=$posted.bytes;contentType=[string]$posted.contentType;message=$msg}
}
# One POST to a loopback Fairlead route. The body is not logged. status 0 means Fairlead did not answer.
# Proxy is off and redirects are not followed, so a 3xx cannot carry the key anywhere else.
function Invoke-EightBellsFairleadPost([string]$Url,[byte[]]$Body,[string]$ContentType,[hashtable]$Headers,[int]$MaxBytes){
  $request=[Net.HttpWebRequest]::Create($Url)
  $request.Method='POST'
  $request.ContentType=$ContentType
  $request.Proxy=$null
  $request.AllowAutoRedirect=$false
  $request.Timeout=90000
  $request.ReadWriteTimeout=90000
  $request.KeepAlive=$false
  try{$request.ServicePoint.Expect100Continue=$false}catch{}
  foreach($name in @($Headers.Keys)){
    if($name -eq 'Authorization'){$request.Headers[[Net.HttpRequestHeader]::Authorization]=[string]$Headers[$name]}
    else{$request.Headers.Add($name,[string]$Headers[$name])}
  }
  $request.ContentLength=$Body.Length
  $response=$null
  try{
    $out=$request.GetRequestStream()
    try{$out.Write($Body,0,$Body.Length)}finally{$out.Close()}
    $response=$request.GetResponse()
  }catch{
    $ex=$_.Exception
    while($ex -and -not ($ex -is [Net.WebException])){$ex=$ex.InnerException}
    if($ex -and $ex.Response){$response=$ex.Response}else{return @{status=0;contentType='';bytes=New-Object byte[] 0}}
  }
  try{
    $status=[int]$response.StatusCode
    $ctype=[string]$response.ContentType
    $ms=New-Object IO.MemoryStream
    $src=$response.GetResponseStream()
    if(-not $src){return @{status=$status;contentType=$ctype;bytes=New-Object byte[] 0}}
    $buf=New-Object byte[] 8192
    while(($n=$src.Read($buf,0,$buf.Length)) -gt 0){
      if(($ms.Length+$n) -gt $MaxBytes){throw 'Fairlead sent more than expected.'}
      $ms.Write($buf,0,$n)
    }
    return @{status=$status;contentType=$ctype;bytes=$ms.ToArray()}
  }finally{if($response){$response.Close()}}
}
