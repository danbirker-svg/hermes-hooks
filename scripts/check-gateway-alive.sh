#!/bin/bash
# Check if Hermes gateway is running
# Silent when healthy, outputs alert when down
# Use as a no_agent cron job:
#   Schedule: */15 * * * *
#   Script: ~/.hermes/scripts/check_gateway_alive.sh
#   no_agent: true

# Check user-level service first
if systemctl --user is-active --quiet hermes-gateway 2>/dev/null; then
    exit 0
fi

# Check system-level service
if systemctl is-active --quiet hermes-gateway 2>/dev/null; then
    exit 0
fi

# Gateway is down — output alert (stdout gets delivered as message)
echo "⚠️ Hermes gateway is DOWN on $(hostname)"
echo "Run: hermes gateway start"
echo "Or SSH in and restart manually."
