---
description: "Run specialist agents over the spec's research until plan has enough to converge"
argument-hint: "[--agent NAME] [--rounds N] [-j N] [--isolation worktree|shared]"
allowed-tools:
  - Bash(spec-plan-build:*)
---

# Run the specialist agents

```bash
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v spec-plan-build >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
spec-plan-build run $ARGUMENTS
```

**Do not run this without confirming scope first.** It loops specialist agents over every eligible plan until a round changes nothing, defaulting to `worktree` isolation, a ceiling of 10 rounds, and `--commit` off.

Establish three things before starting:

1. **Which plans.** `/plan-status` first. Narrow with `--agent NAME` when the user wants one specialist rather than the whole cast.
1. **Whether it may write.** Without `--commit` it is a dry run. Add `--commit` only on an explicit yes. With `--isolation worktree` (the default), a finished branch is pushed and its pull request opened automatically once `--commit` is set — pass `--dont-push-anything` when they want the work left uncommitted instead.
1. **How much parallelism.** `-j` costs a worktree per job.

Report what each round changed, not just the final state — a run that converged because an agent kept failing looks identical to one that converged because the work was done.
