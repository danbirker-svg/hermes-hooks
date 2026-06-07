#!/bin/bash
# Sync credential files to a remote Hermes instance (VPS)
# Only copies when local file is newer than remote
# 
# Setup:
#   1. Edit VPS_HOST and SSH_KEY below
#   2. Add FILES entries for each credential you want to sync
#   3. Add to local crontab: */30 * * * * /path/to/sync-credentials.sh
#   4. Or create a Hermes cron job with script= parameter

set -euo pipefail

# === CONFIGURATION ===
VPS_HOST="root@YOUR_VPS_IP"
SSH_KEY="$HOME/.ssh/id_ed25519"
LOG="$HOME/.hermes/logs/credential-sync.log"

# Files to sync (local_path:remote_path — colon separated)
FILES=(
    "$HOME/.xurl:/root/.xurl"
    "$HOME/.config/gh/hosts.yml:/root/.config/gh/hosts.yml"
)

# === SCRIPT ===
mkdir -p "$(dirname "$LOG")"

for entry in "${FILES[@]}"; do
    LOCAL="${entry%%:*}"
    REMOTE="${entry##*:}"

    if [ ! -f "$LOCAL" ]; then
        echo "$(date): SKIP $LOCAL (file not found)" >> "$LOG"
        continue
    fi

    # Get local modification time
    LOCAL_MTIME=$(stat -c %Y "$LOCAL" 2>/dev/null) || {
        echo "$(date): ERROR stat failed for $LOCAL" >> "$LOG"
        continue
    }

    # Get remote modification time
    REMOTE_MTIME=$(ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        "$VPS_HOST" "stat -c %Y $REMOTE 2>/dev/null || echo 0" 2>/dev/null) || REMOTE_MTIME=0

    if [ "$LOCAL_MTIME" -gt "$REMOTE_MTIME" ]; then
        rsync -avz \
            -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
            "$LOCAL" "$VPS_HOST:$REMOTE" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo "$(date): SYNCED $LOCAL → $VPS_HOST:$REMOTE (local newer: $LOCAL_MTIME > $REMOTE_MTIME)" >> "$LOG"
        else
            echo "$(date): ERROR rsync failed for $LOCAL" >> "$LOG"
        fi
    else
        echo "$(date): No sync needed for $(basename "$LOCAL") (remote up to date)" >> "$LOG"
    fi
done

# Rotate log (keep last 500 lines)
tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
