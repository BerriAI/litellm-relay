[CmdletBinding()]
param(
    [switch]$KeepBin,
    [switch]$RemoveCaTrust,
    [switch]$UnsetSystemProxy,
    [switch]$RemoveData
)

$ErrorActionPreference = "Stop"
$RelayHome = Join-Path $env:USERPROFILE ".litellm-relay"
$RelayBinDir = Join-Path $RelayHome "bin"
$RelayBinary = Join-Path $RelayBinDir "litellm-relay.exe"
$RelayShim = Join-Path $RelayBinDir "relay.cmd"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -eq "S-1-5-18" -or $env:USERNAME -eq "SYSTEM") {
    throw "Do not uninstall LiteLLM Relay as SYSTEM. Run this in the installing user's context."
}

function Write-Usage {
    @"
Uninstall LiteLLM Relay from Windows.

Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
                 [-KeepBin] [-RemoveCaTrust] [-UnsetSystemProxy] [-RemoveData]

Options:
  -KeepBin                       Keep Relay shims and binary
  -RemoveCaTrust                Remove Relay CA trust from Windows Root stores
  -UnsetSystemProxy             Turn off the Relay PAC auto-proxy setting
  -RemoveData                   Remove %USERPROFILE%\.litellm-relay after cleanup

Default behavior removes the Scheduled Tasks, command shim, and Relay binary.
It intentionally preserves logs, config, CA files, and proxy settings unless
explicit flags are passed.
"@
}

if ($args -contains "-h" -or $args -contains "--help") {
    Write-Usage
    exit 0
}

function Refresh-WinInet {
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
}

Unregister-ScheduledTask -TaskName "LiteLLM Relay" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "LiteLLM Relay Autoconfigure" -Confirm:$false -ErrorAction SilentlyContinue

if ($UnsetSystemProxy) {
    $internetSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Remove-ItemProperty -Path $internetSettings -Name AutoConfigURL -ErrorAction SilentlyContinue
    Refresh-WinInet
    Write-Host "Disabled WinINET PAC auto-proxy."
}

if ($RemoveCaTrust) {
    $stores = @("Cert:\CurrentUser\Root", "Cert:\LocalMachine\Root")
    foreach ($store in $stores) {
        Get-ChildItem -Path $store -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -like "*CN=LiteLLM Relay Local Root CA*" } |
            ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.PSPath -Force
                    Write-Host "Removed Relay CA trust from $store."
                } catch {
                    Write-Warning "Could not remove Relay CA $($_.Thumbprint) from $store. Run with administrator rights to remove machine trust."
                }
            }
    }
}

if (-not $KeepBin) {
    Remove-Item -LiteralPath $RelayShim -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $RelayBinary -Force -ErrorAction SilentlyContinue
    $pathValue = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = @($pathValue -split ";" | Where-Object { $_ -and $_ -ne $RelayBinDir })
    [Environment]::SetEnvironmentVariable("Path", ($pathEntries -join ";"), "User")
    Write-Host "Removed Relay shim, binary, and user PATH entry."
} else {
    Write-Host "Preserved Relay shim and binary because -KeepBin was set."
}

if ($RemoveData) {
    $normalizedHome = [IO.Path]::GetFullPath($RelayHome).TrimEnd("\")
    $normalizedUserProfile = [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd("\")
    if ([string]::IsNullOrWhiteSpace($normalizedHome) -or $normalizedHome -eq "\" -or $normalizedHome -eq $normalizedUserProfile) {
        throw "Refusing to remove unsafe Relay home: $RelayHome"
    }
    Remove-Item -LiteralPath $RelayHome -Recurse -Force
    Write-Host "Removed Relay data: $RelayHome"
} else {
    Write-Host "Preserved Relay data: $RelayHome"
}

@"
LiteLLM Relay uninstall complete.

Removed:
  Scheduled Task: LiteLLM Relay
  Scheduled Task: LiteLLM Relay Autoconfigure

Optional cleanup:
  Remove CA trust:     .\uninstall.ps1 -RemoveCaTrust
  Remove Relay data:   .\uninstall.ps1 -RemoveData
  Disable system PAC:  .\uninstall.ps1 -UnsetSystemProxy
"@
