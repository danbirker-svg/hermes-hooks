# Hermes Hooks

Production-ready skills, scripts, and cron templates for [Hermes Agent](https://github.com/NousResearch/hermes-agent) — battle-tested patterns from running Hermes 24/7 across WSL and VPS environments.

## What's Inside

| Category | What You Get |
|----------|-------------|
| **Gateway Watchdog** | Health monitoring, crash recovery, conflict diagnosis for Hermes gateway |
| **Cost Monitor** | Track API spend across providers, predict monthly burn, alert before budget breach |
| **Credential Sync** | Keep OAuth tokens and API keys in sync between local and remote Hermes instances |
| **WSL Auto-Start** | Scripts and task scheduler configs to keep Hermes running after Windows reboots |
| **Cron Templates** | Proven cron job patterns — health checks, daily briefings, token refresh |

## Install

```bash
# Add this repo as a skill source
hermes skills tap add danbirker-svg/hermes-hooks

# Browse available skills
hermes skills search --source hermes-hooks

# Install a specific skill
hermes skills install gateway-watchdog --source hermes-hooks
```

Or install manually:

```bash
# Clone
git clone https://github.com/danbirker-svg/hermes-hooks.git
cd hermes-hooks

# Copy skills
cp -r skills/* ~/.hermes/skills/

# Copy scripts
cp scripts/* ~/.hermes/scripts/
chmod +x ~/.hermes/scripts/*.sh
```

## Skills

### `gateway-watchdog`
Diagnose and fix Hermes gateway issues: Telegram conflicts, cron delivery failures, multi-gateway conflicts, and dead gateway recovery. **Most installed skill** — every Hermes user with a gateway needs this.

### `cost-monitor`
Track API spend across Anthropic, OpenAI, OpenRouter, and X API. Set budget thresholds, get Telegram alerts before you blow past your monthly limit. Includes a ready-to-use cron job template.

### `credential-sync`
Keep OAuth tokens (xurl, xAI, etc.) synced between your local machine and a VPS running Hermes cron jobs. Includes token refresh scripts so your VPS stays authenticated without manual intervention.

### `xurl-safe-patterns`
Hard-won patterns for using xurl with Hermes safely — rate limit guardrails, WSL OAuth setup, VPS token management, silent failure prevention in cron jobs. Every Hermes user automating X/Twitter needs this.

## Scripts

| Script | What it does |
|--------|-------------|
| `auto-start-gateway.sh` | Detects dead gateway and restarts — drop into Windows Task Scheduler for WSL |
| `sync-credentials.sh` | Rsyncs credential files to remote VPS when local copy is newer |
| `refresh-tokens.sh` | Makes a cheap API call every 30 min to keep OAuth tokens alive on VPS |
| `check-gateway-alive.sh` | Silent watchdog — only outputs when gateway is down (for no_agent cron jobs) |

## Cron Templates

Copy-paste patterns for common cron jobs:

- **`health-check`** — Daily gateway health report delivered to Telegram
- **`daily-briefing`** — Aggregate content from feeds, format as a morning briefing
- **`token-refresh`** — Keep OAuth tokens alive on remote Hermes instances

## Who This Is For

You're running Hermes on a VPS, WSL, or both. You've set up cron jobs, Telegram delivery, maybe some X/Twitter automation. Things work… until they don't. The gateway goes silent. Cron jobs show `ok` but deliver nothing. Tokens expire on the VPS. You don't notice for days.

These hooks catch those failures before you do, and give you the tools to fix them fast.

## Contributing

Built and maintained by [@DBirker78883](https://x.com/DBirker78883). PRs welcome — if you've built something that made your Hermes setup more reliable, package it as a skill and submit it.
