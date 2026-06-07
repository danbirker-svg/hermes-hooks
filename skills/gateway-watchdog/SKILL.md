---
name: gateway-watchdog
description: Use when the Hermes gateway is unresponsive, cron jobs stop delivering, Telegram shows polling conflicts, or you suspect multi-gateway interference. Diagnose and fix gateway health issues, crash loops, token problems, and silent delivery failures.
version: 1.0.0
author: Hermes Agent + Daniel Birker
license: MIT
metadata:
  hermes:
    tags: [hermes, gateway, telegram, cron, systemd, vps, wsl, diagnostics]
    related_skills: [credential-sync, cost-monitor]
---

# Gateway Watchdog

Keep your Hermes gateway alive, healthy, and delivering. Based on months of 24/7 production operation across WSL + VPS with Telegram, cron jobs, and multiple API integrations.

## Overview

The Hermes gateway is the always-on process that connects messaging platforms (Telegram, Discord, etc.) and runs cron jobs. When it fails — and it will fail — you lose cron delivery, Telegram responses, and scheduled automation. The failure modes are subtle: cron jobs show `last_status: ok` even when nothing was delivered, and you can go weeks without noticing.

This skill gives you the diagnostic patterns, recovery commands, and prevention scripts to keep your gateway healthy.

## When to Use

- Cron jobs aren't delivering to Telegram (but show `last_status: ok`)
- Telegram bot stopped responding
- Gateway shows `inactive (dead)` or crash-looping
- "Telegram polling conflict" warnings in logs
- After a Hermes update or VPS reboot
- Setting up a new multi-machine Hermes deployment

Don't use this for: model selection issues, API key problems (see `cost-monitor`), or skill installation problems.

## Architecture: One Gateway, One Token

**The golden rule:** One bot token = one running gateway. Period.

If you run Hermes on multiple machines (e.g., WSL desktop + VPS server), pick ONE to be the gateway. The other should be CLI-only. Two gateways sharing a Telegram bot token will fight every ~12 seconds — Telegram sends each poll update to only one instance, the other gets a conflict error, and both degrade.

```
✅ CORRECT:
  VPS: gateway running (systemd, always-on) → Telegram + cron delivery
  WSL: CLI-only (`hermes gateway uninstall`) → interactive sessions only

❌ WRONG:
  Both running gateway → Telegram conflicts, missed messages, crash loops
```

## Diagnostic Commands

### Check if gateway is alive

```bash
# Systemd-based (VPS)
systemctl --user status hermes-gateway
systemctl status hermes-gateway   # if system-level

# Process check
ps aux | grep 'gateway run' | grep -v grep

# Hermes built-in
hermes gateway status
```

### Check recent log output

```bash
# Main gateway log
tail -40 ~/.hermes/logs/gateway.log

# Look for key signals
grep -i "conflict\|error\|started\|connected\|cron" ~/.hermes/logs/gateway.log | tail -20

# Cron-specific
hermes cron list
```

### Verify Telegram connectivity

```bash
# Test the bot token directly
curl -s "https://api.telegram.org/bot<TOKEN>/getMe"

# Check for polling conflicts (the #1 failure mode)
grep "conflict" ~/.hermes/logs/gateway.log | tail -5
```

## Common Failure Modes

### 1. Telegram Polling Conflict

**Symptom:** Log shows `Conflict: terminated by other getUpdates request` every ~12 seconds.

**Cause:** Two gateway instances polling the same bot token.

**Fix:**
```bash
# Kill ALL gateway processes
pkill -f "hermes.*gateway"

# Wait 30 seconds for Telegram to release the old session
sleep 30

# On the machine that should NOT run gateway:
hermes gateway uninstall

# On the gateway machine:
hermes gateway start
```

### 2. Gateway Crash Loop

**Symptom:** `systemctl status` shows `activating (auto-restart)` cycling every 30 seconds. After 5 failures in 10 minutes, systemd gives up and shows `inactive (dead)`.

**Fix:**
```bash
# Kill the cycle
kill -9 $(ps aux | grep 'gateway run' | grep -v grep | awk '{print $2}')

# Reset systemd failure counter (required or start won't work)
systemctl --user reset-failed hermes-gateway.service

# Uninstall if competing with another gateway
hermes gateway uninstall

# Start fresh
hermes gateway start
```

