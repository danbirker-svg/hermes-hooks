#!/bin/bash
# Self-refreshing token keeper for VPS Hermes instances
# Makes cheap API calls to trigger OAuth2 auto-refresh
# 
# Setup:
#   1. Copy this script to /root/refresh-tokens.sh on your VPS
#   2. chmod +x /root/refresh-tokens.sh
#   3. Add to crontab: crontab -e
#      */30 * * * * /root/refresh-tokens.sh

LOG="/root/.hermes/logs/token-refresh.log"
mkdir -p "$(dirname "$LOG")"

FAILURES=0

# === xurl token refresh (X/Twitter API) ===
if command -v xurl &>/dev/null && [ -f /root/.xurl ]; then
    RESULT=$(xurl search "test" -n 3 2>&1)
    if echo "$RESULT" | grep -q '"data"'; then
        echo "$(date): xurl OK" >> "$LOG"
    else
        echo "$(date): xurl FAIL — $RESULT" >> "$LOG"
        FAILURES=$((FAILURES + 1))
    fi
fi

# === GitHub CLI token check ===
if command -v gh &>/dev/null; then
    GH_STATUS=$(gh auth status 2>&1)
    if echo "$GH_STATUS" | grep -q "Logged in"; then
        echo "$(date): gh OK" >> "$LOG"
    else
        echo "$(date): gh FAIL — $GH_STATUS" >> "$LOG"
        FAILURES=$((FAILURES + 1))
    fi
fi

# === Summary ===
if [ $FAILURES -gt 0 ]; then
    echo "$(date): ⚠️  $FAILURES token refresh(es) FAILED" >> "$LOG"
fi

# Rotate log (keep last 500 lines)
tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
