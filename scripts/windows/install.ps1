[CmdletBinding()]
param(
    [string]$Version,
    [string]$Sha256,
    [string]$SourceUrl,
    [switch]$AllowUnpinnedMain,
    [string]$PrebuiltBinary,
    [string]$ConfigFile,
    [switch]$SkipSetup,
    [switch]$SkipAutoconfigure,
    [switch]$SkipTrustCa,
    [switch]$Background,
    [switch]$SetSystemProxy,
    [string]$GatewayUrl,
    [string]$ApiKey,
    [string]$InstallDir,
    [int]$AutoconfigureInterval = 3600
)

$ErrorActionPreference = "Stop"
$RelayHome = Join-Path $env:USERPROFILE ".litellm-relay"
$RelayBinDir = Join-Path $RelayHome "bin"
$RelayBinary = Join-Path $RelayBinDir "litellm-relay.exe"
$RelayShim = Join-Path $RelayBinDir "relay.cmd"
$RelayPort = 4142

function Get-EnvironmentValue([string]$Name, [string]$Value) {
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }
    return [Environment]::GetEnvironmentVariable($Name)
}

function Get-EnvironmentSwitch([string]$Name, [bool]$IsSet, [bool]$Value, [bool]$Default) {
    if ($IsSet) {
        return $Value
    }
    $environmentValue = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($environmentValue)) {
        return $Default
    }
    return $environmentValue -notin @("0", "false", "False", "no", "No")
}

$Version = Get-EnvironmentValue "RELAY_VERSION" $Version
$Sha256 = Get-EnvironmentValue "RELAY_SHA256" $Sha256
$SourceUrl = Get-EnvironmentValue "RELAY_SOURCE_URL" $SourceUrl
$PrebuiltBinary = Get-EnvironmentValue "RELAY_PREBUILT_BINARY" $PrebuiltBinary
$ConfigFile = Get-EnvironmentValue "RELAY_MANAGED_CONFIG" $ConfigFile
$GatewayUrl = Get-EnvironmentValue "RELAY_GATEWAY_URL" $GatewayUrl
$ApiKey = Get-EnvironmentValue "RELAY_API_KEY" $ApiKey
if (-not $PSBoundParameters.ContainsKey("AutoconfigureInterval")) {
    $intervalEnvironmentValue = [Environment]::GetEnvironmentVariable("RELAY_AUTOCONFIGURE_INTERVAL")
    if ($intervalEnvironmentValue) {
        $AutoconfigureInterval = [int]$intervalEnvironmentValue
    }
}
$SkipSetupEffective = if ($PSBoundParameters.ContainsKey("SkipSetup")) {
    $SkipSetup.IsPresent
} elseif ([Environment]::GetEnvironmentVariable("RELAY_SKIP_SETUP")) {
    [Environment]::GetEnvironmentVariable("RELAY_SKIP_SETUP") -in @("1", "true", "True", "yes", "Yes")
} else {
    $false
}
$SkipAutoconfigureEffective = if ($PSBoundParameters.ContainsKey("SkipAutoconfigure")) {
    $SkipAutoconfigure.IsPresent
} elseif ([Environment]::GetEnvironmentVariable("RELAY_AUTOCONFIGURE")) {
    [Environment]::GetEnvironmentVariable("RELAY_AUTOCONFIGURE") -in @("0", "false", "False", "no", "No")
} else {
    $false
}
$SkipTrustCaEffective = if ($PSBoundParameters.ContainsKey("SkipTrustCa")) {
    $SkipTrustCa.IsPresent
} elseif ([Environment]::GetEnvironmentVariable("RELAY_TRUST_CA")) {
    [Environment]::GetEnvironmentVariable("RELAY_TRUST_CA") -in @("0", "false", "False", "no", "No")
} else {
    $false
}
$BackgroundEffective = Get-EnvironmentSwitch "RELAY_BACKGROUND" $PSBoundParameters.ContainsKey("Background") $Background.IsPresent $false
$SetSystemProxyEffective = Get-EnvironmentSwitch "RELAY_SET_SYSTEM_PROXY" $PSBoundParameters.ContainsKey("SetSystemProxy") $SetSystemProxy.IsPresent $false
$AllowUnpinnedMainEffective = Get-EnvironmentSwitch "RELAY_ALLOW_UNPINNED_MAIN" $PSBoundParameters.ContainsKey("AllowUnpinnedMain") $AllowUnpinnedMain.IsPresent $false
$BackgroundEffective = $BackgroundEffective -or $SetSystemProxyEffective

