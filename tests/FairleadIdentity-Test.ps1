#requires -Version 5.1
# Loads Pester 5 and runs the Fairlead identity refusals. Windows smoke already executes every tests/*-Test.ps1.
# Pester is fetched into the temp directory for this run. Nothing is installed, and no token is printed.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Import-EightBellsPester {
    $have = @(Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' } | Sort-Object Version -Descending)
    if ($have.Count -gt 0) {
        Import-Module -Name $have[0].Path -Force
        return
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $temp = $env:RUNNER_TEMP
    if (-not $temp) { $temp = $env:TEMP }
    if (-not $temp) { $temp = [IO.Path]::GetTempPath() }
    $dir = Join-Path $temp 'pester-5.7.1'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $nupkg = Join-Path $dir 'Pester.5.7.1.nupkg'
    $expected = '4A27904C6814A5FBE4758F8E49861F6A1994AEE77B71165A5C43C0371BA6C580'
    if (-not (Test-Path -LiteralPath $nupkg)) {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://www.powershellgallery.com/api/v2/package/Pester/5.7.1' -OutFile $nupkg
    }
    $hash = (Get-FileHash -Algorithm SHA256 -Path $nupkg).Hash
    if ($hash -ne $expected) { throw ('Pester 5.7.1 SHA256 ' + $hash + ' did not match the pinned hash.') }
    $zip = Join-Path $dir 'Pester.zip'
    Copy-Item -LiteralPath $nupkg -Destination $zip -Force
    $mod = Join-Path $dir 'module'
    if (Test-Path -LiteralPath $mod) { Remove-Item -LiteralPath $mod -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $mod -Force
    Import-Module (Join-Path $mod 'Pester.psd1') -Force
}

Import-EightBellsPester
$cfg = New-PesterConfiguration
$cfg.Run.Path = Join-Path $PSScriptRoot 'FairleadIdentity.Tests.ps1'
$cfg.Run.Exit = $false
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $cfg
if ($result.FailedCount -gt 0) { exit 1 }
exit 0
