# Hash-chained audit trail. Each entry stores the SHA-256 of the entry before it, so an entry edited or removed
# in the middle of the log is detected. This is tamper-evident, not tamper-proof: whoever can rewrite the whole
# encrypted store can rebuild the chain, and dropping the newest entries is not detected without an outside anchor.
function Get-EightBellsAuditHash([long]$Seq,[string]$At,[string]$Action,[string]$Target,[string]$Prev){
  $text=[string]::Join('|',@([string]$Seq,$At,$Action,$Target,$Prev))
  $sha=[Security.Cryptography.SHA256]::Create()
  try{return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))|ForEach-Object {$_.ToString('x2')})}
  finally{$sha.Dispose()}
}
# Appends one event to $s.audit. Entries written before this version have no hash and stay as legacy entries.
function Add-EightBellsAuditEvent($s,[string]$action,[string]$target){
  $entries=@($s.audit)
  $last=$entries|Select-Object -Last 1
  $prev='GENESIS';$seq=1
  if($last -and $last.hash){$prev=[string]$last.hash}
  if($last -and $last.seq){$seq=[long]$last.seq+1}
  $at=[DateTime]::UtcNow.ToString('o')
  $hash=Get-EightBellsAuditHash $seq $at $action $target $prev
  $s.audit=$entries+@(@{seq=$seq;at=$at;action=$action;target=$target;prev=$prev;hash=$hash})
  # Keeping the newest 2000 entries drops the oldest link; verification then starts at the first remaining entry.
  if(@($s.audit).Count -gt 2000){$s.audit=@($s.audit|Select-Object -Last 2000)}
}
# Checks every hashed entry: its content hash and its link to the entry before it. Returns a result object.
function Test-EightBellsAuditChain($entries){
  $list=@($entries);$legacy=0;$chained=0;$prev=$null
  for($i=0;$i -lt $list.Count;$i++){
    $e=$list[$i]
    if(!$e.hash){
      if($null -ne $prev){return @{ok=$false;brokenAt=$i+1;reason='unhashed entry after the chain started'}}
      $legacy++;continue
    }
    if($null -ne $prev -and [string]$e.prev -ne $prev){return @{ok=$false;brokenAt=$i+1;reason='link to the previous entry is broken'}}
    $calc=Get-EightBellsAuditHash ([long]$e.seq) ([string]$e.at) ([string]$e.action) ([string]$e.target) ([string]$e.prev)
    if($calc -ne [string]$e.hash){return @{ok=$false;brokenAt=$i+1;reason='entry content does not match its hash'}}
    $prev=[string]$e.hash;$chained++
  }
  return @{ok=$true;entries=$list.Count;chained=$chained;legacy=$legacy}
}
