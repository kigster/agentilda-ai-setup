---
description: "Regenerate the conventions document from the state machine itself"
argument-hint: "[-o <path>]"
allowed-tools:
  - Bash(agentilda:*)
  - Bash(mdformat:*)
  - Bash(just:*)
---

# Regenerate the conventions document

```!
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v agentilda >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
command -v mdformat >/dev/null || export PATH="$HOME/.local/bin:$PATH"
cd "$HOME/.agents" || exit 1
agentilda docs $ARGUMENTS && mdformat --wrap no context/feature-building/agentilda.md
```

> [!IMPORTANT]
> Both steps, always. The generator hard-wraps prose and emits unpadded tables; `mdformat --wrap no` is what puts the file into the shape that is committed. Running `agentilda docs` alone produces a ~160 line diff that is pure formatting churn and nothing else. This mirrors the `docs` recipe in the `justfile` — in this repo, `just docs` does exactly the same two steps.

The states, the emoji and the transition table are emitted from the state machine in `lib/agentilda`, so this file is a build artefact. Never hand-edit it, and never quote a copy of it elsewhere — three copies of the same table quietly disagreeing is the condition it was written to end.

Show the user `git diff` afterwards. An empty diff means the documentation was already in step with the code, which is the expected outcome most of the time.
