---
description: "Create a pull request from the current branch, titled to match its plan"
allowed-tools:
  - Bash(~/.agents/scripts/spec-plan-build *)
  - Bash(./.agents/bin/create-branch-name)
  - Bash(spec-plan-build *)
  - Bash(just *)
  - Bash(make *)
  - Bash(git *)
  - Bash(gh *)
  - Bash(mdformat *)
---

# Create Pull Request

Turn the current work into atomic commits and a pull request, with as few questions and steps as possible. Reconcile these instructions with `~/.agents/AGENTS.md`; that file wins on any contradiction (commit-message format in particular). Prefer sensible defaults over asking; ask only when a choice is destructive or genuinely ambiguous.

## 0. Find the plan this work belongs to

If the repository has a `.plans/` directory, **the pull request title is not free-form** — it carries the plan number that `pull-requests.md`, the branch and the merged history all join on.

```bash
spec-plan-build status          # what plans exist, and their state
```

Resolve the plan from the branch name first (`<user>/NNN.MM-slug`), then from the diff, and **only** when the diff touches exactly one plan folder.

- **One plan resolved** → the title is `[NNN.MM](X) Folder Title Cased`, where `X` is the next unused letter for that plan. A plan's first pull request is `(A)`, its second `(B)`, and so on. The words after the letter are the folder slug title-cased — `002.00-⭐️-tenancy-households` gives `[002.00](A) Tenancy Households`.
- **No plan resolves** and the work genuinely implements no specification — a dependency bump, CI configuration, a hotfix, developer tooling → the title is `[dev] <description>`.
- **No plan resolves and you cannot assert it implements none** → `[none] <description>`. That marker claims nothing; it records a question somebody still has to answer.
- **Several plans, or an ambiguous one** → stop and ask. Do not pick. A wrong number does not announce itself: it files the work under a plan that did not do it and leaves the plan that did looking untouched.

Never invent `[dev]` to escape an unresolved lookup. Asserting "this belongs to no specification" is a claim about intent, and it is the author's to make — and once made, nobody reopens it. `[none]` is the honest marker for a lookup that failed.

## 1. Assess

Run `git status` and look at both staged and unstaged changes.

- Clean tree on `main` → nothing to do; say so and stop.
- Clean tree on a feature branch with commits ahead of `origin/main` → skip to step 5 (pull request from the branch as-is).
- Otherwise there are changes to commit → continue.

## 2. Branch (only if on `main`)

If the work belongs to a plan, name the branch after it so the number carries itself: `<user>/NNN.MM-slug`, matching the plan folder. Otherwise run `~/.claude/branch-name.sh <a few words>` and capture STDOUT — that is the branch name (the script talks to the user via STDERR/STDIN). Create it with `git checkout -b <branch-name>`.

## 3. Stage and verify

- If the user deliberately staged a subset, respect it. Otherwise `git add -A`.
- Run the project's checks **once**, using the first that exists: `just check-all`, `just ci`, `just test`, or `make test`. Run the formatter if one exists (`just fmt` / `just format` / `make format`) and re-stage anything it touched.
- On failure: show the output and ask whether to fix or abort. Non-destructive fixes are auto-approved.

## 4. Commit

Review `git diff --cached`. One logical change per commit:

- Single conceptual change → one commit.
- Clearly independent changes → split by `git reset` and selective `git add`. Keep everything on this one branch unless the user asks for separate pull requests.

Write the message per AGENTS.md: imperative 50-character subject, body only when the change needs explaining. **Leave the `[NNN.MM](X)` prefix out of commit subjects** — it is a join key for pull request titles, and repeating it on every commit eats the 50 characters without adding anything.

Then `git push -u origin <branch-name>`.

## 5. Create the pull request

Analyse `git diff origin/main...HEAD` and write the description to a temp file:

- Top line: `# <pr-title>` — the same title from step 0.
- A short **Summary**. When the work implements a plan, quote that plan's `## Goal` rather than paraphrasing it: a paraphrase is a second copy that drifts.
- A **Plan** section naming the folder, so a reviewer can find the specification: `` Implements `002.00-⭐️-tenancy-households`. ``
- Then only the sections that add real information (Description, Motivation, Testing, Backwards Compatibility). Skip empty boilerplate. No emojis.
- GitHub alerts (`> [!NOTE]` etc.) need a blank `>` line after the marker, or the next step merges the body onto it and breaks the rendering.

Normalise it: confirm `mdformat --version` lists the `mdformat-gfm` and `mdformat_tables` plugins (correct install: `uv tool install mdformat --with mdformat-gfm --with mdformat-tables`; a plugin-less mdformat mangles GFM tables — do not use it), then run `mdformat --wrap no "<pr-description>"`.

Create it:

```bash
gh pr create -a @me -B main -t "<pr-title>" -F "<pr-description>"
```

Show the user the URL it prints.

If `gh` fails on authorisation: save the normalised description as `PR.md` in the project root and print the compare URL (`https://github.com/<owner>/<repo>/compare/main...<branch-name>`) so the user can open it in a browser.

> [!NOTE]
> An invalid `GH_TOKEN` in the environment shadows a working keyring login and makes `gh` fail **silently** — exit 0, no output. If `gh` returns nothing, check `gh auth status` before concluding anything about the repository.

## 6. Record it against the plan

If the work implements a plan, add the pull request to that folder's `pull-requests.md` so the plan's state can advance:

```bash
spec-plan-build resync dirs      # then --commit once the table is written
```

A ✅ folder with an open pull request is a lie the tooling will catch; a 🟡 folder whose pull requests are all merged is one it will fix.

______________________________________________________________________

## Doing this for many plans at once

`spec-plan-build run --commit --push-pr` does all of the above for every plan that an agent finished, using the same title convention and the same `gh pr create` invocation. Use this command for one branch by hand; use that one when a whole round of agent work is ready to publish.
