# autonomous-mode

A [Claude Code](https://claude.com/claude-code) skill that switches the agent into extended autonomous work mode.

You are going away for a few hours. The agent inspects the project (code, Git history, TODOs, tests, logs), builds a prioritized task list, then implements, tests and commits on its own. It makes ordinary decisions itself (naming, local architecture, obvious UX, error handling, tests) and only stops for destructive or irreversible ones, which it records as blockers while it keeps working on everything else.

Part of the [koffih skills catalog](https://github.com/koffih/claude-skills).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/koffih/claude-skill-autonomous-mode/main/install.sh | bash
```

This clones the skill into `~/.claude/skills/autonomous-mode`. Run the same command again to update it.

Other options:

```bash
# into the current project only (./.claude/skills)
curl -fsSL https://raw.githubusercontent.com/koffih/claude-skill-autonomous-mode/main/install.sh | bash -s -- --project

# remove
curl -fsSL https://raw.githubusercontent.com/koffih/claude-skill-autonomous-mode/main/install.sh | bash -s -- --uninstall
```

Or by hand:

```bash
git clone https://github.com/koffih/claude-skill-autonomous-mode ~/.claude/skills/autonomous-mode
```

## Use

In a new Claude Code session, from the project directory:

```
/autonomous-mode
/autonomous-mode the checkout flow first
```

The optional text after the command sets the focus; without it the scope is the whole project.

The skill never triggers on its own (`disable-model-invocation: true`): granting this much autonomy is always an explicit choice.

## What it does

- **Starts by inspecting**: `git status`, branches, recent history, docs, TODOs, tests, CI, logs.
- **Works by priority**: blocking bugs and security first, then unfinished features, broken user journeys, planned work, UX/accessibility/SEO on touched areas, useful tech debt.
- **Validates every change**: tests, lint, type checking, build, edge cases, then fixes what it found.
- **Keeps state**: a task list, and an `AUTONOMOUS_PROGRESS.md` file when useful, so a new session can resume.
- **Commits locally** in coherent units. It does not push to shared branches, open pull requests or deploy unless the project instructions already allow it.
- **Asks only for hard-to-reverse decisions** (data deletion, destructive migrations, paid services, secrets, force push, production changes, anything publicly visible) and keeps working on the rest meanwhile.

It widens initiative, not permissions: project instructions (`CLAUDE.md`, `AGENTS.md`) and your Claude Code permission settings still apply.

## Files

| File | Role |
|---|---|
| `SKILL.md` | The instructions Claude follows |
| `references/checklists.md` | UX, security and SEO checklists, read when working in those areas |
| `assets/AUTONOMOUS_PROGRESS.md` | Template for the progress file |
| `install.sh` | Install, update, uninstall |

## License

MIT
