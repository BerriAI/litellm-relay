# Windows MDM artifacts

Windows MDM proxy configuration is console-based, not a file format like
macOS `.mobileconfig`. Use [`networkproxy-oma-uri.md`](networkproxy-oma-uri.md)
for the exact Intune NetworkProxy CSP values. The optional
[`set-pac-proxy.ps1`](set-pac-proxy.ps1) script is suitable for an Intune
remediation or platform script when a per-user WinINET setting is preferred.
