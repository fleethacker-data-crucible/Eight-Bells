#requires -Version 5.1
# Refusals before Eight Bells sends the Fairlead client key.
# Run with tests/FairleadIdentity-Test.ps1 (Pester 5). No real credential, no real Fairlead, no key printed.
# A hit records authClass '' , 'synthetic', or 'present'. The fixture value itself is not stored on the hit.
# Helpers live in BeforeAll so Pester 5 defines them for the run, not only for discovery.
BeforeAll {
$ErrorActionPreference = 'Stop'

$script:EightBellsHeaderCalls = 0
# Fixture only. The probe classifies a matching Authorization header as 'synthetic' and does not keep the text.
$script:EightBellsSyntheticMarker = 'Bearer synthetic-fairlead-key-1'
function Get-EightBellsFairleadHeaders([bool]$Local) {
    $script:EightBellsHeaderCalls++
    $h = @{ 'X-Fairlead-Label' = 'EightBells'; Authorization = $script:EightBellsSyntheticMarker }
    if ($Local) { $h['X-Fairlead-Privacy'] = 'local' }
    return $h
}

$root = Split-Path $PSScriptRoot -Parent
if (-not $root) { $root = (Resolve-Path '.').Path }
. (Join-Path $root 'EightBells-Fairlead.ps1')

$script:EightBellsProbeSource = @'
$ErrorActionPreference = 'Stop'
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$Shared.Port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
$Shared.Ready = $true
function Send-ProbeResponse($Stream, [int]$Status, [string]$Reason, [string]$Extra, [string]$BodyText) {
    $nl = [string][char]13 + [char]10
    $data = [Text.Encoding]::UTF8.GetBytes($BodyText)
    $head = 'HTTP/1.1 ' + $Status + ' ' + $Reason + $nl + $Extra + 'Content-Length: ' + $data.Length + $nl + 'Connection: close' + $nl + $nl
    $bytes = [Text.Encoding]::ASCII.GetBytes($head)
    $Stream.Write($bytes, 0, $bytes.Length)
    if ($data.Length -gt 0) { $Stream.Write($data, 0, $data.Length) }
    $Stream.Flush()
}
try {
    while (-not $Shared.Stop) {
        if (-not $listener.Pending()) { Start-Sleep -Milliseconds 20; continue }
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 3000
            $client.SendTimeout = 3000
            $stream = $client.GetStream()
            $buf = New-Object 'System.Collections.Generic.List[byte]'
            while ($buf.Count -lt 16384) {
                $b = $stream.ReadByte()
                if ($b -lt 0) { break }
                $buf.Add([byte]$b)
                $c = $buf.Count
                if ($c -ge 4 -and $buf[$c - 4] -eq 13 -and $buf[$c - 3] -eq 10 -and $buf[$c - 2] -eq 13 -and $buf[$c - 1] -eq 10) { break }
            }
            if ($buf.Count -eq 0) { continue }
            $lines = ([Text.Encoding]::ASCII.GetString($buf.ToArray()) -split "`r`n")
            $parts = $lines[0].Split(' ')
            $method = $parts[0]
            $path = $parts[1]
            $auth = ''
            $len = 0
            foreach ($line in $lines) {
                if ($line -match '^(?i)authorization:\s*(.*)$') { $auth = $Matches[1] }
                if ($line -match '^(?i)content-length:\s*(\d+)$') { $len = [int]$Matches[1] }
            }
            $left = $len
            $scratch = New-Object byte[] 2048
            while ($left -gt 0) {
                $take = $scratch.Length
                if ($take -gt $left) { $take = $left }
                $n = $stream.Read($scratch, 0, $take)
                if ($n -le 0) { break }
                $left -= $n
            }
            $authClass = ''
            $marker = [string]$Shared.Marker
            if ($marker -and $auth -eq $marker) { $authClass = 'synthetic' }
            elseif ($auth) { $authClass = 'present' }
            $hit = New-Object psobject -Property @{ method = $method; path = $path; authClass = $authClass }
            [void]$Shared.Hits.Add($hit)
            if ([string]$Shared.Mode -eq 'sink') {
                Send-ProbeResponse $stream 204 'No Content' '' ''
                continue
            }
            $redirect = 'Location: http://127.0.0.1:' + [int]$Shared.RedirectPort + '/stolen' + [string][char]13 + [char]10
            if ($path -eq '/__fleethacker/id') {
                $idStatus = [int]$Shared.IdStatus
                if ($idStatus -ge 300 -and $idStatus -lt 400) {
                    Send-ProbeResponse $stream $idStatus 'Redirect' $redirect ''
                } else {
                    $doc = @{ tool = [string]$Shared.Tool; version = 'test'; pid = [int]$Shared.IdPid }
                    if (-not $Shared.OmitPath) { $doc.path = [string]$Shared.IdPath }
                    $json = ConvertTo-Json -InputObject $doc -Compress
                    Send-ProbeResponse $stream 200 'OK' ('Content-Type: application/json' + [string][char]13 + [char]10) $json
                }
            } else {
                $postStatus = [int]$Shared.PostStatus
                if ($postStatus -ge 300 -and $postStatus -lt 400) {
                    Send-ProbeResponse $stream $postStatus 'Redirect' $redirect ''
                } else {
                    $json = '{"choices":[{"message":{"content":"synthetic ok"}}]}'
                    Send-ProbeResponse $stream 200 'OK' ('Content-Type: application/json' + [string][char]13 + [char]10) $json
                }
            }
        } catch { }
        finally { $client.Close() }
    }
} finally { $listener.Stop() }
'@

