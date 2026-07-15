# RelayBar (Glass) — macOS menu bar app

A native SwiftUI `MenuBarExtra` app that shows **per-coding-tool AI spend** for the
LiteLLM Relay key, read live from the LiteLLM Gateway. Dark frosted-glass UI with a
per-agent color scheme.

<!-- Add a screenshot here -->

## What it shows

- **✨🚅 menu bar icon** → a frosted-glass popover.
- **Per-tool tabs** (each with its brand logo + accent color): Codex CLI, Codex App,
  Claude Code, Claude App, Cursor, Gemini, Copilot. Tabs distinguish **CLI vs desktop app**.
- For the selected tool (scoped to the relay key):
  - **This month** spend + tokens, **spend/day** chart, **model mix**.
  - Insight chips: **cache-hit rate**, **success rate**, **$/req**.
  - Tools that don't route through the relay key show a **"Not routed through Relay"** state.
- **Relay-key budget bar** — `spend / max_budget`, % used, reset date.

## Data source

Everything is pulled from the gateway using the key in `~/.litellm-relay/config.yaml`:

- `GET /key/info` → key hash, spend, `max_budget`, `budget_reset_at`.
- `GET /user/daily/activity?api_key=<keyHash>&start_date=…&end_date=…&page_size=500`
  → key-scoped daily metrics + per-model breakdown.

Two correctness notes baked in:
- **Filter by `api_key`** (singular) — otherwise the totals are account-wide, not the key's.
- **UTC date bucketing** — the gateway buckets by UTC day; the "today" figure uses the
  latest UTC day present so recent traffic isn't dropped by a local-date cutoff.

Relay status is a TCP check against `127.0.0.1:4142`.

## Build & run

```bash
cd macos/RelayBarGlass
./build.sh
open RelayBarGlass.app
```

Requires the Swift toolchain (Xcode or Command Line Tools) on macOS 13+.
The build produces an ad-hoc-signed `LSUIElement` app (menu bar only, no Dock icon).

## Layout

- `Sources/RelayBarGlass/RelayBarApp.swift` — `MenuBarExtra` entry + ✨🚅 label.
- `PopoverView.swift` — composes the tab bar + per-tool card.
- `AgentTabBar.swift` — the per-tool tab row with sliding accent underline.
- `UsageCard.swift` — the per-tool card (spend, chart, model mix, insights, budget).
- `AppModel.swift` — gateway fetch, key-scoping, per-tool mapping, budget.
- `Theme.swift` — dark glass tokens + `GlassBackground`.
- `AgentIcons.swift` — loads bundled brand SVGs via `Bundle.module`.
- `Resources/*.svg` — brand logos (lobehub icons).