### 3. Silent Cron Delivery Failure

**Symptom:** `hermes cron list` shows `last_status: ok` for all jobs, but nothing arrives in Telegram.

**Cause:** The gateway isn't running, so cron jobs execute locally but have no transport to deliver messages. `last_status` means the job process didn't crash — it doesn't mean delivery succeeded.

**Diagnose:**
```bash
# Check gateway status first
hermes gateway status

# Check if the job actually produced content
ls -lt ~/.hermes/sessions/session_cron_* | head -3
```

**Fix:** Start the gateway. If jobs need to run on a remote machine (VPS), trigger them there:
```bash
ssh user@vps 'hermes cron run <JOB_ID>'
```

### 4. Gateway Dies on WSL Close / Reboot

**Symptom:** Gateway works while WSL terminal is open, dies when you close the window or restart Windows.

**Cause:** WSL2 without `systemd=true` can't run systemd user services reliably. After a host reboot, nothing auto-starts the gateway.

**Fix — three layers:**

1. Enable systemd in WSL (`/etc/wsl.conf`):
   ```ini
   [boot]
   systemd=true
   ```

2. Use the auto-start script (`scripts/auto-start-gateway.sh` in this repo)

3. Add Windows Task Scheduler trigger: run at login, action:
   ```
   wsl.exe -d Ubuntu -u YOUR_USER /home/YOUR_USER/.hermes/scripts/auto-start-gateway.sh
   ```

### 5. VPS Token Expiry (xurl/OAuth)

**Symptom:** Cron jobs on VPS that use xurl return 401 errors. xurl works fine locally.

**Cause:** OAuth tokens live in `~/.xurl` on your local machine. If you copied them to VPS once but never refreshed, they expired. The local copy auto-refreshes when you use xurl locally — the VPS copy is static.

**Immediate fix:**
```bash
# Copy fresh tokens to VPS
rsync ~/.xurl root@VPS_IP:/root/.xurl
```

**Permanent fix:** See `credential-sync` skill and `scripts/refresh-tokens.sh`.

## Prevention Checklist

- [ ] Only ONE gateway per bot token
- [ ] `approvals.cron_mode` set to `auto` (not `ask`)
- [ ] Gateway installed as systemd service (survives reboots)
- [ ] Auto-start script in place for WSL
- [ ] Token refresh cron job on VPS (30-minute interval)
- [ ] Daily health check cron job delivering to Telegram
- [ ] Gateway status verified after every `hermes update`

## Recovery Script (One-Liner)

Drop this on your gateway machine as `~/fix-gateway.sh`:

```bash
#!/bin/bash
systemctl --user reset-failed hermes-gateway.service 2>/dev/null
systemctl --user restart hermes-gateway.service 2>/dev/null || \
  systemctl restart hermes-gateway 2>/dev/null
sleep 3
echo "=== STATUS ==="
systemctl --user status hermes-gateway 2>/dev/null || systemctl status hermes-gateway
echo "=== RECENT LOG ==="
tail -20 ~/.hermes/logs/gateway.log
```

## Common Pitfalls

1. **Trusting `last_status: ok`.** It means the job process didn't crash. It does NOT mean Telegram received a message. Always verify with `hermes gateway status` + check actual session file content.

2. **`hermes gateway uninstall` doesn't stick.** Opening a new `hermes` CLI session may auto-reinstall the gateway. If you want a machine to stay CLI-only, check after each session.

3. **SSH from sandboxed environments.** `execute_code` sandboxes lack SSH agent forwarding. Use the terminal tool directly for SSH commands.

4. **Forgetting to `reset-failed` before restarting.** After 5 crash-loop cycles, systemd rate-limits restarts. `systemctl --user reset-failed hermes-gateway.service` is required before `start` will work again.

5. **`hermes update` doesn't always restart the gateway.** Even when the output says "Gateway restarted", verify with `hermes gateway status`. The gateway can stay dead silently.

## Verification Checklist

- [ ] `hermes gateway status` shows `active (running)`
- [ ] `hermes cron list` shows jobs with `last_status: ok` and recent timestamps
- [ ] No `conflict` lines in `gateway.log` for 60+ seconds
- [ ] `curl https://api.telegram.org/bot<TOKEN>/getMe` returns `ok: true`
- [ ] A test cron job triggered manually delivers to Telegram
