---
name: hermes-tweet-safe-patterns
description: Use when running Hermes Tweet with Hermes Agent for X/Twitter reads, monitoring, cron jobs, or approval-gated actions. Covers plugin install, API key checks, safe cron prompts, and when to use Hermes Tweet instead of xurl.
version: 1.0.0
author: Hermes Agent + Xquik
license: MIT
metadata:
  hermes:
    tags: [hermes-tweet, xquik, twitter, x, plugin, monitoring, cron, automation]
    related_skills: [xurl-safe-patterns, credential-sync, gateway-watchdog]
---

# Hermes Tweet Safe Patterns

Production patterns for using Hermes Tweet in Hermes Agent when you need X/Twitter reads, monitoring, or carefully gated actions without xurl OAuth state on the machine running Hermes.

## Overview

Hermes Tweet is a native Hermes Agent plugin for X/Twitter automation through Xquik. It exposes a small toolset:

- `tweet_explore` discovers supported endpoint capabilities without using the network.
- `tweet_read` calls catalog-listed read-only endpoints after `XQUIK_API_KEY` is configured.
- `tweet_action` is disabled unless `HERMES_TWEET_ENABLE_ACTIONS=true`.

This skill focuses on safe installation, cron usage, and choosing the right X/Twitter route for unattended Hermes jobs.

## When to Use

- You need X/Twitter search or monitoring in Hermes cron jobs.
- You run Hermes on a VPS and do not want to copy local xurl OAuth files.
- You want endpoint discovery before making any API call.
- You need write-like actions to be explicit and opt-in.
- xurl works locally, but cron jobs fail because OAuth tokens are missing or stale.

Do not use this for xurl-specific workflows, local browser OAuth debugging, or free-tier browser-only experiments. Use `xurl-safe-patterns` for those cases.

## Install

Install the plugin from GitHub:

```bash
hermes plugins install Xquik-dev/hermes-tweet --enable
```

If the install runs in an interactive terminal, Hermes prompts for `XQUIK_API_KEY` and stores it in the Hermes profile. For headless cron, gateway, or CI setup, set the key in the environment used by that process:

```bash
export XQUIK_API_KEY="xq_YOUR_KEY"
export HERMES_TWEET_ENABLE_ACTIONS="false"
```

Keep `HERMES_TWEET_ENABLE_ACTIONS=false` for unattended reads. Enable it only for a session that is supposed to call write-like, private, monitor, webhook, or job-creation endpoints.

## Verify the Toolset

After installation, restart any long-running Hermes gateway or cron process that should see the plugin.

```bash
hermes plugins list
```

Probe without using the API key:

```bash
hermes -z "Use tweet_explore to find X/Twitter search capabilities. Do not call tweet_read or tweet_action." --toolsets hermes-tweet
```

Probe a read only after `XQUIK_API_KEY` is available:

```bash
hermes -z "Use tweet_explore first, then use tweet_read for a small X/Twitter search. Return 3 concise results. Do not call tweet_action." --toolsets hermes-tweet
```

Expected behavior:

- Without `XQUIK_API_KEY`, `tweet_explore` is still available.
- Without `XQUIK_API_KEY`, `tweet_read` is hidden or unavailable.
- Without `HERMES_TWEET_ENABLE_ACTIONS=true`, `tweet_action` is hidden or disabled.

## Cron Prompt Pattern

Use this prompt shape for read-only social monitoring:

```text
Use the hermes-tweet toolset only.
First call tweet_explore to find the relevant read-only X/Twitter endpoint.
Then call tweet_read with the smallest query that answers the task.
Do not call tweet_action.
If XQUIK_API_KEY is missing, say exactly:
Hermes Tweet read check failed. Set XQUIK_API_KEY for this Hermes gateway or cron process.
Do not output [SILENT] when the read check fails.
```

For scheduled jobs, keep the failure message short enough for Telegram, email, or other gateway delivery.

## Action Opt-In Pattern

Only use actions when the user explicitly asks for a write-like or private operation.

Before calling `tweet_action`:

1. State the exact endpoint or capability returned by `tweet_explore`.
2. State the payload fields that will be sent.
3. Confirm `HERMES_TWEET_ENABLE_ACTIONS=true` is set for this session.
4. Make one call. Do not retry writes in a loop.

Use this prompt clause for action-capable jobs:

```text
Before any tweet_action call, summarize the endpoint and payload.
If HERMES_TWEET_ENABLE_ACTIONS is not true, stop and report that actions are intentionally disabled.
Never call tweet_action for discovery or read-only tasks.
```

## Choosing Hermes Tweet vs xurl

Use Hermes Tweet when:

- A managed API key is easier to operate than OAuth files.
- The same Hermes job must run on WSL, VPS, and gateway processes.
- You want `tweet_explore` to make endpoint discovery explicit.
- You need action tools disabled by default.

Use xurl when:

- You need exact xurl CLI behavior.
- You are debugging X OAuth flows.
- Your automation already depends on local xurl profiles and refresh scripts.

Many setups use both: xurl for local OAuth-heavy workflows, Hermes Tweet for gateway-safe reads and opt-in actions.

## Safety Checklist

- [ ] `hermes plugins list` shows `hermes-tweet` enabled.
- [ ] Gateway or cron process was restarted after changing environment variables.
- [ ] `XQUIK_API_KEY` is set only in the Hermes environment, not pasted into prompts.
- [ ] Read-only cron prompts say `Do not call tweet_action`.
- [ ] `HERMES_TWEET_ENABLE_ACTIONS` remains `false` unless a write-like job needs it.
- [ ] Cron prompts include a clear failure message for missing API keys.
- [ ] Endpoint paths come from `tweet_explore`, not from memory.
