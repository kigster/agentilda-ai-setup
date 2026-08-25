---
description: "Rename plan folders so the name matches their contents (dry run first)"
allowed-tools:
  - Bash(agentilda:*)
---

# Resync plan folder names

```!
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v agentilda >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
agentilda resync dirs $ARGUMENTS
```

That was a **dry run** — `--commit` defaults to false, so nothing above has been renamed yet.

Show the user what it proposes, then run it again with `--commit` once they agree:

```bash
agentilda resync dirs --commit
```

A ✅ folder with an open pull request is a lie this catches; a 🟡 folder whose pull requests are all merged is one it fixes.
