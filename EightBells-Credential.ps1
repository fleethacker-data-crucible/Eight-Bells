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
# Returns the key text, or $null when none is installed. Tests may supply a key through EIGHTBELLS_TEST_FAIRLEAD_KEY, but only
# in the isolated test service (the caller passes -AllowTestKey); the real Credential Manager is never touched by tests.
function Get-EightBellsFairleadKey([switch]$AllowTestKey){
  if($AllowTestKey){
    $t=[Environment]::GetEnvironmentVariable('EIGHTBELLS_TEST_FAIRLEAD_KEY')
    if($t -eq '(none)'){return $null}
    if($t){return $t}
  }
  try{return [EightBells.CredReader]::Read((Get-EightBellsFairleadTarget))}catch{return $null}
}
