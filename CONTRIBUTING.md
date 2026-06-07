# Contributing to Hermes Hooks

If you've built something that made your Hermes setup more reliable, package it up and PR it in.

## What Makes a Good Hook

A good hook is:

- **Generalized.** Strip out your IPs, usernames, tokens, and specific paths. Use placeholders like `YOUR_VPS_IP` or `~/.hermes/`.
- **Battle-tested.** You've run it in production for at least a week without issues.
- **Self-contained.** One skill/script = one problem solved. Don't bundle unrelated things.
- **Documented.** Every script has comments explaining what it does. Every skill has a `## When to Use` section.

## Adding a Skill

1. Create `skills/<your-skill-name>/SKILL.md`
2. Follow the Hermes skill format (see existing skills for examples)
3. Required frontmatter: `name`, `description`, `version`, `author`, `license`, `metadata.hermes.tags`
4. Keep SKILL.md under 15k chars (split into `references/` files if larger)
5. Test it: copy to `~/.hermes/skills/` and verify with `/skill your-skill-name`

## Adding a Script

1. Add to `scripts/` with a `.sh` extension
2. Make it executable: `chmod +x scripts/your-script.sh`
3. Include a header comment explaining: what it does, how to configure it, how to schedule it
4. Use `set -euo pipefail` for bash scripts
5. Hardcode nothing user-specific — use variables at the top of the file

## Adding a Cron Template

1. Add to `cron/templates/README.md` under the appropriate section
2. Include: schedule, prompt, toolsets, delivery target
3. For `no_agent` templates, include the full script inline

## Commit Style

```
type: short description

Optional body with details.
```

Types: `feat:` (new hook), `fix:` (bug fix), `docs:` (README, comments), `refactor:` (restructure).

## Before You PR

- [ ] No personal IPs, usernames, or tokens in files
- [ ] Scripts have `chmod +x`
- [ ] Skills follow the frontmatter convention
- [ ] README updated if adding a new top-level skill
- [ ] Tested on your own Hermes setup
