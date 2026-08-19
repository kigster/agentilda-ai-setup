---
description: "Print every plan folder, its state, and its pull requests"
allowed-tools:
  - Bash(spec-plan-build:*)
---

# Plan status

```!
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v spec-plan-build >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
spec-plan-build status $ARGUMENTS
```

Read-only. Interpret the table using the status vocabulary in [`context/feature-building/spec-plan-build.md`](../context/feature-building/spec-plan-build.md), never a copy of it.

Report only what the table says. A folder's emoji is a claim about its contents; if the user asks why a state looks wrong, that is `/plan-resync-dirs`.