if ($AutoconfigureInterval -le 0) {
    throw "AutoconfigureInterval must be greater than zero."
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -eq "S-1-5-18" -or $env:USERNAME -eq "SYSTEM") {
    throw "Do not install LiteLLM Relay as SYSTEM. Intune must run this installer in the installing user's context."
}

function Write-Usage {
    @"
Install LiteLLM Relay on Windows.

Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-Version VERSION]
                 [-PrebuiltBinary PATH] [-Background] [-SetSystemProxy]

Options:
  -Version VERSION               Download and build the named GitHub release tag
  -Sha256 SHA256                 Verify the downloaded source archive checksum
  -SourceUrl URL                 Download source from an explicit archive URL
  -AllowUnpinnedMain             Allow remote install from mutable main.tar.gz
  -PrebuiltBinary PATH           Install this prebuilt relay binary instead of building
  -ConfigFile PATH               Seed %USERPROFILE%\.litellm-relay\config.yaml
  -SkipSetup                     Skip the interactive gateway setup wizard
  -SkipAutoconfigure              Do not auto-detect and wire installed AI tools
  -SkipTrustCa                   Install without adding the Relay CA to the user Root store
  -Background                    Configure Gateway auth and Scheduled Tasks
  -SetSystemProxy                Route Windows WinINET through Relay's PAC URL
  -GatewayUrl URL                Gateway URL for non-interactive setup
  -ApiKey KEY                    Gateway key for non-interactive setup
  -InstallDir DIR                Reserved compatibility option; Relay uses its per-user home
  -AutoconfigureInterval SECONDS Seconds between periodic re-detection (default 3600)

When run from a checked-out repository, this builds the local source tree.
Remote source builds require -Version, -SourceUrl, or -AllowUnpinnedMain.
Endpoints do not need Rust when -PrebuiltBinary is supplied.

RELAY_VERSION, RELAY_SHA256, RELAY_SOURCE_URL, RELAY_ALLOW_UNPINNED_MAIN,
RELAY_PREBUILT_BINARY, RELAY_MANAGED_CONFIG, RELAY_SKIP_SETUP,
RELAY_AUTOCONFIGURE, RELAY_AUTOCONFIGURE_INTERVAL, and RELAY_TRUST_CA are
also accepted as environment equivalents of the matching options.
"@
}

if ($args -contains "-h" -or $args -contains "--help") {
    Write-Usage
    exit 0
}

if ($Sha256 -and $Sha256 -notmatch "^[A-Fa-f0-9]{64}$") {
    throw "Sha256 must be a 64-character SHA-256 hex digest."
}

