---
name: cost-monitor
description: Use when you need to track, predict, or alert on AI API spending across providers (Anthropic, OpenAI, OpenRouter, X API). Monitor real-time usage, forecast monthly burn rates, and get Telegram alerts before exceeding budget thresholds.
version: 1.0.0
author: Hermes Agent + Daniel Birker
license: MIT
metadata:
  hermes:
    tags: [api, cost, spending, budget, monitoring, anthropic, openai, openrouter, alerts]
    related_skills: [gateway-watchdog, credential-sync]
---

# Cost Monitor

Track API spend across AI providers and get alerted before you blow your budget. Designed for multi-provider setups where costs are spread across Anthropic, OpenAI, OpenRouter, and X API — making it easy to lose track until the bill arrives.

## Overview

Running LLM-powered automation means API costs. A single misconfigured cron job, an unexpected rate increase, or a loop can burn through your monthly budget in hours. This skill gives you visibility and alerts so you catch overages before they happen.

## When to Use

- You use 2+ AI providers and want consolidated cost tracking
- You've been surprised by a bill ($25 in one day of X API testing? Been there.)
- You want Telegram alerts when you approach budget thresholds
- You're running cron jobs and need to know their per-job cost
- You're optimizing prompts and need to measure cost impact

Don't use this for: general system monitoring (use `gateway-watchdog`), or per-request latency tracking.

## Setup: Cost Tracking Script

Create `~/.hermes/scripts/cost_monitor.py`:

```python
#!/usr/bin/env python3
"""Track Hermes API spending across providers from session logs."""
import json, os, glob, re
from datetime import datetime, timedelta
from collections import defaultdict
from pathlib import Path

HERMES_HOME = Path(os.environ.get("HERMES_HOME", os.path.expanduser("~/.hermes")))
SESSIONS_DIR = HERMES_HOME / "sessions"
COST_LOG = HERMES_HOME / "logs" / "costs.jsonl"

# Provider pricing per 1M tokens (input, output) — update as needed
PRICING = {
    "anthropic": {
        "claude-sonnet-4": (3.00, 15.00),
        "claude-haiku-4-5": (1.00, 5.00),
        "claude-opus-4": (15.00, 75.00),
    },
    "openai": {
        "gpt-4o": (5.00, 15.00),
        "gpt-4o-mini": (0.15, 0.60),
    },
    "openrouter": {
        "deepseek/deepseek-v4-pro": (2.00, 8.00),
        "nousresearch/hermes-4-70b": (1.50, 6.00),
    },
    "xai": {
        "grok-3": (3.00, 15.00),
        "grok-3-mini": (1.00, 5.00),
    },
}

def get_cost(provider, model, input_tokens, output_tokens):
    """Calculate cost from token counts."""
    if provider not in PRICING:
        # Unknown provider — find matching key
        for key in PRICING:
            if key in provider.lower():
                provider = key
                break
        else:
            return None

    # Try exact match first, then partial
    pricing = None
    if model in PRICING[provider]:
        pricing = PRICING[provider][model]
    else:
        for model_key, p in PRICING[provider].items():
            if model_key in model:
                pricing = p
                break

    if not pricing:
        return None

    in_price, out_price = pricing
    cost = (input_tokens / 1_000_000) * in_price + (output_tokens / 1_000_000) * out_price
    return round(cost, 6)


def scan_session(session_path):
    """Extract token usage and cost from a session JSON."""
    try:
        with open(session_path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, IOError):
        return []

    if "messages" not in data:
        return []

    results = []
    for msg in data["messages"]:
        if msg.get("role") != "assistant":
            continue
        usage = msg.get("usage") or msg.get("token_usage") or {}
        if not usage:
            continue

        input_tokens = usage.get("input_tokens", 0) or usage.get("prompt_tokens", 0)
        output_tokens = usage.get("output_tokens", 0) or usage.get("completion_tokens", 0)

        provider = msg.get("provider", "unknown")
        model = msg.get("model", "unknown")

        if not input_tokens and not output_tokens:
            continue

        cost = get_cost(provider, model, input_tokens, output_tokens)
        results.append({
            "ts": msg.get("timestamp", ""),
            "provider": provider,
            "model": model,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "cost": cost,
        })

    return results


def main(days=7):
    """Scan recent sessions and report costs."""
    cutoff = datetime.now() - timedelta(days=days)
    sessions = sorted(glob.glob(str(SESSIONS_DIR / "session_*.json")))

    totals = defaultdict(lambda: {"input_tokens": 0, "output_tokens": 0, "cost": 0.0, "calls": 0})
    provider_totals = defaultdict(lambda: defaultdict(float))
    daily = defaultdict(float)

    for sp in sessions:
        mtime = datetime.fromtimestamp(os.path.getmtime(sp))
        if mtime < cutoff:
            continue

        for entry in scan_session(sp):
            key = f"{entry['provider']}/{entry['model']}"
            totals[key]["input_tokens"] += entry["input_tokens"]
            totals[key]["output_tokens"] += entry["output_tokens"]
            totals[key]["cost"] += entry["cost"] or 0
            totals[key]["calls"] += 1

            provider_totals[entry["provider"]]["cost"] += entry["cost"] or 0

            day = entry["ts"][:10] if entry["ts"] else mtime.strftime("%Y-%m-%d")
            daily[day] += entry["cost"] or 0

    # Print report
    total_cost = sum(t["cost"] for t in totals.values())
    print(f"📊 API Cost Report (last {days} days)")
    print(f"   Total: ${total_cost:.3f}")
    print(f"   Daily avg: ${total_cost/days:.3f}")
    print(f"   30-day projection: ${(total_cost/days)*30:.2f}")
    print()
    print("By Model:")
    for key in sorted(totals.keys(), key=lambda k: totals[k]["cost"], reverse=True):
        t = totals[key]
        print(f"  {key}: ${t['cost']:.3f} ({t['calls']} calls, {t['input_tokens']:,} in / {t['output_tokens']:,} out)")
    print()
    print("By Provider:")
    for prov in sorted(provider_totals.keys(), key=lambda p: provider_totals[p]["cost"], reverse=True):
        print(f"  {prov}: ${provider_totals[prov]['cost']:.3f}")
    print()
    print("Daily:")
    for day in sorted(daily.keys()):
        bar = "█" * min(int(daily[day] * 10), 50)
        print(f"  {day}: ${daily[day]:.2f} {bar}")

    # Determine alert status
    monthly_est = (total_cost / days) * 30
    alert = ""
    if monthly_est > 200:
        alert = "🔴 CRITICAL: 30-day projection ${:.2f} exceeds $200!".format(monthly_est)
    elif monthly_est > 100:
        alert = "🟡 WARNING: 30-day projection ${:.2f} exceeds $100".format(monthly_est)
    elif monthly_est > 50:
        alert = "🟢 NOTE: 30-day projection ${:.2f}".format(monthly_est)

    if alert:
        print(f"\n{alert}")
    else:
        print()

    # Return for cron job usage
    return {
        "total_cost": total_cost,
        "monthly_projection": (total_cost / days) * 30,
        "alert": alert,
        "by_provider": dict(provider_totals),
        "by_model": {k: dict(v) for k, v in totals.items()},
    }


if __name__ == "__main__":
    import sys
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    main(days)
```

