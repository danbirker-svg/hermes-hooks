---
name: credential-sync
description: Use when OAuth tokens or API credentials need to stay fresh across multiple Hermes instances (local WSL + remote VPS). Sync credential files, set up self-refreshing tokens, and prevent silent auth failures in cron jobs.
version: 1.0.0
author: Hermes Agent + Daniel Birker
license: MIT
metadata:
  hermes:
    tags: [credentials, sync, oauth, tokens, vps, wsl, xurl, rsync]
    related_skills: [gateway-watchdog]
---

# Credential Sync

Keep OAuth tokens and credential files in sync between your local machine and remote Hermes instances. Prevents the most painful silent failure mode: cron jobs suddenly returning 401 because VPS tokens expired and nobody noticed.

## Overview

When you run Hermes on multiple machines (local WSL + Hetzner VPS, for example), credentials are the weakest link. OAuth tokens for xurl, xAI, and other services live in local files (`~/.xurl`, `~/.config/gh/hosts.yml`). You copy them to the VPS once, they work for a while, then silently expire. Cron jobs show `last_status: ok` but produce nothing — and you don't find out until you check Telegram and realize nothing arrived for days.

This skill gives you a belt-and-suspenders approach: sync scripts for the local→VPS path, and self-refreshing token scripts so the VPS doesn't depend on your local machine being online.

## When to Use

- You use xurl on a VPS for cron jobs (X engagement, content posting)
- You've hit "401 Unauthorized" on VPS tasks that work fine locally
- You're setting up a new VPS Hermes instance and need to seed credentials
- You want to stop manually scp'ing credential files every few weeks

Don't use this for: SSH key management, git credentials (use `gh auth login`), or API keys in `.env` files.

## Architecture

```
┌─────────────────────┐         rsync (mtime check)        ┌──────────────────┐
│   Local WSL         │ ──────────────────────────────────> │   Remote VPS      │
│   ~/.xurl (master)  │                                      │   /root/.xurl     │
│   ~/.config/gh/     │   Local cron: every 30 min           │                   │
│                     │                                      │   Self-refresh:   │
│   xurl refresh on   │                                      │   cron every 30m  │
│   normal usage      │                                      │   xurl search ... │
└─────────────────────┘                                      └──────────────────┘
```

Two independent mechanisms, so either one can fail and the other catches it:

1. **Sync script** (local → VPS): copies credential files when local is newer
2. **Token refresh** (VPS-side): makes cheap API calls to trigger OAuth auto-refresh

## Scripts

### sync-credentials.sh (runs locally)

Syncs credential files to a remote VPS. Compares mtime — only copies when local is newer.

```bash
#!/bin/bash
# Sync credential files to remote Hermes instance
# Config — edit these:
VPS_HOST="root@YOUR_VPS_IP"
SSH_KEY="$HOME/.ssh/id_ed25519"
LOG="$HOME/.hermes/logs/credential-sync.log"

# Files to sync (local_path:remote_path)
FILES=(
    "$HOME/.xurl:/root/.xurl"
    "$HOME/.config/gh/hosts.yml:/root/.config/gh/hosts.yml"
)

mkdir -p "$(dirname "$LOG")"

for entry in "${FILES[@]}"; do
    LOCAL="${entry%%:*}"
    REMOTE="${entry##*:}"

    if [ ! -f "$LOCAL" ]; then
        echo "$(date): SKIP $LOCAL (not found)" >> "$LOG"
        continue
    fi

    LOCAL_MTIME=$(stat -c %Y "$LOCAL" 2>/dev/null)
    REMOTE_MTIME=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes \
        "$VPS_HOST" "stat -c %Y $REMOTE 2>/dev/null || echo 0" 2>/dev/null)

    if [ "$LOCAL_MTIME" -gt "$REMOTE_MTIME" ]; then
        rsync -avz -e "ssh -i $SSH_KEY -o ConnectTimeout=10" \
            "$LOCAL" "$VPS_HOST:$REMOTE" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "$(date): SYNCED $LOCAL → $VPS_HOST:$REMOTE" >> "$LOG"
        else
            echo "$(date): ERROR rsync failed for $LOCAL" >> "$LOG"
        fi
    fi
done
```