function Get-SourceTree([string]$TemporaryDirectory) {
    if ($SourceUrl) {
        $downloadUrl = $SourceUrl
    } elseif ($Version) {
        $downloadUrl = "https://github.com/LiteLLM-Labs/litellm-relay/archive/refs/tags/$Version.tar.gz"
    } elseif ($AllowUnpinnedMainEffective) {
        $downloadUrl = "https://github.com/LiteLLM-Labs/litellm-relay/archive/refs/heads/main.tar.gz"
        Write-Warning "Installing from mutable main because RELAY_ALLOW_UNPINNED_MAIN=1 was set. Prefer -Version plus -Sha256 for production deployments."
    } else {
        throw "Remote install requires a pinned source. Pass -Version, -SourceUrl, or explicitly opt in with -AllowUnpinnedMain."
    }

    $archive = Join-Path $TemporaryDirectory "litellm-relay-source.tar.gz"
    Write-Host "Downloading LiteLLM Relay source: $downloadUrl"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archive
    if ($Sha256) {
        Write-Host "Verifying source archive SHA-256..."
        $actual = (Get-FileHash -Path $archive -Algorithm SHA256).Hash
        if ($actual.ToLowerInvariant() -ne $Sha256.ToLowerInvariant()) {
            throw "Source archive checksum mismatch; expected $Sha256, actual $actual."
        }
        Write-Host "Source archive checksum verified."
    } else {
        Write-Warning "No source archive checksum was provided. Set RELAY_SHA256 or pass -Sha256 for a checksum-verified install."
    }

    $extractDir = Join-Path $TemporaryDirectory "source"
    New-Item -ItemType Directory -Path $extractDir | Out-Null
    tar -xzf $archive -C $extractDir
    $cargoToml = Get-ChildItem -Path $extractDir -Filter Cargo.toml -Recurse -File | Select-Object -First 1
    if (-not $cargoToml) {
        throw "Source archive did not contain Cargo.toml."
    }
    return $cargoToml.Directory.FullName
}

New-Item -ItemType Directory -Path $RelayBinDir -Force | Out-Null

