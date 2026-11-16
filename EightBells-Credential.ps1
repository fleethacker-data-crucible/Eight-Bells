# Reads Eight Bells' Fairlead client key from Windows Credential Manager: the generic credential Fairlead/EightBells that
# Fairlead writes when you choose "Install for this app" (the same convention Halyard uses for Fairlead/Halyard).
# The key is read when a model call is made, held only for that call, and never stored, logged or returned in a response.
# Fairlead stores the blob as UTF-16 text; UTF-16LE is tried first and UTF-8 second (what cmdkey may leave).
# The C# is compiled in memory by Windows PowerShell 5.1 (framework assemblies and P/Invoke into advapi32 only; no DLL ships).
if(-not ('EightBells.CredReader' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace EightBells {
  public static class CredReader {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL {
      public int Flags; public int Type; public string TargetName; public string Comment;
      public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
      public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
      public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
    }
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);
    private static bool Printable(string text) {
      if (string.IsNullOrWhiteSpace(text)) return false;
      foreach (char ch in text.Trim()) if (ch < 0x20 || ch > 0x7E) return false;
      return true;
    }
    public static string Read(string target) {
      IntPtr ptr;
      if (!CredRead(target, 1, 0, out ptr)) return null;
      try {
        CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
        if (c.CredentialBlobSize <= 0 || c.CredentialBlob == IntPtr.Zero) return null;
        byte[] blob = new byte[c.CredentialBlobSize];
        Marshal.Copy(c.CredentialBlob, blob, 0, blob.Length);
        string wide = (blob.Length % 2 == 0) ? Encoding.Unicode.GetString(blob) : null;
        if (Printable(wide)) return wide.Trim();
        string narrow = Encoding.UTF8.GetString(blob);
        return Printable(narrow) ? narrow.Trim() : null;
      } finally { CredFree(ptr); }
    }
  }
}
'@
}
# The app name Fairlead installs the key for. Fairlead's app names are letters, digits and hyphens.
function Get-EightBellsFairleadTarget{ return 'Fairlead/EightBells' }
# Fairlead's own local token (docs/API.md, "How a tool gets its Fairlead key"): the credential Fairlead/<App> if
# present, otherwise the first line of %LOCALAPPDATA%\Fairlead\local-token. FAIRLEAD_LOCAL_TOKEN=off skips the file.
# FAIRLEAD_LOCAL_TOKEN_FILE moves it. The file is never logged. A line that is empty, longer than 4 KB, or not
# printable ASCII is ignored.
function Get-EightBellsLocalTokenPath{
  if([Environment]::GetEnvironmentVariable('FAIRLEAD_LOCAL_TOKEN') -eq 'off'){return $null}
  $custom=[Environment]::GetEnvironmentVariable('FAIRLEAD_LOCAL_TOKEN_FILE')
  if($custom){return $custom}
  $base=$env:LOCALAPPDATA
  if([string]::IsNullOrEmpty($base)){try{$base=[Environment]::GetFolderPath('LocalApplicationData')}catch{$base=$null}}
  if([string]::IsNullOrEmpty($base)){return $null}
  return (Join-Path (Join-Path $base 'Fairlead') 'local-token')
}
function Read-EightBellsLocalTokenFile([string]$Path){
  try{
    if([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    $info=New-Object IO.FileInfo $Path
    if($info.Length -le 0 -or $info.Length -gt 4096){return $null}
    $text=[IO.File]::ReadAllText($Path)
    $line=($text -split "`r?`n",2)[0]
    if($null -eq $line){return $null}
    $line=$line.Trim().TrimStart([char]0xFEFF)
    if($line.Length -lt 1){return $null}
    foreach($ch in $line.ToCharArray()){if([int]$ch -lt 0x21 -or [int]$ch -gt 0x7E){return $null}}
    return $line
  }catch{return $null}
}
# Returns @{key; source} where source is credential-manager, local-token or none. The key is $null when source is none.
# Tests may supply a key through EIGHTBELLS_TEST_FAIRLEAD_KEY, or a token file through EIGHTBELLS_TEST_LOCAL_TOKEN_FILE
# when the key variable is (none). Both apply only when the caller passes -AllowTestKey, so tests never read this
# account's Credential Manager or its real local-token file.
function Get-EightBellsFairleadKeyInfo([switch]$AllowTestKey){
  if($AllowTestKey){
    $t=[Environment]::GetEnvironmentVariable('EIGHTBELLS_TEST_FAIRLEAD_KEY')
    if($t -eq '(none)'){
      $file=[Environment]::GetEnvironmentVariable('EIGHTBELLS_TEST_LOCAL_TOKEN_FILE')
      if($file){$tok=Read-EightBellsLocalTokenFile $file;if($tok){return @{key=$tok;source='local-token'}}}
      return @{key=$null;source='none'}
    }
    if($t){return @{key=$t;source='credential-manager'}}
  }
  $key=$null
  try{$key=[EightBells.CredReader]::Read((Get-EightBellsFairleadTarget))}catch{$key=$null}
  if($key){return @{key=$key;source='credential-manager'}}
  # A test that did not set a key still must not open this account's local-token file.
  if($AllowTestKey){return @{key=$null;source='none'}}
  $path=Get-EightBellsLocalTokenPath
  if($path){$tok=Read-EightBellsLocalTokenFile $path;if($tok){return @{key=$tok;source='local-token'}}}
  return @{key=$null;source='none'}
}
function Get-EightBellsFairleadKey([switch]$AllowTestKey){
  return (Get-EightBellsFairleadKeyInfo -AllowTestKey:$AllowTestKey).key
}