### refresh-tokens.sh (runs on VPS)

Makes cheap API calls to trigger OAuth2 auto-refresh. Add to root crontab on VPS:

```bash
#!/bin/bash
# Self-refreshing token keeper for VPS Hermes instances
# Add to crontab: */30 * * * * /root/refresh-tokens.sh

LOG="/root/.hermes/logs/token-refresh.log"
mkdir -p "$(dirname "$LOG")"

# xurl token refresh
if command -v xurl &>/dev/null && [ -f /root/.xurl ]; then
    RESULT=$(xurl search "test" -n 3 2>&1)
    if echo "$RESULT" | grep -q '"data"'; then
        echo "$(date): xurl OK" >> "$LOG"
    else
        echo "$(date): xurl FAIL — $RESULT" >> "$LOG"
    fi
fi

# GitHub token check
if command -v gh &>/dev/null; then
    GH_STATUS=$(gh auth status 2>&1)
    if echo "$GH_STATUS" | grep -q "Logged in"; then
        echo "$(date): gh OK" >> "$LOG"
    else
        echo "$(date): gh FAIL — $GH_STATUS" >> "$LOG"
    fi
fi

# Rotate log
tail -200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
```

## Initial VPS Credential Seeding

When setting up a fresh VPS:

```bash
# xurl tokens (most likely to expire)
rsync ~/.xurl root@VPS_IP:/root/.xurl

# GitHub CLI auth
rsync ~/.config/gh/hosts.yml root@VPS_IP:/root/.config/gh/hosts.yml

# Verify on VPS
ssh root@VPS_IP 'xurl auth status && xurl search "test" -n 3'
ssh root@VPS_IP 'gh auth status'
```

## Cron Job: Token Refresh

Create a Hermes cron job that monitors token health and alerts you:

```
Schedule: 0 8 * * * (daily at 8am)
Prompt: |
  Check credential health on this machine:
  1. Run: xurl auth status
  2. Run: xurl search "test" -n 3  (verify API access)
  3. Run: gh auth status
  
  If everything is healthy, respond with: ✅ Credentials healthy
  If anything fails, respond with: ⚠️ ACTION NEEDED: <specific fix instructions>
  
  Deliver: telegram
```

## Security Notes

- **Never commit `~/.xurl` or credential files to git.** They're in `.gitignore` for a reason.
- **Use SSH keys, not passwords**, for rsync/scp.
- **Prefer rsync over scp** for credential files — rsync preserves permissions and only copies on change.
- **Log rotation is built in** — scripts keep last 200 lines to prevent disk fill.
- **Token files contain OAuth refresh tokens** — treat them like passwords.

## Common Pitfalls

1. **scp silently failing.** In sandboxed environments (like `execute_code`), SSH agent forwarding may not work. Use the terminal tool directly, or use rsync with explicit `-i` key path.

2. **rsync creating wrong permissions.** Add `-p` flag to preserve permissions, or `chmod 600` on the VPS after sync.

3. **Forgetting to set up VPS-side refresh.** The sync script only helps when your local machine is on. If your laptop is closed for a week, VPS tokens expire. Always set up `refresh-tokens.sh` as a belt-and-suspenders.

4. **Multiple files, one destination directory.** If syncing to a directory that doesn't exist on VPS, rsync creates it. Check paths exist first.

5. **Token file format changes.** xurl and other tools occasionally change their credential file format. Verify with `xurl auth status` after syncing.

## Verification Checklist

- [ ] Sync script copies files successfully: `bash ~/.hermes/scripts/sync-credentials.sh`
- [ ] VPS xurl works: `ssh root@VPS 'xurl search "test" -n 3'`
- [ ] VPS gh works: `ssh root@VPS 'gh auth status'`
- [ ] Token refresh script added to VPS crontab: `ssh root@VPS 'crontab -l | grep refresh'`
- [ ] Refresh log shows successful calls: `ssh root@VPS 'tail -5 /root/.hermes/logs/token-refresh.log'`
