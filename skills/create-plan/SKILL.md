---
name: spec-plan-build
description: "Create and drive a numbered plan folder through the spec → plan → build lifecycle in a project's .plans tree. Use when the user wants to start a new feature, write or grill a specification, turn a spec into an implementation plan, or asks where a piece of work should be documented. Also triggers when the user says 'new plan', 'write a spec for', 'plan this feature', mentions .plans or a plan number like 003, asks to resync plan folders or pull request titles, or wants to document work that already shipped. Useful for both greenfield projects needing their first specification and mature trees where the next plan must slot into an existing sequence."
---

# Spec → Plan → Build

Three phases, each with a file that proves it happened, and a guarded state
machine that refuses to let a folder claim a phase it has not reached.

| Phase     | State       | The file that proves it |
| --------- | ----------- | ----------------------- |
| **spec**  | ⚪️ New      | `spec.md`               |
| **plan**  | ⭐️ Ready    | `plan.md`               |
| **build** | 🟡 → ✅     | `pull-requests.md`      |

> [!IMPORTANT]
> **The conventions are not written here.** The status vocabulary, the numbering
> rules and the transition table live in `~/.agents/lib/spec_plan_build` and are
> emitted by `spec-plan-build docs` into
> [`~/.agents/context/feature-building/spec-plan-build.md`](../../context/feature-building/spec-plan-build.md).
> Read that, never a copy. This system has already had three hand-maintained
> copies of the status table drift apart.

## When to use

- The user wants to start a medium-to-large feature and it needs documenting.
- A specification exists and needs grilling into something unambiguous.
- A signed-off spec needs turning into an executable plan.
- Work shipped with no spec and the gap needs backfilling.
- Folder emoji or pull request titles have drifted and need resyncing.

## When NOT to use

- Small changes: a typo fix, a dependency bump, a hotfix, CI config. Those are
  `[DEV.00]` pull requests and always were. Backfilling them produces an index
  that is longer without being more informative.
- The user is asking a general planning question with no `.plans` tree in sight.
- Writing the pull-request record itself — that is `/create-plan-prs`.

## Required inputs

Before creating anything you need:

1. **The project root**, and whether `.plans` exists.
2. **A topic in two to five words.** It becomes the folder slug and cannot be
   changed later without breaking every link that joins on it.
3. **The problem being solved**, in the user's words, not yours.
4. **For retroactive work only:** which plan the work landed *after*.

If 2 or 3 are vague, grill before creating. A folder is cheap; a folder with a
misleading name is a lie that outlives the confusion that produced it.

## The tool

`spec-plan-build` lives on `PATH` (via `~/.agents/.envrc`). The full path is
`~/.agents/scripts/spec-plan-build` if you need it.

```bash
spec-plan-build create tax rule dsl        # next number, opens at ⚪️
spec-plan-build create --after 002 k1 sync # retroactive: 002.01, opens at ⬜️
spec-plan-build status                     # every plan, its state, its PRs
spec-plan-build resync dirs                # folder emoji vs folder contents
spec-plan-build resync prs                 # [NNN.MM] prefixes on PR titles
spec-plan-build docs -o context/feature-building/spec-plan-build.md
```

**Everything that writes is a dry run until you pass `--commit`.** Run it
without first, show the user what it proposes, and only then commit.

## Workflow

1. **Locate or create `.plans`.** If the project has none and this is a new
   project, the first plan is the project specification itself.

2. **Create the folder with the tool**, never by hand. The number is an
   identity that branch names and merged pull request titles join on, and the
   tool is what knows which number is next.

   For work that already shipped, use `--after NNN`, which takes a retroactive
   slot in the gap rather than pretending the work was specified in advance.

3. **Write `spec.md`, then grill it.** Invoke `/grilling`. Do not stop at the
   first round of answers. The specification is finished when a competent
   implementer could build it without asking you anything.

4. **Extract Goals and Non-Goals explicitly.** Non-goals are the half people
   skip and the half that prevents scope arguments later.

5. **Write `plan.md`.** Structure it so independent agents can work
   concurrently: name the seams, state what each work unit may and may not
   touch, and make ordering constraints explicit rather than implied.

6. **Grill the plan** the same way, then get sign-off.

7. **Resync rather than rename.** When the phase changes, run
   `spec-plan-build resync dirs`. Renaming a folder by hand bypasses every
   guard, which is the whole thing the state machine exists to prevent.

8. **Ask before implementing.** Sign-off on a plan is not permission to build
   it.

## Failure patterns

- **Creating the folder before the topic is clear.** The slug is permanent.
- **Renaming a plan's number.** It is an identity; branch names and merged pull
  request titles join on it, and renumbering breaks all of them silently.
- **Writing a spec that reads as if it were written in advance when it was
  not.** That is fabricated provenance. Retroactive plans take a `.MM` slot and
  open with a dated line naming the pull requests they describe.
- **Restating the status table in a project file.** Run `spec-plan-build docs`.
- **Renaming a folder by hand** instead of letting `resync dirs` do it.
- **Committing a `resync prs` run without reading it.** Titles it could not
  resolve are marked *assumed* and get `[DEV.00]`; asserting "this implements no
  plan" is the author's call, not the tool's.
- **One giant plan.** If it cannot be split into concurrent work units, it is
  probably several plans.
- **Accepting the first answer while grilling.** The first answer is the one the
  user already had; the useful ones come after.

## Output format

A folder `NNN.MM-<emoji>-<slug>` containing `spec.md`, then `plan.md`, then
`pull-requests.md` once building starts. `blocked.md`, `delayed.md` and
`rejected.md` appear only when the corresponding state does — each is required
by its state, and `spec-plan-build status` exits non-zero without it.

## Reference files

- [`references/spec-template.md`](references/spec-template.md) — the
  specification structure, with the Goals/Non-Goals discipline.
- [`references/plan-template.md`](references/plan-template.md) — turning a spec
  into concurrently-executable work units.
- [`references/blocked-template.md`](references/blocked-template.md) — recording
  a block as numbered questions (B1, B2…) addressed to whoever must decide.
- [`references/rejected-template.md`](references/rejected-template.md) —
  recording a terminal rejection, with links to whatever superseded it.
- [`references/retroactive-spec.md`](references/retroactive-spec.md) — the dated
  provenance line a `.MM` spec must open with.
- [`references/pull-requests.md`](references/pull-requests.md) — defers to
  `/create-plan-prs`.
