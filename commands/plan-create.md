---
description: "Create the next numbered plan folder from a few words"
argument-hint: "<two to five words describing the feature>"
allowed-tools:
  - Bash(spec-plan-build:*)
---

# Create a plan folder

The words after the command are the plan topic: `$ARGUMENTS`

```bash
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v spec-plan-build >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
spec-plan-build create $ARGUMENTS
```

Pass them **verbatim**. Do not re-word, expand or "improve" them — the slug is an identity that branch names and merged pull request titles join on, and changing it later breaks every link that joins on it.

> [!IMPORTANT]
> `create` writes immediately. Unlike `resync` and `run` it has no `--commit` gate, so there is no dry run to inspect first.

Run it only once the topic is two to five concrete words. If no words were given, or they are vague enough to produce a slug that will mislead later, ask before creating anything — a folder is cheap, a misleading folder name outlives the confusion that produced it.

Afterwards, follow `## The Workflow` in the `create-plan` skill to write `spec.md`.
