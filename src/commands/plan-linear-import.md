---
description: "Create Linear projects and issues from .plans, via MCP or LINEAR_API_KEY"
argument-hint: "TAX [--since NNN.MM] [--status building,in_review]"
allowed-tools:
  - Bash(agentilda:*)
  - mcp__claude_ai_Linear__list_teams
  - mcp__claude_ai_Linear__list_issue_statuses
  - mcp__claude_ai_Linear__save_project
  - mcp__claude_ai_Linear__save_issue
---

# Import the plans into Linear

Each plan folder becomes a Linear **project**; each `PR-n` work unit inside its `plan.md` becomes an **issue** in that project, carrying the pull requests that implement it. The folder is the source of truth and this runs one way only — nothing in Linear travels back to `.plans`.

```!
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v agentilda >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
agentilda linear import --prefix $ARGUMENTS
```

That was a **dry run**. Nothing has been created.

## Then pick a transport

Both do the same thing. The plan above is what either one applies.

**If `LINEAR_API_KEY` is set**, let the tool do it — it is deterministic, it records what it did, and it runs unattended:

```bash
agentilda linear import --prefix <KEY> --commit
```

**Otherwise, do it yourself through the MCP server.** Re-run with `--format json` and apply the actions in the order they come:

```bash
agentilda linear import --prefix <KEY> --format json
```

Every action is already shaped as the tool call it needs. Take `args` verbatim:

| `kind`    | `op`     | Call                                        |
| :-------- | :------- | :------------------------------------------ |
| `project` | `create` | `save_project` with `args`                  |
| `project` | `update` | `save_project` with `args` (`id` is inside) |
| `issue`   | `create` | `save_issue` with `args`                    |
| `issue`   | `update` | `save_issue` with `args` (`id` is inside)   |
| either    | `skip`   | nothing — it is already in step             |

Rules that matter:

1. **A plan's project before its issues.** An issue names its project by name, and the name has to exist first. Actions arrive in that order already; keep them in it.
1. **Do not invent arguments.** No assignee, no priority, no cycle, no estimate. If `.plans` does not say it, this import does not claim it.
1. **`state` and `labels` are names.** `save_issue` resolves them against the team. If the team has no state by that name, say so and stop rather than guessing at a different column — the mapping is in `Linear::PLACEMENTS`.
1. **Do not file the plans it skipped.** 💩 Scrapped by Review and 😱 Rolled Back are left out on purpose, and the dry run says which plans that cost. Where they belong is the user's call; show them the list rather than picking a column.

## Then write down what you did

The Ruby path records every issue it creates in each plan's `linear.md`, which is what makes the *next* run idempotent. **The MCP path must do the same**, or the next import creates a second copy of everything.

For each plan you touched, write `<plan folder>/linear.md`:

```markdown
# Linear

Team **TAX** · project [003.00 Tenancy: users, households](https://linear.app/…) `aabbccdd`

| Unit | Issue | Title | State | Synced |
| :--- | :---- | :---- | ----: | :----- |
| PR-1 | [TAX-41](https://linear.app/…/TAX-41) | [003.00] PR-1 — RLS substrate | Done | 9f2c1a04 |
```

`Synced` is the `digest` field of the action you just applied, copied verbatim; the project's digest goes in the heading. Copy them, do not compute them — a digest that does not match what the tool would compute makes every future run report an update that changes nothing.

> [!NOTE]
> `--prefix` is the Linear team key: the part before the dash in `TAX-41`. It selects the team; Linear assigns the numbers itself.

> [!WARNING]
> Pull requests that name no work unit their plan declares are reported separately and filed on the project rather than on an issue. That is usually a missing `PR-n` in a pull request title, or a unit the plan never wrote down. Show the user that list — do not attach them by guesswork.
