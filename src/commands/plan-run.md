---
description: "Run specialist agents over the plans until nothing changes"
argument-hint: "[--agent NAME] [--plan NNN,...] [--rounds N] [-j N] [--isolation worktree|shared] [--dont-push-anything] [--log PATH]"
allowed-tools:
  - Bash(agentilda:*)
---

# Run the specialist agents

```bash
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v agentilda >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
agentilda run $ARGUMENTS
```

**Do not run this without confirming scope first.** It loops specialist agents over every eligible plan until a round changes nothing, defaulting to `worktree` isolation, a ceiling of 10 rounds, and `--commit` off.

Establish three things before starting:

1. **Which plans.** `/plan-status` first. Narrow with `--agent NAME` when the user wants one specialist rather than the whole cast, and with `--plan NNN,NNN.MM,...` when this is a handoff for specific plans rather than the whole tree — a batch that just created several plans hands off with `--plan`, once, never with a bare `run` per plan created. See `/plan-create`'s "Creating several plans at once" for the shape.
1. **Whether it may write.** Without `--commit` it is a dry run. Add `--commit` only on an explicit yes. With `--isolation worktree` (the default), pushing a finished branch and opening its pull request happens automatically as each one lands — pass `--dont-push-anything` when they want the work left uncommitted instead. **Never `--commit` while a manual agent session is already working a plan in the same tree** — check `alock list`, or ask, first; `run` writes the same folders a person driving an agent by hand would, and two writers on one folder leave no conflict to catch it.
1. **How much parallelism.** `-j` costs a worktree per job.

Report what each round changed, not just the final state — a run that converged because an agent kept failing looks identical to one that converged because the work was done.

It prints a start and finish line per plan as it works (not just a final summary), and always appends the same to a log file — printed at startup, default a per-project file under the system temp dir, override with `--log PATH`. Point the user at it if a long `--commit` run needs checking on from elsewhere: `tail -f <path>`.
