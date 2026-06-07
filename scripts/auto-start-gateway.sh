#!/bin/bash
# Auto-start Hermes gateway on WSL startup
# Usage: Drop into Windows Task Scheduler to run at user login
# Action: wsl.exe -d Ubuntu -u YOUR_USER /home/YOUR_USER/.hermes/scripts/auto-start-gateway.sh
#
# Windows Task Scheduler setup:
#   1. Open Task Scheduler (taskschd.msc)
#   2. Create Basic Task → "Hermes Gateway Auto-Start"
#   3. Trigger: "When I log on"
#   4. Action: Start a program
#      Program: wsl.exe
#      Arguments: -d Ubuntu -u YOUR_USER /home/YOUR_USER/.hermes/scripts/auto-start-gateway.sh
#   5. Check "Run with highest privileges" (optional but recommended)
#   6. Finish

# Wait for network (WSL can take a few seconds after boot)
sleep 5

# Check if gateway is already running
if systemctl --user is-active --quiet hermes-gateway 2>/dev/null; then
    echo "$(date): Gateway already running" >> ~/.hermes/gateway_autostart.log
    exit 0
fi

# Check if system-level service exists
if systemctl is-active --quiet hermes-gateway 2>/dev/null; then
    echo "$(date): System-level gateway already running" >> ~/.hermes/gateway_autostart.log
    exit 0
fi

# Start the gateway
~/.local/bin/hermes gateway start 2>&1 >> ~/.hermes/gateway_autostart.log

if [ $? -eq 0 ]; then
    echo "$(date): Gateway auto-started successfully" >> ~/.hermes/gateway_autostart.log
else
    echo "$(date): Gateway auto-start FAILED" >> ~/.hermes/gateway_autostart.log
fi
