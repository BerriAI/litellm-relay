# Windows MDM rollout

LiteLLM Relay ships to employee Windows endpoints as a Win32 app deployed
through Microsoft Intune, plus a NetworkProxy policy that points Windows
AutoConfig at Relay's local PAC URL. Endpoints do **not** need Rust/cargo:
the Win32 payload carries a prebuilt `litellm-relay.exe` and installs it for
the console user. Run the installer in **User** context, not SYSTEM.

Recommended shape, same as other endpoint software: manual pilot on one
Windows device, then a small Intune pilot group, then broaden.

## What gets deployed

| Artifact | Purpose | Source |
| --- | --- | --- |
| `litellm-relay-<tag>-x86_64-pc-windows-msvc.zip` | Prebuilt Windows binary and deployment scripts | GitHub Release artifact from [`release.yml`](../.github/workflows/release.yml) |
| `install.ps1` / `uninstall.ps1` | Per-user install, Scheduled Tasks, CA trust, and offboarding | [`scripts/windows`](../scripts/windows) |
| NetworkProxy policy | Points Windows AutoConfig at `http://127.0.0.1:4142/proxy.pac` | [`mdm/windows/networkproxy-oma-uri.md`](../mdm/windows/networkproxy-oma-uri.md) |
| Managed `config.yaml` | Gateway URL, capture/shadow settings | [`mdm/config.yaml.example`](../mdm/config.yaml.example) |

## Package the Win32 app

Put these files in one payload directory:

```text
install.ps1
uninstall.ps1
litellm-relay.exe
config.yaml
```

`config.yaml` is optional. Build the executable with
`cargo build --release --target x86_64-pc-windows-gnu` on a cross-build host,
or build on a Windows runner with `cargo build --release`; release binaries
are attached to GitHub Releases.

Use Microsoft's [Win32 Content Prep Tool](https://learn.microsoft.com/mem/intune/apps/lob-apps-windows)
to create the `.intunewin` package.

Install command:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1 -PrebuiltBinary litellm-relay.exe -Background -SkipSetup -ConfigFile config.yaml
```

Uninstall command:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
```

Configure **Install behavior: User**. The detection rule is a file-exists
rule for:

```text
%USERPROFILE%\.litellm-relay\bin\litellm-relay.exe
```

The default installer trusts Relay's per-user CA in the Windows user Root
store, seeds `%USERPROFILE%\.litellm-relay\config.yaml`, puts the Relay bin
directory on the user's PATH, and registers per-user Scheduled Tasks.

## Microsoft Intune

1. **Wrap and upload the app.** Run the Win32 Content Prep Tool against the
   payload directory and create an Intune app under Apps → Windows → Add →
   **Windows app (Win32)**. Upload the resulting `.intunewin`.
2. **Configure the program.** Use the install and uninstall commands above,
   set **User** install behavior, and assign as **Required** to a pilot user
   group. Do not run the install command as SYSTEM.
3. **Configure detection.** Add the file detection rule for
   `%USERPROFILE%\.litellm-relay\bin\litellm-relay.exe`.
4. **Deploy the PAC policy.** Create the Custom OMA-URI profile described in
   [`mdm/windows/networkproxy-oma-uri.md`](../mdm/windows/networkproxy-oma-uri.md),
   or use Settings Catalog → Network → Proxy → **Proxy Pac Url**. Assign it
   to the same pilot group.
5. **Verify.** Monitor the app install status, then check the dashboard and
   Gateway traffic on a pilot endpoint.
6. **Broaden.** Expand the app and policy assignments to the full user group.

## PAC system proxy

The NetworkProxy CSP is the preferred managed setting:

```text
./Vendor/MSFT/Policy/Config/NetworkProxy/ProxyPacUrl
  Type: String
  Value: http://127.0.0.1:4142/proxy.pac

./Vendor/MSFT/Policy/Config/NetworkProxy/AutoDetectProxy
  Type: Integer
  Value: 0
```

The equivalent Settings Catalog policy is **Network > Proxy > Proxy Pac Url**.
Use one managed approach rather than competing policy and user settings.
For a manual pilot, `install.ps1 -Background -SetSystemProxy` writes the same
per-user WinINET `AutoConfigURL` and refreshes WinINET immediately.

## Trusted certificate profile

The default install trusts Relay's **per-device** CA in the installing user's
Root store. An Intune machine-wide trusted-certificate profile is therefore
only useful for a future shared managed-CA MITM mode; it is not part of the
default rollout. The installer warns with the CA path if user-store import
fails.

## Verify

On a pilot endpoint:

```powershell
Get-ScheduledTask -TaskName "LiteLLM Relay"
Get-ScheduledTask -TaskName "LiteLLM Relay Autoconfigure"
```

Open `http://127.0.0.1:4142/`, then generate traffic from a configured AI tool
and confirm the request appears in the LiteLLM Gateway. The PAC endpoint is
`http://127.0.0.1:4142/proxy.pac`.

## Offboarding / uninstall

Unassign the PAC profile and deploy `uninstall.ps1` as the Win32 app uninstall
command or as an Intune remediation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1 -UnsetSystemProxy
```

By default, uninstall preserves Relay data, configuration, CA files, CA trust,
and proxy settings. For full cleanup:

```powershell
.\uninstall.ps1 -UnsetSystemProxy -RemoveCaTrust -RemoveData
```

## Notes

Windows has one per-user WinINET PAC setting. The Windows installer uses
Scheduled Tasks instead of macOS LaunchAgents; the serve task and the
autoconfigure task both run in the installing user's context. Unlike macOS,
Windows folds Claude Desktop into the same per-user autoconfigure task because
`%ProgramData%\ClaudeDesktop` is generally writable by the creating user and
autoconfigure continues past an individual tool failure.

Using `-ApiKey` (or `gateway.api_key` in the managed config) writes a static
Gateway key to every device. Prefer per-user browser SSO where your Gateway
supports it.
