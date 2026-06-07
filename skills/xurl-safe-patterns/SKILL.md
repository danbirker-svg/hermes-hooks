---
name: xurl-safe-patterns
description: Use when integrating xurl (X/Twitter CLI) with Hermes for automation, cron jobs, or engagement workflows. Covers rate-limit safety, cost management, WSL OAuth setup, VPS token management, and silent failure prevention.
version: 1.0.0
author: Hermes Agent + Daniel Birker
license: MIT
metadata:
  hermes:
    tags: [xurl, twitter, x, rate-limits, cost, oauth, vps, cron]
    related_skills: [credential-sync, gateway-watchdog]
---

# xurl Safe Patterns

Production patterns for using xurl with Hermes — especially in cron jobs and on remote VPS instances. Based on hard-learned lessons from running automated X engagement at scale.

## Overview

xurl is the official X/Twitter CLI. It's powerful but has sharp edges when automated: rate limits, token expiry, OAuth setup in headless environments, and costs that can spike without warning. This skill focuses on the Hermes-specific integration patterns that keep automation safe and reliable.

For the full xurl command reference, see the upstream xurl skill or https://github.com/xdevplatform/xurl.

## When to Use

- Setting up xurl in WSL (no browser for OAuth)
- Running xurl in Hermes cron jobs on a VPS
- Building automated X engagement workflows
- Avoiding rate limits and API cost surprises
- Syncing xurl tokens between local and remote Hermes instances

## Rate Limit Safety

### Read Operations

X API v2 has per-endpoint rate limits. A safe baseline for automated reads:

- **12 read calls/day** is safe and well within free/basic tier limits
- **3 searches/day** for content discovery
- **Rapid testing can trigger lockouts** — space test calls by at least 2 minutes

### Write Operations

Write endpoints (post, reply, like, repost) have tighter limits:
- **Posts:** 50/day on free tier, 500+/day on paid
- **Likes/Reposts:** ~50/day on free tier
- **Never automate writes in a tight loop** — at least 60 seconds between actions

### Cost Management

X API access is paid for meaningful usage. Key facts:
- **$25 can burn in one day** of aggressive testing
- **Read operations are cheap** (fractions of a cent)
- **Write operations cost more** but still modest
- **Check your balance** at developer.x.com → Portal → Billing before automating

Set a cost alert cron job (see `cost-monitor` skill) that monitors X API spend separately — xurl itself doesn't expose billing info.

## WSL OAuth Setup

WSL has no GUI browser, so `xurl auth oauth2` fails silently when it tries to open the URL. Here's the working pattern:

### One-Time Setup (user runs these commands)

```bash
# 1. Register your X Developer app at developer.x.com
#    - Set redirect URI to: http://localhost:8080/callback
#    - App type must be "Web app, automated app or bot"

# 2. Register the app locally
xurl auth apps add hermes-app --client-id YOUR_CLIENT_ID --client-secret YOUR_CLIENT_SECRET

# 3. Authenticate (this is the WSL-specific part)
#    Method A: If you have access to a Windows browser
#    Run xurl auth in a way that lets you copy the URL:
xurl auth oauth2 --app hermes-app 2>&1 | tee /tmp/xurl-auth.txt &
sleep 3
cat /tmp/xurl-auth.txt   # Find the auth.x.com URL, open in Windows browser

#    Method B: Using the hermes-agent skill pattern
#    (See hermes-agent skill → "Pattern for OAuth in WSL")

# 4. Set as default
xurl auth default hermes-app @YOUR_USERNAME

# 5. Verify
xurl whoami
```

### Common Setup Mistakes

1. **Token saved to `default` app instead of named app.** Always use `--app hermes-app` with `xurl auth oauth2`. Without it, tokens go to the built-in `default` profile (no client-id/secret) and all commands fail.

2. **App type set to "Native App".** X requires "Web app, automated app or bot" for OAuth 2.0 PKCE. You'll get `unauthorized_client` otherwise.

3. **Forgetting to set default.** `xurl auth oauth2 --app hermes-app` stores tokens, but `xurl auth default hermes-app` makes them active. Without `default`, xurl still tries the empty `default` profile.

## VPS Token Management

### The Problem

When you run Hermes cron jobs on a VPS that use xurl, the VPS needs its own copy of `~/.xurl`. You can scp it from your local machine, but:

