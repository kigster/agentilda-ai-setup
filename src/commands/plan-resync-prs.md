---
description: "Add missing [NNN.MM] prefixes to pull request titles (dry run first)"
argument-hint: "[--state open|closed|merged|all]"
allowed-tools:
  - Bash(agentilda:*)
---

# Resync pull request titles

```!
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v agentilda >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
agentilda resync prs $ARGUMENTS
```

That was a **dry run** — `--commit` defaults to false, so no pull request title has been changed yet. `--state` defaults to `all`.

Show the user the proposed retitles, then commit once they agree:

```bash
agentilda resync prs --commit
```

> [!NOTE]
> This edits titles on GitHub. An invalid `GH_TOKEN` in the environment shadows a working keyring login and makes `gh` fail silently — check `gh auth status` before concluding the tool found nothing to do.
