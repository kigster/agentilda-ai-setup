---
description: "Fold answered blocks into a plan's documents and retire blocked.md"
argument-hint: "NNN[,NNN.MM,...] [--commit] [--agent NAME]"
allowed-tools:
  - Bash(agentilda:*)
---

# Drain a blocked plan

```bash
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
command -v agentilda >/dev/null || export PATH="$HOME/.rbenv/shims:$HOME/.agents/scripts:$PATH"
agentilda unblock $ARGUMENTS
```

Hands a ⭕️/🅱️ folder to `lando-broker`, which moves every **answered** question out of `blocked.md` and into the document it was stopping, then deletes `blocked.md` when nothing is left in it. Without `--commit` it prints the questions still open and invokes nothing.

`agentilda run` cannot do this and must not learn how. A blocked plan is waiting on a human, and an autonomous loop that could move it would make the state meaningless. Someone typing this command is the signal that answers arrived; nothing else can produce that signal.

Before running it with `--commit`:

1. **Check the answers are answers.** Each one names who decided, carries a date, and settles the question. A recommendation, a preference, or "leaning towards B" is none of those, and `lando-broker` will leave it and say so. If the user is asking you to unblock a plan whose answers are not written down yet, write them into `blocked.md` as `## A<n>` sections first, each answering the `## B<n>` of the same number, attributed and dated, or say plainly that there is nothing to fold in yet.
1. **Never answer a question on the user's behalf**, and never promote the recommendation inside a block into the decision. That is the entire reason the plan stopped. If the user says "just do what you think is right", ask them to say which option they are choosing, and record them as the decider.
1. **Expect a partial drain.** Two answers out of five is a successful run. The folder stays ⭕️, because it still is blocked.

Afterwards, report which questions were folded and where, and which are still open. If the folder left ⭕️, the plan is back in the ordinary loop and `/plan-run` can take it.
