# The command registry: every UI action that works on the stored data is one `eightbells <noun> <verb>` command.
# `route` is the server route the command mirrors; tests/Cli-Test.ps1 checks that every route in Start-EightBells.ps1 is
# either mirrored here or listed in Get-EightBellsExcludedRoutes with a reason, so the CLI cannot silently fall behind the UI.
function New-EbInput([string]$Flag,[string]$Type,[bool]$Required,[string]$Help,[string[]]$Values){
  $i=[ordered]@{flag=$Flag;key=$Flag;type=$Type;required=$Required;help=$Help}
  if($Values){$i.values=$Values}
  return $i
}
function Get-EightBellsCommands{
  $dispositions='acknowledged','follow-up','false-positive'
  $formats='auto','text','csv','json'
  return @(
    [ordered]@{name='status show';route='GET /api/state';summary='Counts of logs, lessons, reviews and audit entries, and whether a server is running for this data folder.';inputs=@();destructive=$false;writes=$false}
    [ordered]@{name='log list';route='GET /api/state';summary='List imported logs.';inputs=@();destructive=$false;writes=$false}
    [ordered]@{name='log show';route='GET /api/state';summary='One log with its analysis summary.';inputs=@((New-EbInput 'id' 'string' $true 'Log id'));destructive=$false;writes=$false}
    [ordered]@{name='log import';route='POST /api/import';summary='Parse a text, CSV or JSON file with the engine port and store it as a log.';inputs=@((New-EbInput 'file' 'string' $true 'Path of the file to import'),(New-EbInput 'name' 'string' $false 'Log title (default: the file name)'),(New-EbInput 'watch' 'string' $false 'Watch profile label (default: Other)'),(New-EbInput 'format' 'string' $false 'auto, text, csv or json (default: auto)' $formats),(New-EbInput 'interval' 'number' $false 'Required reading interval in minutes (default: none)'));destructive=$false;writes=$true}
    [ordered]@{name='finding list';route='GET /api/state';summary='Quality findings of a log, with how many reviews each has.';inputs=@((New-EbInput 'log' 'string' $true 'Log id'));destructive=$false;writes=$false}
    [ordered]@{name='finding review';route='POST /api/review';summary='Record a reviewer disposition and explanation for a finding. The source log is not changed.';inputs=@((New-EbInput 'log' 'string' $true 'Log id'),(New-EbInput 'finding' 'string' $true 'Finding id, for example f1'),(New-EbInput 'disposition' 'string' $true 'acknowledged, follow-up or false-positive' $dispositions),(New-EbInput 'note' 'string' $true 'Reviewer explanation'));destructive=$false;writes=$true}
    [ordered]@{name='turnover show';route='GET /api/state';summary='The offline turnover draft for a log.';inputs=@((New-EbInput 'log' 'string' $true 'Log id'));destructive=$false;writes=$false}
    [ordered]@{name='lesson list';route='GET /api/state';summary='List lessons and their status.';inputs=@();destructive=$false;writes=$false}
    [ordered]@{name='lesson add';route='POST /api/lesson';summary='Save a lesson as a draft.';inputs=@((New-EbInput 'title' 'string' $true 'Lesson title'),(New-EbInput 'body' 'string' $true 'Evidence explanation'),(New-EbInput 'source' 'string' $false 'Source log id'));destructive=$false;writes=$true}
    [ordered]@{name='lesson review';route='POST /api/lesson/review';summary='Mark a lesson locally reviewed. This is not an authenticated approval.';inputs=@((New-EbInput 'id' 'string' $true 'Lesson id'));destructive=$false;writes=$true}
    [ordered]@{name='memory candidates';route='GET /api/state';summary='Equipment with potentially open conditions in at least two logs.';inputs=@();destructive=$false;writes=$false}
    [ordered]@{name='memory search';route='GET /api/state';summary='Search lessons and logs.';inputs=@((New-EbInput 'q' 'string' $false 'Text to find (default: everything)'));destructive=$false;writes=$false}
    [ordered]@{name='export json';route='GET /api/state';summary='Write all records to an UNENCRYPTED JSON file. Needs --out and --yes.';inputs=@();destructive=$true;writes=$false}
  )
}
# Server routes with no command, and why. Anything not mirrored and not listed here fails the parity test.
function Get-EightBellsExcludedRoutes{
  return @(
    [ordered]@{route='GET /health';reason='Liveness probe of a running server; the CLI has no server.'}
    [ordered]@{route='GET /api/diagnostics';reason='Reads the running server log lines; the CLI has no service log.'}
    [ordered]@{route='POST /api/ai/config';reason='Session-bound: the endpoint and key exist only in the running server''s memory.'}
    [ordered]@{route='POST /api/ai/run';reason='Session-bound: needs the endpoint and key held by the running server, and per-request consent in the page.'}
    [ordered]@{route='POST /api/vision';reason='Session-bound: needs the endpoint and key held by the running server, and per-image consent in the page.'}
    [ordered]@{route='POST /api/heartbeat';reason='Tab lifecycle of the browser; the CLI has no tab.'}
    [ordered]@{route='POST /api/shutdown';reason='Stops the running server; use Stop-EightBells.ps1 from the shell.'}
  )
}
