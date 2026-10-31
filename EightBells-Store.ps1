# The encrypted store as the command line sees it: the same file, format and atomic replace as the server's
# Load-State and Save-State (Windows DPAPI, CurrentUser, version 2). Nothing here opens a port.
Add-Type -AssemblyName System.Security
function Get-EightBellsDataDir([string]$Override,[switch]$LocalDev){
  if($Override){return $Override}
  $env1=[Environment]::GetEnvironmentVariable('EIGHTBELLS_DATA_DIR')
  if($env1){return $env1}
  return (Join-Path $env:LOCALAPPDATA $(if($LocalDev){'EightBells-LocalDev'}else{'EightBells'}))
}
function New-EightBellsState{return [pscustomobject]@{version=2;logs=@();lessons=@();reviews=@();audit=@()}}
function Read-EightBellsStore([string]$DataDir){
  $store=Join-Path $DataDir 'store.v2.dpapi'
  if(!(Test-Path -LiteralPath $store)){return (New-EightBellsState)}
  try{
    $plain=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($store),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $value=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json
    if($value.version -ne 2){throw 'Unsupported database version'}
    return $value
  }catch{throw ('The encrypted store cannot be opened by this Windows account: '+$_.Exception.Message)}
}
function Write-EightBellsStore([string]$DataDir,$State){
  New-Item -ItemType Directory -Force -Path $DataDir|Out-Null
  $store=Join-Path $DataDir 'store.v2.dpapi'
  $raw=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $State -Depth 70 -Compress))
  $cipher=[Security.Cryptography.ProtectedData]::Protect($raw,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $tmp=$store+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  [IO.File]::WriteAllBytes($tmp,$cipher)
  try{
    if(Test-Path -LiteralPath $store){[IO.File]::Replace($tmp,$store,$store+'.backup',$true)}
    else{[IO.File]::Move($tmp,$store)}
  }finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
}
# Same audit entry as the server writes; uses the hash chain when EightBells-Audit.ps1 is loaded.
function Add-EightBellsStoreAudit($State,[string]$Action,[string]$Target){
  if(Get-Command Add-EightBellsAuditEvent -ErrorAction SilentlyContinue){Add-EightBellsAuditEvent $State $Action $Target;return}
  $State.audit=@($State.audit)+@(@{at=[DateTime]::UtcNow.ToString('o');action=$Action;target=$Target})
  if(@($State.audit).Count -gt 2000){$State.audit=@($State.audit|Select-Object -Last 2000)}
}