function Reset-EightBellsIdentityHooks {
    $script:EightBellsListenerLookup = $null
    $script:EightBellsProcessLookup = $null
    $script:EightBellsHeaderCalls = 0
    $script:routerUrl = $null
    $script:EightBellsOwnerPid = 4242
    $script:EightBellsOwnerExe = 'C:\Fairlead\Fairlead.exe'
    $script:EightBellsOwnerScript = ''
}

function Set-FairleadOwner([int]$ProcessId, [string]$Exe, [string]$ScriptPath) {
    $script:EightBellsOwnerPid = $ProcessId
    $script:EightBellsOwnerExe = $Exe
    $script:EightBellsOwnerScript = $ScriptPath
    $script:EightBellsListenerLookup = { param($Port) return @($script:EightBellsOwnerPid) }
    $script:EightBellsProcessLookup = {
        param($ProcessId)
        return @{ ExecutablePath = $script:EightBellsOwnerExe; ScriptPath = $script:EightBellsOwnerScript }
    }
}

function New-EightBellsProbe([hashtable]$Options) {
    $hits = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    $shared = [hashtable]::Synchronized(@{
        Ready = $false
        Stop = $false
        Port = 0
        Hits = $hits
        Mode = [string]$Options.Mode
        Tool = [string]$Options.Tool
        IdPid = [int]$Options.IdPid
        IdPath = [string]$Options.IdPath
        OmitPath = [bool]$Options.OmitPath
        IdStatus = [int]$Options.IdStatus
        PostStatus = [int]$Options.PostStatus
        RedirectPort = [int]$Options.RedirectPort
        Marker = [string]$script:EightBellsSyntheticMarker
    })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Shared', $shared)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:EightBellsProbeSource)
    $handle = $ps.BeginInvoke()
    $probe = @{ Shared = $shared; PowerShell = $ps; Runspace = $rs; Handle = $handle; Port = 0 }
    for ($i = 0; $i -lt 50; $i++) {
        if ($shared.Ready) { $probe.Port = [int]$shared.Port; return $probe }
        if ($ps.InvocationStateInfo.State -eq 'Failed') { break }
        Start-Sleep -Milliseconds 20
    }
    $err = ($ps.Streams.Error | ForEach-Object { $_.Exception.Message }) -join ' '
    Stop-EightBellsProbe $probe
    throw ('The test listener did not start. ' + $err)
}

function Stop-EightBellsProbe($Probe) {
    if (-not $Probe) { return }
    try { $Probe.Shared.Stop = $true } catch { }
    try {
        if ($Probe.Handle -and $Probe.PowerShell) { $null = $Probe.PowerShell.EndInvoke($Probe.Handle) }
    } catch { }
    try { if ($Probe.PowerShell) { $Probe.PowerShell.Dispose() } } catch { }
    try { if ($Probe.Runspace) { $Probe.Runspace.Close(); $Probe.Runspace.Dispose() } } catch { }
}

function Get-ProbeHits($Probe) {
    # Index the list. Piping a synchronized list enumerates each object's properties instead of the objects.
    $raw = $Probe.Shared.Hits
    $n = 0
    if ($null -ne $raw) { $n = [int]$raw.Count }
    $out = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $n; $i++) {
        $hit = $raw[$i]
        [void]$out.Add([pscustomobject]@{
            method = [string]$hit.method
            path = [string]$hit.path
            authClass = [string]$hit.authClass
        })
    }
    return ,$out.ToArray()
}

