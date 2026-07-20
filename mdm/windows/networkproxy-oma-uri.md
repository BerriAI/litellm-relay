# Windows NetworkProxy OMA-URI

Configure a Custom OMA-URI profile in Intune with these values:

| OMA-URI | Data type | Value |
| --- | --- | --- |
| `./Vendor/MSFT/Policy/Config/NetworkProxy/ProxyPacUrl` | String | `http://127.0.0.1:4142/proxy.pac` |
| `./Vendor/MSFT/Policy/Config/NetworkProxy/AutoDetectProxy` | Integer | `0` |

The same policy is available in Settings Catalog as **Network > Proxy >
Proxy Pac Url**. Windows MDM proxy configuration is console-based rather than
a file artifact like macOS `.mobileconfig`, so this document is the deployable
reference for the profile.
