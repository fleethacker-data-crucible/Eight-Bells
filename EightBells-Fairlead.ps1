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
# Tests replace this with { param($ProcessId) -> @{ ExecutablePath; ScriptPath } }.
function Get-EightBellsProcessPaths([int]$ProcessId){
  if($script:EightBellsProcessLookup){return (& $script:EightBellsProcessLookup $ProcessId)}
  $p=$null
  try{$p=Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = '+$ProcessId) -ErrorAction Stop}catch{$p=$null}
  if(-not $p){return @{ExecutablePath='';ScriptPath=''}}
  $file=''
  $m=[regex]::Match([string]$p.CommandLine,'(?i)(?:^|\s)[-/](?:file|f)\s+(?:"([^"]+)"|(\S+))')
  if($m.Success){if($m.Groups[1].Success){$file=$m.Groups[1].Value}else{$file=$m.Groups[2].Value}}
  return @{ExecutablePath=[string]$p.ExecutablePath;ScriptPath=$file}
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
    $tool=[string]$id.tool
    if($tool -cne 'fairlead'){
      $who='something else'
      if($tool -cmatch '\A[A-Za-z0-9._-]{1,40}\z'){$who='"'+$tool+'"'}
      return ('The program at 127.0.0.1:'+$port+' is '+$who+', not Fairlead, so the key was not sent.')
    }
    $idPid=0
    if(-not [int]::TryParse([string]$id.pid,[ref]$idPid) -or $idPid -ne $owner){
      return ('The program on port '+$port+' is not the one that answered the identity check, so the key was not sent.')
    }
    $reported=[string]$id.path
    if(-not $reported -or -not (Test-EightBellsProcessPath -ProcessId $owner -Path $reported)){
      return ('The program on port '+$port+' reported a path that is not the program holding the port, so the key was not sent.')
    }
    return $null
  }catch{
    return ('The program at 127.0.0.1:'+$port+' did not identify itself as Fairlead, so the key was not sent.')
  }finally{if($null -ne $resp){try{$resp.Close()}catch{}}}
}
