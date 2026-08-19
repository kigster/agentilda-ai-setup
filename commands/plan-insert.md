---
description: "Create a plan folder slotted in after an existing number"
argument-hint: "<NNN[.MM]> <two to five words describing the feature>"
allowed-tools:
  - Bash(spec-plan-build:*)
---

# Insert a plan folder after an existing one

`$1` is the **preceding** plan number. Everything after it is the topic.

```bash
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v spec-plan-build >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
spec-plan-build create --after $ARGUMENTS
```

You give only the number that comes *before* the new folder; the tool works out the rest. `--after 002` yields `002.01`, opening at ⬜️ rather than ⚪️ — that is the retroactive state, for work that shipped without a specification.

Confirm `$1` actually exists first (`/plan-status`). A number that does not resolve files the work under a plan that did not do it, and leaves the plan that did looking untouched. The same verbatim-slug rule as `/plan-create` applies.
