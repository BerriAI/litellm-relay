# LiteLLM Relay

LiteLLM Relay is a local endpoint agent that routes AI app traffic through
LiteLLM Gateway and captures redacted request/response previews on the machine.
V0 focuses on macOS manual pilots and MDM-friendly PAC deployment for Notion Mac
app traffic.

Relay is implemented as a single Rust CLI/runtime. The backend is Rust because
the product sits on the local network path: it needs predictable startup,
low-overhead CONNECT tunneling, explicit TLS handling, and a single distributable
binary for endpoint installs.

## V0 scope

- Starts a local HTTP CONNECT proxy on `127.0.0.1:4142`.
- Serves a local dashboard at `http://127.0.0.1:4142/`.
- Serves a PAC file at `http://127.0.0.1:4142/proxy.pac`.
- Routes known AI domains through Relay when the PAC is installed.
- Generates a local Relay CA and uses it to decrypt configured AI domains.
- Logs redacted AI request/response previews to `~/.litellm-relay/relay.log.jsonl`.
- Optionally sends a synthetic shadow event through LiteLLM Gateway for audit correlation.

V0 does **not** capture cookies or authorization headers. Payload previews are
truncated and headers are redacted. If a specific app uses certificate pinning,
set `LITELLM_RELAY_CAPTURE_PAYLOADS=0` to fall back to metadata-only tunneling
for that pilot.

## Install

Install is interactive, like a local agent CLI. It builds the Rust binary, asks
for your LiteLLM Gateway URL, opens the Gateway SSO flow in the browser, waits
for authorization, saves the Relay credential, then starts the local service.

```text
LiteLLM Gateway URL [http://127.0.0.1:4000]:
Authentication method [sso]:
Opening LiteLLM Gateway SSO in your browser.
Waiting for Gateway authorization...
```

```bash
curl -fsSL https://raw.githubusercontent.com/BerriAI/litellm-relay/main/src/install.sh | bash
```

To immediately route Notion traffic on a pilot Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/BerriAI/litellm-relay/main/src/install.sh \
  | bash -s -- --set-system-proxy "Wi-Fi"
```

Gateway auth is stored in `~/.litellm-relay/env` with owner-only permissions.
Browser SSO is the default setup path. For headless or emergency installs, set
`LITELLM_GATEWAY_API_KEY` before running the installer and Relay will use that
key without opening SSO.

After install, running `litellm-relay` directly uses the saved setup. If no
Gateway auth is present yet, it starts the same interactive setup flow first.

## Local Pilot

Generate a test intercepted request:

```bash
curl --cacert ~/.litellm-relay/mitm/litellm-relay-ca.pem \
  -x http://127.0.0.1:4142 https://www.notion.so
```

Generate a Codex/OpenAI-style intercepted request:

```bash
curl --cacert ~/.litellm-relay/mitm/litellm-relay-ca.pem \
  -x http://127.0.0.1:4142 https://api.openai.com/v1/models
```

## Local development

```bash
cargo run -- serve
cargo run -- pac
cargo run -- ca-path
cargo test
cargo fmt --all --check
cargo clippy --all-targets -- -D warnings
```

## Docs

- [Notion AI shadowing v0](docs/notion-shadow-v0.md)
- [MDM rollout](docs/mdm.md)
- [Dashboard/product scope artifact](src/static/dashboard.html)
