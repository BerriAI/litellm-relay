# LiteLLM Relay

LiteLLM Relay is a proxy you install on employee machines through your MDM. It does two things.

First, it sets up your developers' AI tools for them. On install, Relay **auto-detects the AI tools already on the machine** — Claude Desktop, Claude Code, and Codex (CLI, VS Code, and the macOS and Windows apps) — and wires each one to your LiteLLM AI Gateway automatically. There is no per-tool opt-in: if Relay recognizes a tool, it routes it through the Gateway. Developers just launch the tool and sign in with their corporate identity, with no provider API key and no manual setup. See [Auto-configuration](#auto-configuration) and the [AI Tool Guides](#ai-tool-guides) below.

Second, it catches shadow AI. Relay detects AI traffic from tools like Notion AI, Perplexity, and OpenClaw and routes it to the Gateway too, making it a single pane of glass for all AI usage in your company.

<img width="2467" height="1080" alt="relay-hero" src="https://github.com/user-attachments/assets/e766224d-014b-4083-b03e-be11abfb0b4a" />

# Usage 
 1. Install LiteLLM Relay on all your employee devices, using [supported MDM](https://github.com/LiteLLM-Labs/litellm-relay#supported-mdms)
 2. Employees use AI tools as they normally would, such as Notion AI.
    <img width="2200" height="1654" alt="Xnapper-2026-07-09-18 25 01" src="https://github.com/user-attachments/assets/01f59c09-c927-4d04-af37-35ff5b7ec8fb" />
 3. Every request, response, and usage event is captured in LiteLLM.
    <img width="2200" height="1327" alt="Xnapper-2026-07-09-18 47 14" src="https://github.com/user-attachments/assets/dfe69818-ba4d-4874-b386-d3d7a061be39" />

## Auto-configuration

Relay is opt-out, not opt-in. When you install it (or run `relay setup`), Relay
scans the device for supported AI tools and wires every one it finds to the
Gateway in a single pass — you never enumerate tools per machine.

| Tool | Detected by | Config Relay writes |
| --- | --- | --- |
| Claude Code CLI | `claude` on `PATH` or `~/.claude` | `~/.claude/settings.json` |
| Claude Desktop | macOS `/Applications/Claude.app` or app-support dir; Windows Claude/AnthropicClaude install or `%APPDATA%\Claude` | macOS `/etc/claude-desktop/managed-settings.json`; Windows `%ProgramData%\ClaudeDesktop\managed-settings.json` |
| Codex (CLI, VS Code, macOS app) | `codex` on `PATH`, `Codex.app`, the `openai.chatgpt` VS Code extension, or `~/.codex` | `~/.codex/config.toml` |

Detection also runs on a schedule, so a tool installed *after* Relay gets wired
to the Gateway automatically — no manual re-run. Because each tool's config
lives in a different place, the installer registers two periodic jobs (both at
login and every `RELAY_AUTOCONFIGURE_INTERVAL` seconds, default 3600):

| Job | Runs as | Tools | Why |
| --- | --- | --- | --- |
| `ai.litellm.relay.autoconfigure` (LaunchAgent) | you | Claude Code, Codex | configs are user-writable (`~/.claude`, `~/.codex`) |
| `ai.litellm.relay.autoconfigure-desktop` (LaunchDaemon) | root | Claude Desktop on macOS | its managed file is the root-owned `/etc/claude-desktop/managed-settings.json` |

On Windows, both serve and auto-configuration run as the installing user in
Scheduled Tasks; there is no separate root task. On macOS, the root daemon pins
`HOME` to the installing user so it reads that user's Relay config while running
as root. Installing it needs root; `install.sh` uses `sudo` when not already
root.

You can still run detection on demand, and scope it with `--only`:

```bash
relay autoconfigure                       # every detected tool
relay autoconfigure --only claude-desktop # just one (repeatable)
```

Unset flags fall back to the saved Relay config, so a managed `config.yaml`
seeded by your MDM is enough to configure a device with no arguments. Pass
`--authorize-url`, `--team`, `--api-key`, or the `--oidc-*` flags to override.
Only detected tools are touched, and one tool failing never blocks the others.
Pass `--skip-autoconfigure` to `install.sh` to disable it.

## Developers see their own usage, locally

Relay also ships an optional **macOS menu bar app** so each developer can see **their own AI spend right on their machine** — no dashboard login. It reads live, key-scoped usage from the Gateway and breaks it down per coding tool: spend this month, spend/day, model mix, cache-hit rate, and the relay key's budget.

<p>
  <img width="340" alt="Claude Code usage in the menu bar" src="docs/img/relaybar-claude-code.png" />
  <img width="340" alt="Codex CLI usage in the menu bar" src="docs/img/relaybar-codex-cli.png" />
</p>

Each tool (Claude Code, Codex CLI, Cursor, Gemini, …) gets its own tab with its own color. Build it from [`macos/RelayBarGlass`](macos/RelayBarGlass) (`./build.sh && open RelayBarGlass.app`).

## AI Tool Guides

Relay onboards each AI coding tool onto the LiteLLM AI Gateway with zero developer setup — the developer just launches the tool. Pick your tool for the step-by-step guide:

- [Claude Desktop](docs/claude-desktop.md)
- [Claude Code CLI](docs/claude-code.md)
- [Codex CLI](docs/codex-cli.md)
- [Codex with VS Code](docs/codex-vscode.md)

## Supported MDMs

Deploy LiteLLM Relay with your existing device-management process:

- Jamf
- [Microsoft Intune (Windows)](docs/mdm-windows.md)
- Kandji
- Mosyle
- VMware Workspace ONE
- Addigy
- Custom shell scripts or internal deployment workflows

See the [macOS MDM rollout guide](docs/mdm.md) and the
[Windows Intune rollout guide](docs/mdm-windows.md).

## Features

- Detect shadow AI usage across employee devices and company traffic sources
- Route AI traffic through LiteLLM AI Gateway for central visibility
- Log AI activity from desktop apps, browser AI, coding tools, agents, MCP
  clients, and LLM APIs
- Apply one set of Gateway controls for audit, access, provider routing, and
  policy

Relay does not log cookies or authorization headers. Payload previews are
truncated and headers are redacted.

## Install

Relay has no tagged release yet, so install it from GitHub. The macOS installer
builds Relay from source, so you need [Rust](https://rustup.rs/) (`cargo`)
installed first. Windows deployments should use the prebuilt release binary and
[`scripts/windows/install.ps1`](scripts/windows/install.ps1); macOS LaunchAgents
become per-user Scheduled Tasks on Windows.

Clone the repository and run the installer:

```bash
git clone https://github.com/LiteLLM-Labs/litellm-relay.git
cd litellm-relay
./src/install.sh
```

Or install directly from `main` without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/LiteLLM-Labs/litellm-relay/main/src/install.sh | \
  RELAY_ALLOW_UNPINNED_MAIN=1 bash
```

The installer builds the `relay` command, adds it to your `PATH`, and trusts
the local Relay CA so AI app payloads can be captured. Pass `--skip-trust-ca`
to install without trusting the CA.

Then open a new terminal and run:

```bash
relay
```

Once tagged releases are published, production deployments will be able to pin
a version tag and verify the source archive checksum:

```bash
curl -fsSL https://raw.githubusercontent.com/LiteLLM-Labs/litellm-relay/main/src/install.sh | \
  RELAY_VERSION=vX.Y.Z \
  RELAY_SHA256=<release-tarball-sha256> \
  bash
```
