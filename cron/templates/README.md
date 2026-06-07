# Cron Job Templates

Copy-paste patterns for common Hermes cron jobs. Each template is a self-contained prompt you can plug into `hermes cron create` or the cronjob tool.

## Daily Health Check

Checks gateway status, credential health, and recent job execution. Delivers a status card to Telegram every morning.

```
Schedule: 0 8 * * *
Name: Daily Health Check
Toolsets: terminal
Deliver: telegram

Prompt:
Run these checks and format the results as an emoji status card:

1. Gateway status:
   Run: hermes gateway status
   ✅ if active (running), ❌ otherwise

2. Cron job health:
   Run: hermes cron list
   Count jobs with last_status: ok vs failed
   List any jobs whose last_run_at is >24h ago

3. Credential check (if xurl is installed):
   Run: xurl auth status 2>/dev/null || echo "xurl not installed"
   Run: gh auth status 2>/dev/null || echo "gh not installed"

4. Disk space:
   Run: df -h / | tail -1

Format as:
```
🏥 Daily Health — 2026-XX-XX
Gateway: ✅ Running
Cron Jobs: 5/5 OK, last run <12h ago
xurl auth: ✅
gh auth: ✅
Disk: 45% used (89G free)

⚠️ ACTION NEEDED: (only if something is red — include specific fix command)
```
```

## Weekly Cost Report

Runs the cost monitor script and delivers a spending summary.

```
Schedule: 0 9 * * 1  (every Monday at 9am)
Name: Weekly Cost Report
Toolsets: terminal
Deliver: telegram

Prompt:
Run: python3 ~/.hermes/scripts/cost_monitor.py 7

Format the output as a Telegram-friendly summary:
💰 Weekly API Spend: $X.XX
📊 30-day projection: $XX.XX

Breakdown:
• Anthropic: $X.XX (XX% of total)
• OpenRouter: $X.XX (XX%)
• Other: $X.XX (XX%)

Most expensive model: <name> at $X.XX

If 30-day projection exceeds $100, add:
⚠️ BUDGET WARNING: On track for $XXX this month
```

## Token Refresh (VPS-side)

Keeps OAuth tokens alive on a remote VPS by making cheap API calls every 30 minutes. This is a `no_agent` cron job — it runs the script directly with no LLM involvement.

```
Schedule: */30 * * * *
Name: Token Refresh
Script: ~/.hermes/scripts/refresh-tokens.sh
no_agent: true
```

This job produces no output when healthy (silent = all good). If a token fails, the script logs the error and the cron scheduler can deliver the error output.

## Dead Gateway Alert

Monitors whether the gateway is running. Uses no_agent mode for efficiency — only delivers when gateway is down.

```bash
#!/bin/bash
# Save as ~/.hermes/scripts/check_gateway_alive.sh
if systemctl --user is-active --quiet hermes-gateway 2>/dev/null; then
    exit 0  # Silent — gateway is fine
elif systemctl is-active --quiet hermes-gateway 2>/dev/null; then
    exit 0  # System-level gateway is fine
else
    echo "⚠️ Hermes gateway is DOWN on $(hostname)"
    echo "Run: hermes gateway start"
    echo "Or SSH in and restart manually."
fi
```

```
Schedule: */15 * * * *
Name: Dead Gateway Alert
Script: ~/.hermes/scripts/check_gateway_alive.sh
no_agent: true
```
