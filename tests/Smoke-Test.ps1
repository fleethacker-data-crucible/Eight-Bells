param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$script=Join-Path $Root 'Start-LogHawk.ps1'
$token=$null
$process=$null
try {
 $port=0
 $tcp=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
 $tcp.Start();$port=([Net.IPEndPoint]$tcp.LocalEndpoint).Port;$tcp.Stop()
 $exe=(Get-Process -Id $PID).Path
 $process=Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-File',('"{0}"' -f $script),'-Port',$port,'-NoBrowser') -PassThru -WindowStyle Hidden
 $url="http://127.0.0.1:$port"
 $ready=$false
 for($i=0;$i -lt 40;$i++){Start-Sleep -Milliseconds 250;try{$r=Invoke-WebRequest -UseBasicParsing -Uri "$url/api/state" -TimeoutSec 2;if($r.StatusCode -eq 200){$ready=$true;break}}catch{}}
 if(!$ready){throw 'Service did not start'}
 $state=Invoke-RestMethod "$url/api/state"
 if($null -eq $state.logs){throw 'Missing logs'}
 $body=@{name='Synthetic QA';content="0800 Test alarm observed`n0830 Supervisor notified`n0900 Still pending"}|ConvertTo-Json
 $result=Invoke-RestMethod -Uri "$url/api/import" -Method Post -ContentType 'application/json' -Body $body
 if(@($result.entries).Count -lt 3){throw 'Import parser failed'}
 $state=Invoke-RestMethod "$url/api/state"
 if(@($state.logs).Count -lt 1){throw 'Persistence failed'}
 $page=Invoke-WebRequest -UseBasicParsing "$url/"
 if($page.Content -notmatch 'LOGHAWK'){throw 'UI not served'}
 Write-Host 'PASS: server, UI, import, persistence'
} finally {
 if($process -and !$process.HasExited){Stop-Process -Id $process.Id -Force}
}
