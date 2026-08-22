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

For a genuinely new feature (no `--after`/`--prs`), `create` already scaffolds `spec.md` with a title and four headings and makes a best-effort attempt at them from project context before opening it. What follows is what to check — or write by hand with `--no-draft` — before the folder is ready for `leah-researcher` or `run`.

## The four headings, and nothing else

```
## What we are trying to achieve
## Why it matters
## What already exists
## What research needs to settle
```

Verbatim, in that order — that is exactly what `create` writes, and it is what `spec-plan-build status` and the agent loop read the folder's state from having. Do not add to the set, and do not rename one to something that reads better; the folder's state is derived from this shape.

- **Never write Goals, Non-Goals or a conclusion.** That is `yoda-writer`'s chapter, written *after* research, not before it. Writing it now decides the answer before the research runs, and a researcher handed a foregone conclusion looks for evidence of it rather than for what is actually true.
- **Never write a `## Research` heading — not even empty.** It is not decoration, it is the state transition: the 🔎 Researched invariant matches any heading beginning with the word "Research" (`## Research`, `### Research`, case-insensitive). Seeding it — even as an empty placeholder — flips the folder to 🔎 the moment `resync dirs` runs next, and the agent loop reads that as "somebody already researched this" and skips `leah-researcher` entirely. The folder ends up *looking* done while nobody has looked.
- **`## What already exists` is the non-delegable section.** Cite specific repo paths, prior plans, and — especially — defects that were already found and fixed. An absent defect looks identical to a defect nobody has researched; if this section doesn't say "this was already fixed in 002.00," `leah-researcher` has no way to tell the difference and will report a closed issue as an open one.
- **One achievement per plan.** If `## What we are trying to achieve` needs two paragraphs to state, it is two plans, not one plan with two goals — `palpatine-planner` decomposes a single goal into work units; it cannot split a goal it was never given as two.

## Creating several plans at once

The mechanics are three commands and do not need a skill of their own — `create`, `status`, `run --plan`. The constraints above are what erode, because nothing on disk enforces them; get them right per plan, then batch the handoff.

1. `spec-plan-build create <words>`, once per plan.
2. Write (or let `create`'s draft attempt) each `spec.md`, following every constraint above.
3. **Verify each one before handing off, not after** — `spec-plan-build status` shows every plan at a glance:
   - `spec.md` exists.
   - Exactly the four `##` headings above, nothing added.
   - No heading beginning with "Research".
   - Status reads ⚪️ New, not 🔎 Researched.
4. Report readiness and print **one** command — do not run it yourself unless asked:
   ```bash
   spec-plan-build run --commit --plan <NNN,NNN,...>
   ```

**One handoff at the end, not N.** `run` with no `--plan` is a whole-tree loop; running it after every single `create` turns N new plans into N overlapping whole-tree loops, each claiming worktrees for plans the others are touching too — the exact concurrency hazard `config/AGENTS.md`'s "Concurrent Agents — Claim Before You Write" warns about, industrialized by a loop instead of a person. `--plan` exists so a batch step can hand off exactly the plans it just made, once.

> [!CAUTION]
> **Never start `--commit` while a manual agent session is already in flight on any plan in that tree — yours or anyone else's.** `run` reads and writes plan folders the same as a person driving an agent by hand would, and two writers on one folder produce no git conflict to catch it — just whichever one wrote last, silently. Check with `bin/agent-lock list` (or ask) before `--commit`, the same as before writing any file in this repository.
