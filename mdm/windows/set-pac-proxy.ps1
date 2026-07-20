$ErrorActionPreference = "Stop"

$settingsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$pacUrl = "http://127.0.0.1:4142/proxy.pac"
New-Item -Path $settingsPath -Force | Out-Null
Set-ItemProperty -Path $settingsPath -Name AutoConfigURL -Value $pacUrl

if (-not ("Relay.WinInet" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace Relay {
  public static class WinInet {
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
    public static void Refresh() {
      InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
      InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
    }
  }
}
"@
}
[Relay.WinInet]::Refresh()
Write-Host "Enabled WinINET PAC auto-proxy: $pacUrl"