function New-FairleadProbe([hashtable]$Extra) {
    $opt = @{
        Mode = 'fairlead'
        Tool = 'fairlead'
        IdPid = 4242
        IdPath = 'C:\Fairlead\Fairlead.exe'
        OmitPath = $false
        IdStatus = 200
        PostStatus = 200
        RedirectPort = 9
    }
    if ($Extra) { foreach ($k in @($Extra.Keys)) { $opt[$k] = $Extra[$k] } }
    $probe = New-EightBellsProbe $opt
    $script:OpenProbes += $probe
    return $probe
}

function Invoke-ProbeRequest($Probe, [string]$Kind) {
    $url = 'http://127.0.0.1:' + $Probe.Port + '/v1/chat/completions'
    $script:routerUrl = $url
    $json = '{"model":"auto"}'
    if ($Kind -eq 'vision') { $json = '{"model":"auto","messages":[{"role":"user","content":[{"type":"text","text":"synthetic image"}]}]}' }
    $body = [Text.Encoding]::UTF8.GetBytes($json)
    return Invoke-EightBellsRouterRequest -Url $url -Body $body -ContentType 'application/json' -Local $true -MaxBytes 100000
}

function Assert-NoKeySent($Result, $Hits, [string]$Pattern) {
    $Result.ok | Should -BeFalse
    [string]$Result.message | Should -Match $Pattern
    [string]$Result.message | Should -Not -Match 'synthetic-fairlead-key'
    $script:EightBellsHeaderCalls | Should -Be 0
    foreach ($hit in @($Hits)) {
        if (-not $hit) { continue }
        [string]$hit.authClass | Should -Be ''
    }
}
}