Save this as `~/.hermes/scripts/cost_monitor.py` and make it executable:

```bash
chmod +x ~/.hermes/scripts/cost_monitor.py
```

## Usage

```bash
# View last 7 days
python3 ~/.hermes/scripts/cost_monitor.py

# View last 30 days
python3 ~/.hermes/scripts/cost_monitor.py 30

# View last 1 day (quick check)
python3 ~/.hermes/scripts/cost_monitor.py 1
```

## Cron Job: Daily Cost Alert

Create a cron job that runs the script and alerts you:

```
Schedule: 0 9 * * * (daily at 9am)
Prompt: |
  Run: python3 ~/.hermes/scripts/cost_monitor.py 7
  
  Read the output. If the 30-day projection exceeds $100, format it as a Telegram alert with:
  - Total spent in last 7 days
  - 30-day projection
  - Breakdown by provider
  - Any single model that dominates spend
  
  If projection is under $100, respond with a brief emoji status:
  💰 API spend: $X this week, ~$Y/mo projected. All good.
  
  Toolsets needed: terminal
  Deliver: telegram
```

Or use `hermes cron create "0 9 * * *"` with that prompt.

## Manual Budget Check

For a quick ad-hoc check without the script:

```bash
# Anthropic: check usage at console.anthropic.com
# OpenRouter: check at openrouter.ai/activity
# X API: xurl doesn't expose billing — check developer.x.com Portal → Billing
```

## Common Pitfalls

1. **Pricing changes.** Providers update pricing. Update the `PRICING` dict in the script periodically.

2. **Token counting varies by provider.** Some sessions may not include usage data (depends on provider API response). The script handles missing data gracefully.

3. **Cron model mismatch.** If you switch providers, old cron jobs may still use the old model's pricing. Update cron job model settings with `hermes cron edit`.

4. **X API costs aren't token-based.** The cost monitor script only tracks LLM API costs. X API billing is request-count-based and must be checked manually in the X Developer Portal.

5. **OpenRouter pricing passthrough.** OpenRouter models may have different pricing than direct provider. Use OpenRouter's published pricing.

## Verification Checklist

- [ ] Script runs: `python3 ~/.hermes/scripts/cost_monitor.py 1`
- [ ] Shows costs for each provider you use
- [ ] 30-day projection is reasonable
- [ ] Cron job created and delivering to Telegram
- [ ] Pricing dict updated for your specific models