- **Tokens expire.** OAuth2 refresh tokens have a finite lifetime.
- **Local copy auto-refreshes** when you use xurl locally, but the VPS copy is static.
- **You won't notice until cron jobs silently fail** with 401 errors.

### The Solution: Two-Layer Defense

**Layer 1: Sync script (local → VPS)**
```bash
# One-time seed
rsync ~/.xurl root@VPS_IP:/root/.xurl

# Automated sync (add to local crontab or Hermes cron with script=)
# See scripts/sync-credentials.sh in this repo
```

**Layer 2: VPS self-refresh (belt-and-suspenders)**
```bash
# On VPS: add to crontab (crontab -e)
*/30 * * * * /root/refresh-tokens.sh

# refresh-tokens.sh makes a cheap xurl search call every 30 min
# OAuth2 auto-refresh fires during the call → token stays alive indefinitely
```

With both layers: if your laptop is off for a week, the VPS self-refresh keeps tokens alive. If the VPS refresh mechanism fails, the next time your laptop is on, the sync script catches it up.

## Silent Failure Prevention in Cron Jobs

### The Problem

A cron job that uses xurl can fail silently. The job runs, xurl returns a 401, the agent has nothing to say, and the session ends with `[SILENT]`. `last_status` shows `ok` because the process didn't crash.

You don't find out until you notice nothing's been delivered for days.

### The Fix

Append this clause to every cron job prompt that uses xurl:

```
CRITICAL — IF XURL FAILS:
If any xurl command returns a 401 error or authentication failure, do NOT go silent.
Instead, respond with exactly this message so it gets delivered to Telegram:
⚠️ Cron job FAILED — xurl auth broken (401 error). Tokens may have expired on this machine.
Re-sync tokens from local machine or run the token refresh script.
Do not output [SILENT]. Always send the alert if xurl fails.
```

### Verify Delivery

After triggering a cron job:

```bash
# Check job ran recently (not an old session file)
ls -lt ~/.hermes/sessions/session_cron_* | head -3

# Check it produced real content (not [SILENT])
python3 -c "
import json
with open('path/to/session.json') as f:
    data = json.load(f)
for m in data['messages']:
    if m['role'] == 'assistant':
        print(m['content'][:300])
"

# If on VPS, trigger via SSH (not local CLI — different databases!)
ssh root@VPS_IP 'hermes cron run <JOB_ID>'
```

## Multi-Machine Reality

Two Hermes installs = two separate cron databases:

| | Local WSL | Remote VPS |
|---|---|---|
| Config | `/home/dan/.hermes/` | `/root/.hermes/` |
| Cron DB | Local only | Local only |
| Gateway | Off (CLI-only) | On (delivers to Telegram) |
| xurl tokens | Master copy | Synced copy |

**Critical rule:** `hermes cron run` from your local CLI runs the job LOCALLY — no gateway, no Telegram delivery. To trigger a job that actually delivers, run it on the gateway machine:

```bash
ssh root@VPS_IP 'hermes cron run <JOB_ID>'
```

## Common Pitfalls

1. **scp silently failing in sandboxed environments.** `execute_code` sandboxes lack SSH agent forwarding. Use terminal tool directly for SSH, or use rsync with explicit `-i` key path.

2. **`hermes cron run` from CLI triggers local DB, not VPS.** The success message is misleading. Always SSH to the gateway machine for production cron triggers.

3. **Rapid testing triggers rate limits.** Space test calls by 2+ minutes. After 3-4 rapid calls in succession, X may temporarily lock your app.

4. **OAuth tokens expire silently.** The 401 response looks identical to a permission error. Always check `xurl auth status` before assuming it's a permission issue.

5. **`last_status: ok` ≠ delivery.** It means the job process completed. Check session file content for actual output.

6. **X API v2 credits are pre-paid, not subscription-included.** Even if you pay for X Premium or SuperGrok, API access is billed separately.

## Verification Checklist

- [ ] `xurl auth status` shows a named app with oauth2 tokens (marked with ▸ as default)
- [ ] `xurl whoami` returns your user info
- [ ] `xurl search "test" -n 3` returns real results
- [ ] VPS has working xurl: `ssh root@VPS 'xurl whoami'`
- [ ] Token refresh script running on VPS (check crontab and refresh log)
- [ ] All cron job prompts include the xurl-failure escape clause
- [ ] You know how to trigger VPS cron jobs: `ssh root@VPS 'hermes cron run <ID>'`