Describe 'Fairlead identity refusals' {
    BeforeEach {
        Reset-EightBellsIdentityHooks
        $script:OpenProbes = @()
    }
    AfterEach {
        foreach ($p in @($script:OpenProbes)) { Stop-EightBellsProbe $p }
        $script:OpenProbes = @()
        Reset-EightBellsIdentityHooks
    }

    It 'accepts a fairlead id whose pid owns the port and whose path is that process' {
        Get-EightBellsScriptPathFromCommandLine 'powershell.exe -NoProfile -File C:\Fairlead\scripts\Start-Fairlead.ps1 --no-browser' | Should -Be 'C:\Fairlead\scripts\Start-Fairlead.ps1'
        Get-EightBellsScriptPathFromCommandLine 'powershell.exe -NoProfile -File "C:\Fairlead\scripts\Start Fairlead.ps1"' | Should -Be 'C:\Fairlead\scripts\Start Fairlead.ps1'
        Get-EightBellsScriptPathFromCommandLine 'powershell.exe -Command C:\Fairlead\scripts\Start-Fairlead.ps1' | Should -Be ''
        Set-FairleadOwner 40 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' 'C:\Fairlead\scripts\Start-Fairlead.ps1'
        Test-EightBellsProcessPath -ProcessId 40 -Path 'C:\Fairlead\scripts\Start-Fairlead.ps1' | Should -BeTrue
        Set-FairleadOwner 40 'C:\Fairlead\Fairlead.exe' ''
        Test-EightBellsProcessPath -ProcessId 40 -Path 'C:\Fairlead\Fairlead.exe' | Should -BeTrue
        Test-EightBellsProcessPath -ProcessId 40 -Path 'C:\Fairlead\Fairlead.exe.evil' | Should -BeFalse
        Set-FairleadOwner 40 'C:\Fairlead\Fairlead.exe.evil' ''
        Test-EightBellsProcessPath -ProcessId 40 -Path 'C:\Fairlead\Fairlead.exe' | Should -BeFalse
        Test-EightBellsProcessPath -ProcessId 40 -Path 'Fairlead.exe' | Should -BeFalse
    }

    It 'sends the key only after the identity check passes, and the identity request carries none' {
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe' ''
        $probe = New-FairleadProbe @{}
        $result = Invoke-ProbeRequest $probe 'chat'
        $result.ok | Should -BeTrue
        $script:EightBellsHeaderCalls | Should -Be 1
        # Assign the array. Wrapping the call in @() counts an empty array as one item.
        $hits = Get-ProbeHits $probe
        $id = @($hits | Where-Object { $_.path -eq '/__fleethacker/id' })
        $post = @($hits | Where-Object { $_.path -eq '/v1/chat/completions' })
        $id.Count | Should -Be 1
        $id[0].authClass | Should -Be ''
        $post.Count | Should -Be 1
        $post[0].authClass | Should -Be 'synthetic'
    }

    It 'does not send the key when the listener is not fairlead' {
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe' ''
        $probe = New-FairleadProbe @{ Tool = 'talkforge' }
        $result = Invoke-ProbeRequest $probe 'chat'
        Assert-NoKeySent $result (Get-ProbeHits $probe) 'not Fairlead'
        @((Get-ProbeHits $probe) | Where-Object { $_.path -eq '/v1/chat/completions' }).Count | Should -Be 0
    }

    It 'does not send the key when the tool name is not exactly fairlead' {
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe' ''
        $probe = New-FairleadProbe @{ Tool = 'Fairlead' }
        $result = Invoke-ProbeRequest $probe 'chat'
        Assert-NoKeySent $result (Get-ProbeHits $probe) 'not Fairlead'
    }

    It 'does not send the key when the reported pid does not own the port' {
        Set-FairleadOwner 7 'C:\Fairlead\Fairlead.exe' ''
        $probe = New-FairleadProbe @{ IdPid = 4242 }
        $result = Invoke-ProbeRequest $probe 'chat'
        Assert-NoKeySent $result (Get-ProbeHits $probe) 'not the one that answered'
    }

    It 'does not send the key when more than one process owns the port' {
        $script:EightBellsListenerLookup = { param($Port) return @(4242, 7) }
        $probe = New-FairleadProbe @{}
        $result = Invoke-ProbeRequest $probe 'chat'
        $hits = Get-ProbeHits $probe
        Assert-NoKeySent $result (,$hits) 'Something other than Fairlead'
        $hits.Count | Should -Be 0
    }

    It 'does not send the key when nothing is listening' {
        $script:EightBellsListenerLookup = { param($Port) return @() }
        $probe = New-FairleadProbe @{}
        $result = Invoke-ProbeRequest $probe 'chat'
        $hits = Get-ProbeHits $probe
        Assert-NoKeySent $result (,$hits) 'not running'
        $hits.Count | Should -Be 0
    }

    It 'does not send the key when the reported path is not the process holding the port' {
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe' ''
        $probe = New-FairleadProbe @{ IdPath = 'C:\Other\not-fairlead.exe' }
        $result = Invoke-ProbeRequest $probe 'chat'
        Assert-NoKeySent $result (Get-ProbeHits $probe) 'reported a path'
    }

    It 'does not treat a path that merely contains the real path as a match' {
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe' ''
        $probe = New-FairleadProbe @{ IdPath = 'C:\Fairlead\Fairlead.exe.evil' }
        $result = Invoke-ProbeRequest $probe 'chat'
        Assert-NoKeySent $result (Get-ProbeHits $probe) 'reported a path'
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe.evil' ''
        $probe2 = New-FairleadProbe @{ IdPath = 'C:\Fairlead\Fairlead.exe' }
        $result2 = Invoke-ProbeRequest $probe2 'chat'
        Assert-NoKeySent $result2 (Get-ProbeHits $probe2) 'reported a path'
    }

    It 'does not send the key when the identity response has no path' {
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe' ''
        $probe = New-FairleadProbe @{ OmitPath = $true }
        $result = Invoke-ProbeRequest $probe 'chat'
        Assert-NoKeySent $result (Get-ProbeHits $probe) 'reported a path'
    }

    It 'does not follow an identity redirect and does not send the key' {
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe' ''
        $sink = New-FairleadProbe @{ Mode = 'sink' }
        $probe = New-FairleadProbe @{ IdStatus = 302; RedirectPort = $sink.Port }
        $result = Invoke-ProbeRequest $probe 'chat'
        $hits = Get-ProbeHits $probe
        Assert-NoKeySent $result (,$hits) 'did not identify'
        (Get-ProbeHits $sink).Count | Should -Be 0
    }

    It 'still reaches Fairlead when a proxy is configured, and the proxy sees no request' {
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe' ''
        $sink = New-FairleadProbe @{ Mode = 'sink' }
        $probe = New-FairleadProbe @{}
        $old = [Net.WebRequest]::DefaultWebProxy
        try {
            [Net.WebRequest]::DefaultWebProxy = New-Object Net.WebProxy(('http://127.0.0.1:' + $sink.Port), $false)
            $result = Invoke-ProbeRequest $probe 'chat'
        } finally {
            [Net.WebRequest]::DefaultWebProxy = $old
        }
        $result.ok | Should -BeTrue
        (Get-ProbeHits $sink).Count | Should -Be 0
        $hits = Get-ProbeHits $probe
        @($hits | Where-Object { $_.path -eq '/__fleethacker/id' -and $_.authClass -eq '' }).Count | Should -Be 1
        @($hits | Where-Object { $_.path -eq '/v1/chat/completions' -and $_.authClass -eq 'synthetic' }).Count | Should -Be 1
    }
}