if ($PrebuiltBinary) {
    if (-not (Test-Path -LiteralPath $PrebuiltBinary -PathType Leaf)) {
        throw "Prebuilt binary not found: $PrebuiltBinary"
    }
    Write-Host "Installing prebuilt LiteLLM Relay binary..."
    Copy-Item -LiteralPath $PrebuiltBinary -Destination $RelayBinary -Force
} else {
    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargo) {
        throw "cargo is not installed. Windows endpoints do not need Rust: pass -PrebuiltBinary litellm-relay.exe. For a source install, install Rust from https://rustup.rs/ and rerun this script."
    }

    $localRoot = Join-Path $PSScriptRoot "..\.."
    $localCargo = Join-Path $localRoot "Cargo.toml"
    $temporaryDirectory = $null
    if (-not (Test-Path -LiteralPath $localCargo -PathType Leaf)) {
        $temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("litellm-relay-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
        $localRoot = Get-SourceTree $temporaryDirectory
    }

    Write-Host "Building LiteLLM Relay..."
    Push-Location $localRoot
    try {
        & cargo build --quiet --release
        if ($LASTEXITCODE -ne 0) {
            throw "cargo build failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
    $builtBinary = Join-Path $localRoot "target\release\litellm-relay.exe"
    if (-not (Test-Path -LiteralPath $builtBinary -PathType Leaf)) {
        throw "cargo build completed but did not produce $builtBinary."
    }
    Copy-Item -LiteralPath $builtBinary -Destination $RelayBinary -Force
    if ($temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($ConfigFile) {
    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        throw "Managed config file not found: $ConfigFile"
    }
    Write-Host "Seeding managed Relay config from $ConfigFile"
    Copy-Item -LiteralPath $ConfigFile -Destination (Join-Path $RelayHome "config.yaml") -Force
}

$pathValue = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($pathValue -split ";" | Where-Object { $_ })
if ($pathEntries -notcontains $RelayBinDir) {
    [Environment]::SetEnvironmentVariable("Path", (($pathEntries + $RelayBinDir) -join ";"), "User")
}
$env:Path = "$RelayBinDir;$env:Path"
Set-Content -LiteralPath $RelayShim -Value "@`"%~dp0litellm-relay.exe`" %*" -Encoding ASCII

$caPath = (& $RelayBinary ca-path | Select-Object -Last 1).ToString().Trim()
if (-not $SkipTrustCaEffective) {
    try {
        $isAdministrator = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $store = if ($isAdministrator) { "Cert:\LocalMachine\Root" } else { "Cert:\CurrentUser\Root" }
        Import-Certificate -FilePath $caPath -CertStoreLocation $store | Out-Null
        Write-Host "Trusted Relay CA in $store."
    } catch {
        Write-Warning "Could not add the Relay CA to the Windows certificate store. Payload capture requires trusting this certificate: $caPath"
    }
} else {
    Write-Warning "Skipping Relay CA trust because RELAY_TRUST_CA=0 or -SkipTrustCa was set. Payload capture requires trusting this certificate later: $caPath"
}

function Invoke-Autoconfigure {
    if ($SkipAutoconfigureEffective) {
        return
    }
    $configPath = Join-Path $RelayHome "config.yaml"
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return
    }
    Write-Host "Auto-configuring installed AI tools to route through the Gateway..."
    & $RelayBinary autoconfigure
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "AI tool auto-configuration did not complete."
    }
}

if (-not $BackgroundEffective) {
    Invoke-Autoconfigure
    @"
LiteLLM Relay installed.

Command:     $RelayShim
Relay CA:    $caPath

Start the interactive setup and live trace view:
  relay
"@
    exit 0
}

if ($SkipSetupEffective) {
    Write-Host "Skipping interactive gateway setup (-SkipSetup)."
    if (-not (Test-Path -LiteralPath (Join-Path $RelayHome "config.yaml") -PathType Leaf)) {
        Write-Warning "-SkipSetup was set but $RelayHome\config.yaml does not exist. Seed a managed config with -ConfigFile so Relay can reach your Gateway."
    }
    Invoke-Autoconfigure
} else {
    $setupArguments = @("setup")
    if ($GatewayUrl) { $setupArguments += @("--gateway-url", $GatewayUrl) }
    if ($ApiKey) { $setupArguments += @("--api-key", $ApiKey) }
    & $RelayBinary @setupArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Relay setup failed with exit code $LASTEXITCODE."
    }
}

$pacOutput = @(& $RelayBinary pac)
$pacPath = Join-Path $RelayHome "relay.pac"
$pacOutput | Set-Content -LiteralPath $pacPath -Encoding ASCII
$pacMatch = $pacOutput | Select-String -Pattern "PROXY 127\.0\.0\.1:(\d+)" | Select-Object -First 1
if ($pacMatch -and $pacMatch.Matches.Count -gt 0) {
    $RelayPort = [int]$pacMatch.Matches[0].Groups[1].Value
}

function New-RelayTask([string]$TaskName, [string]$Arguments, [object[]]$Triggers) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute $RelayBinary -Argument $Arguments -WorkingDirectory $RelayHome
    $settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType InteractiveToken -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $Triggers -Settings $settings -Principal $principal | Out-Null
}

$atLogOn = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
New-RelayTask "LiteLLM Relay" "serve" @($atLogOn)

if (-not $SkipAutoconfigureEffective) {
    # Windows keeps all tools in one per-user task. Unlike macOS, the
    # ProgramData Claude Desktop path is normally writable by that user.
    $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Seconds $AutoconfigureInterval) -RepetitionDuration ([TimeSpan]::MaxValue)
    New-RelayTask "LiteLLM Relay Autoconfigure" "autoconfigure" @($atLogOn, $repeat)
}

if ($SetSystemProxyEffective) {
    $proxyUrl = "http://127.0.0.1:$RelayPort/proxy.pac"
    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name AutoConfigURL -Value $proxyUrl
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
    Write-Host "Enabled WinINET PAC auto-proxy: $proxyUrl"
}

@"
LiteLLM Relay installed.

Command:     $RelayShim
Relay proxy: 127.0.0.1:$RelayPort
Dashboard:   http://127.0.0.1:$RelayPort/
PAC URL:     http://127.0.0.1:$RelayPort/proxy.pac
Relay CA:    $caPath
Logs:        $(Join-Path $RelayHome "relay.log.jsonl")

To open the interactive terminal view:
  relay

Gateway auth and Relay settings are saved in $(Join-Path $RelayHome "config.yaml").
"@
