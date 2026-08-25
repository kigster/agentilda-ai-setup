---
description: "Print every plan folder, its state, and its pull requests"
allowed-tools:
  - Bash(agentilda:*)
---

# Plan status

```!
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v agentilda >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
agentilda list-plans $ARGUMENTS
```

Read-only. Interpret the table using the status vocabulary in [`context/feature-building/agentilda.md`](../context/feature-building/agentilda.md), never a copy of it.

Report only what the table says. A folder's emoji is a claim about its contents; if the user asks why a state looks wrong, that is `/plan-resync-dirs`.
