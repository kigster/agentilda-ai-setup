---
name: pr-review-respond
description: Answer review comments on your open pull requests, from humans or bots (Copilot, CodeRabbit), fixing what is right and rebutting what is not, then wait for reviews still in flight. Use when asked to respond to, address or handle PR review comments or feedback, or when your pull requests are being reviewed while you work.
---

# Respond to pull request reviews

Your open pull requests are under review, by a human or by another agent, possibly while you work. Every review comment gets an answer in its own thread. Reviewers are often wrong, and a bot reviewer more often still: a comment is a claim to verify against the code, never an order. Agreeing with a wrong comment ships a regression; a clear rebuttal with evidence is as good an answer as a fix.

Everything below goes through `scripts/pr-reviews` in this skill's folder. Call it by its full path, from inside the repository's checkout. It unsets a stale `GH_TOKEN` itself.

## 1. Survey

```bash
start=$(date +%s)
<skill-dir>/scripts/pr-reviews pending
```

`pending` lists every open pull request you authored, each with a `status`:

- `needs-response`: holds `unanswered_threads`, `unanswered_reviews` or `unanswered_comments`. Go to step 2 for each.
- `unreviewed`: nobody has looked yet. Step 3 waits for it.
- `answered`: your reply is the last word everywhere. Nothing to do unless the reviewer comes back.
- `merged` or `closed`: only when you named the PR (`pending <n>`). Report it and leave it: its branch still accepts pushes, and nobody will see them.

Another agent may be answering the same reviews. Re-run `pending <n>` right before you push or reply, and drop whatever someone else answered meanwhile.

No open pull requests at all means there is nothing to wait for: report that and stop.

## 2. Respond to one pull request

### Workspace

Work on the PR's `branch` in a worktree, never in the checkout you were started in, since other agents may share it.

1. `git worktree list` shows whether some worktree already has the branch. If one does, claim it there: `cd <worktree> && alock acquire . "responding to review on #<n>"`. If the claim is refused, another agent is using it: skip this pull request and report it.

1. Otherwise create one and seed it, since a fresh worktree lacks every git-ignored file the suite needs:

   ```bash
   git fetch origin <branch>
   git worktree add ~/.agents.worktrees/<branch-slug> <branch>
   cd ~/.agents.worktrees/<branch-slug> && ~/.claude/bin/setup-worktree
   alock acquire . "responding to review on #<n>"
   ```

1. `git pull --ff-only` so you build on what the reviewer saw plus anything pushed since.

### Triage

Read each unanswered item against the code at `head`, including the files around the line it names. Sort it into one of three verdicts:

- **Fix**: the reviewer is right. Fix it, including the same mistake elsewhere in the diff.
- **Rebut**: the reviewer is wrong, the change is out of scope, or the cost outweighs the benefit. Gather the evidence that shows it: a passing test, the spec or plan line, a measurement, the documentation of the library in question.
- **Answer**: a question that needs no code change.

A claim about what runs (this is evaluated, that is never called, this input is untrusted) is settled by the code that runs it. Cite that line in the reply, or the search that found no such line, and size the fix to it: guarding a path nothing executes is scope creep, not caution.

An `outdated` thread names code that has since changed: check whether the current code still has the problem before choosing.

A review summary (`unanswered_reviews`) often only lists the inline threads it opened. Points it makes that no thread carries are triaged like a thread.

### Fix, check, push

Make every fix for this pull request, then run the project's own checks until they pass: `just lint && just test` where there is a justfile, otherwise whatever the project uses. Commit atomically with an imperative subject of at most 50 characters, then `git push`. Note each fix's short SHA for the replies.

Prove a fix with tests and linters, which run against test databases. The worktree's seeded `.env` points at the developer's real local databases and services, so a recipe that resets, migrates, seeds, imports or drops anything acts on their data, not a copy. When the reviewed code *is* such a recipe (a guard, a reset), exercise it through the test suite, or ask the human to run it.

### Reply

Write each reply body to a file made with `mktemp`, then post it:

```bash
<skill-dir>/scripts/pr-reviews reply <thread_id> "$body"
<skill-dir>/scripts/pr-reviews resolve <thread_id>    # Fix only
```

| Verdict | Reply                                                                       | Resolve |
| ------- | --------------------------------------------------------------------------- | ------- |
| Fix     | `Fixed in <sha>.` plus one line on what changed.                            | Yes     |
| Rebut   | Why the comment does not apply, with the evidence and a link or path to it. | No      |
| Answer  | The answer.                                                                 | No      |

A rebutted or answered thread stays open: whether the reviewer accepts it is theirs to decide.

Review summaries and conversation comments have no thread to resolve. Answer all of them on that pull request in one comment, quoting each point and giving its verdict, SHA or rebuttal:

```bash
<skill-dir>/scripts/pr-reviews comment <n> "$body"
```

A summary whose points are all carried by threads still gets a one-line reply saying so, which marks it answered.

Write replies to the reviewer plainly: what you did, or why not, and nothing else.

### Done when

`pr-reviews pending <n>` reports `answered`, or every item left is one you chose to skip and will report. Release the claim with `alock release .` in the worktree.

## 3. Wait for reviews in flight

Reviewers work concurrently: an unreviewed pull request may get its review in a minute, and a reviewer may answer a rebuttal or review the fix you just pushed. Wait for that rather than exiting:

```bash
<skill-dir>/scripts/pr-reviews wait --deadline $(( start + 1800 ))
```

It polls every 60 seconds and blocks for up to 5 minutes, so give the command at least 6 minutes before the shell times it out (a background run also works).

- **Exit 0**: something new arrived; it prints the fresh `pending` JSON. Go to step 2 for it, then wait again. Each wait starts a fresh 5-minute idle window.
- **Exit 3**: 5 minutes with nothing new, or 30 minutes since `start`. Go to step 4.

## 4. Report

One line per pull request: its number, what you fixed (with SHAs), what you rebutted, what you answered, what you skipped and why, and any still `unreviewed` when you stopped.
