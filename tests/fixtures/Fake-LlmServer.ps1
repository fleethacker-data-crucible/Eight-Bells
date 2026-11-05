param([Parameter(Mandatory=$true)][int]$Port,[Parameter(Mandatory=$true)][string]$Record,[ValidateSet('ok','fail','empty','deny')][string]$Mode='ok',[string]$Reply='SYNTHETIC REPLY: Pump B vibration remains open (Line 1).')
# Fake OpenAI-compatible chat endpoint for tests. Binds loopback only, answers every POST, and appends one JSON line per
# request (path, Authorization and X-Fairlead-Privacy headers, parsed body) to -Record. Synthetic data only; no network.
$ErrorActionPreference='Stop'
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
$listener.Start()
function Send($stream,[int]$status,[string]$body){
  $nl=[string][char]13+[char]10
  $data=[Text.Encoding]::UTF8.GetBytes($body)
  $head='HTTP/1.1 '+$status+' X'+$nl+'Content-Type: application/json'+$nl+'Content-Length: '+$data.Length+$nl+'Connection: close'+$nl+$nl
  $h=[Text.Encoding]::ASCII.GetBytes($head)
  $stream.Write($h,0,$h.Length);$stream.Write($data,0,$data.Length);$stream.Flush()
}
try{
  while($true){
    $client=$listener.AcceptTcpClient()
    try{
      $client.ReceiveTimeout=10000
      $stream=$client.GetStream()
      $buf=New-Object 'System.Collections.Generic.List[byte]'
      while($true){
        $b=$stream.ReadByte();if($b -lt 0){break}
        $buf.Add([byte]$b);$c=$buf.Count
        if($c -ge 4 -and $buf[$c-4] -eq 13 -and $buf[$c-3] -eq 10 -and $buf[$c-2] -eq 13 -and $buf[$c-1] -eq 10){break}
      }
      if($buf.Count -eq 0){continue}
      $lines=([Text.Encoding]::ASCII.GetString($buf.ToArray()) -split '\r\n')
      $path=($lines[0] -split ' ')[1]
      $auth='';$privacy='';$len=0
      foreach($l in $lines){
        if($l -match '^authorization:\s*(.*)$'){$auth=$Matches[1]}
        if($l -match '^x-fairlead-privacy:\s*(.*)$'){$privacy=$Matches[1]}
        if($l -match '^content-length:\s*(\d+)$'){$len=[int]$Matches[1]}
      }
      $data=New-Object byte[] $len;$off=0
      while($off -lt $len){$n=$stream.Read($data,$off,$len-$off);if($n -le 0){break};$off+=$n}
      $body=[Text.Encoding]::UTF8.GetString($data)
      $entry=@{path=$path;auth=$auth;privacy=$privacy;body=($body|ConvertFrom-Json)}
      Add-Content -LiteralPath $Record -Value (ConvertTo-Json -InputObject $entry -Depth 20 -Compress) -Encoding UTF8
      if($Mode -eq 'fail'){Send $stream 500 '{"error":"synthetic upstream failure"}'}
      elseif($Mode -eq 'deny'){Send $stream 401 '{"error":"synthetic key refused"}'}
      elseif($Mode -eq 'empty'){Send $stream 200 '{"choices":[{"message":{"content":""}}]}'}
      else{Send $stream 200 (ConvertTo-Json -InputObject @{choices=@(@{message=@{role='assistant';content=$Reply}})} -Depth 6 -Compress)}
    }catch{}
    finally{$client.Close()}
  }
}finally{$listener.Stop()}