Describe 'Fairlead chat and vision redirect refusals' {
    BeforeEach {
        Reset-EightBellsIdentityHooks
        $script:OpenProbes = @()
        Set-FairleadOwner 4242 'C:\Fairlead\Fairlead.exe' ''
    }
    AfterEach {
        foreach ($p in @($script:OpenProbes)) { Stop-EightBellsProbe $p }
        $script:OpenProbes = @()
        Reset-EightBellsIdentityHooks
    }

    It 'treats every 3xx status as a failure and does not describe it as success' {
        foreach ($status in @(300, 301, 302, 303, 307, 308, 399)) {
            (Get-EightBellsRouterFailure -Status $status -What 'Chat') | Should -Be 'Fairlead redirected the request, so it was not followed.'
        }
        (Get-EightBellsRouterFailure -Status 401 -What 'Chat') | Should -Match 'Install for this app'
        (Get-EightBellsRouterFailure -Status 0 -What 'Chat') | Should -Match 'did not answer'
    }

    It 'does not follow a chat redirect, so the key is not sent to the other host' {
        $sink = New-FairleadProbe @{ Mode = 'sink' }
        $probe = New-FairleadProbe @{ PostStatus = 302; RedirectPort = $sink.Port }
        $result = Invoke-ProbeRequest $probe 'chat'
        $result.ok | Should -BeFalse
        [string]$result.message | Should -Match 'not followed'
        [string]$result.message | Should -Not -Match 'synthetic-fairlead-key'
        $result.status | Should -Be 302
        $post = @((Get-ProbeHits $probe) | Where-Object { $_.path -eq '/v1/chat/completions' })
        $post.Count | Should -Be 1
        $post[0].authClass | Should -Be 'synthetic'
        (Get-ProbeHits $sink).Count | Should -Be 0
    }

    It 'does not follow a vision redirect, so the key is not sent to the other host' {
        $sink = New-FairleadProbe @{ Mode = 'sink' }
        $probe = New-FairleadProbe @{ PostStatus = 307; RedirectPort = $sink.Port }
        $result = Invoke-ProbeRequest $probe 'vision'
        $result.ok | Should -BeFalse
        [string]$result.message | Should -Match 'not followed'
        [string]$result.message | Should -Not -Match 'synthetic-fairlead-key'
        $result.status | Should -Be 307
        $post = @((Get-ProbeHits $probe) | Where-Object { $_.path -eq '/v1/chat/completions' })
        $post.Count | Should -Be 1
        $post[0].authClass | Should -Be 'synthetic'
        (Get-ProbeHits $sink).Count | Should -Be 0
    }

    It 'sends router chat and vision through the no-proxy no-redirect call' {
        $startPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Start-EightBells.ps1'
        $fairPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'EightBells-Fairlead.ps1'
        $start = Get-Content -LiteralPath $startPath -Raw
        $fair = Get-Content -LiteralPath $fairPath -Raw
        $calls = 0
        foreach ($line in ($start -split "`n")) {
            $trim = $line.Trim()
            if ($trim.StartsWith('#')) { continue }
            if ($trim -match 'Invoke-EightBellsRouterRequest') { $calls++ }
        }
        $calls | Should -Be 4
        $blocks = [regex]::Matches($start, 'if\(\$script:ai\.router\)\{')
        $blocks.Count | Should -Be 2
        foreach ($block in $blocks) {
            $slice = $start.Substring($block.Index, [Math]::Min(600, $start.Length - $block.Index))
            $slice | Should -Match 'Invoke-EightBellsRouterRequest'
            $slice | Should -Not -Match 'Invoke-RestMethod'
        }
        @([regex]::Matches($fair, '\.Proxy\s*=\s*\$null')).Count | Should -Be 2
        @([regex]::Matches($fair, 'AllowAutoRedirect\s*=\s*\$false')).Count | Should -Be 2
        $fair | Should -Not -Match 'Invoke-RestMethod'
    }
}
