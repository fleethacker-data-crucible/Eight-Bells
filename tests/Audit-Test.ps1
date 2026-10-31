param([string]$Root=(Split-Path -Parent $PSScriptRoot))
# Hash-chained audit trail: unit checks on the chain, then the live service, including a tampered encrypted store.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $Root 'EightBells-Audit.ps1')
Add-Type -AssemblyName System.Security

# ---- unit: chain construction and verification ----
$s=@{audit=@()}
1..3|ForEach-Object{Add-EightBellsAuditEvent $s 'import' ('id-'+$_)}
$r=Test-EightBellsAuditChain $s.audit
Assert-True ($r.ok -and $r.chained -eq 3 -and $r.legacy -eq 0) 'Three new events should form a valid chain'
Assert-True ($s.audit[0].prev -eq 'GENESIS' -and $s.audit[1].prev -eq $s.audit[0].hash) 'Each entry must link to the previous hash'
Assert-True ($s.audit[2].seq -eq 3) 'Sequence numbers must increase by one'

$edited=@($s.audit|ForEach-Object{$_})
$edited[1]=@{seq=$edited[1].seq;at=$edited[1].at;action=$edited[1].action;target='changed';prev=$edited[1].prev;hash=$edited[1].hash}
$r=Test-EightBellsAuditChain $edited
Assert-True (-not $r.ok -and $r.brokenAt -eq 2 -and $r.reason -match 'content') 'An edited entry must be detected at its position'

$removed=@($s.audit[0],$s.audit[2])
$r=Test-EightBellsAuditChain $removed
Assert-True (-not $r.ok -and $r.brokenAt -eq 2 -and $r.reason -match 'link') 'A removed entry must break the link'

$legacyPlusChain=@(@{at='2026-10-25T10:00:00Z';action='import';target='old'},@{at='2026-10-25T10:05:00Z';action='review';target='old2'})+@($s.audit)
$r=Test-EightBellsAuditChain $legacyPlusChain
Assert-True ($r.ok -and $r.legacy -eq 2 -and $r.chained -eq 3) 'Entries from before the upgrade count as legacy, not as failures'
$r=Test-EightBellsAuditChain (@($s.audit)+@(@{at='x';action='x';target='x'}))
Assert-True (-not $r.ok -and $r.reason -match 'unhashed') 'An unhashed entry after the chain started must fail'
$r=Test-EightBellsAuditChain @()
Assert-True ($r.ok -and $r.entries -eq 0) 'An empty trail verifies'

$capped=@{audit=@()}
1..2005|ForEach-Object{Add-EightBellsAuditEvent $capped 'import' ('id-'+$_)}
Assert-True (@($capped.audit).Count -eq 2000) 'The trail keeps the newest 2000 entries'
$r=Test-EightBellsAuditChain $capped.audit
Assert-True ($r.ok -and $r.chained -eq 2000) 'A capped trail must still verify from its first remaining entry'
Write-Host 'PASS: audit chain (links, edit and removal detection, legacy entries, unhashed tail, empty trail, 2000-entry cap)'

# ---- service: the route reports a valid chain, and an edit made to the encrypted store is detected ----
$sandbox=New-TestSandbox
$svc=$null
try{
  $svc=Start-TestService $Root $sandbox 'synthetic-audit-test-token-789'
  $imp=Post-Json $svc '/api/import' @{name='Synthetic audit log';watch='Engineering';content='0800 Synthetic entry';format='text';entries=@(@{line=1;time='08:00';text='Synthetic entry';issue=$false;resolution=$false});analysis=@{score=100;findings=@();open=@()};sourceType='digital-text'}
  $null=Post-Json $svc '/api/lesson' @{title='Synthetic lesson';body='Synthetic body';source=$imp.id}
  $v=Invoke-RestMethod -Uri ($svc.Url+'/api/audit/verify') -Headers $svc.Headers
  Assert-True ($v.ok -eq $true -and $v.chained -ge 2) 'Live trail should verify after an import and a lesson'
  Assert-HttpStatus {Invoke-WebRequest -UseBasicParsing -Uri ($svc.Url+'/api/audit/verify') -TimeoutSec 5} 401 'Audit verification without a token'
  Write-Host ('PASS: live audit trail verifies ('+$v.chained+' hashed entries)')

  # Edit the encrypted store as the same Windows account would, then ask again.
  Stop-TestProcess $svc;$svc=$null
  $store=Join-Path $sandbox 'store.v2.dpapi'
  $plain=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($store),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $state=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json
  $state.audit[0].target='rewritten-target'
  $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $state -Depth 70 -Compress))
  [IO.File]::WriteAllBytes($store,[Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
  $svc=Start-TestService $Root $sandbox 'synthetic-audit-test-token-789'
  $v=Invoke-RestMethod -Uri ($svc.Url+'/api/audit/verify') -Headers $svc.Headers
  Assert-True ($v.ok -eq $false -and $v.brokenAt -eq 1) 'An edited audit entry in the store must be detected'
  Write-Host 'PASS: edited audit entry in the encrypted store is detected'
}finally{
  Stop-TestProcess $svc
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
