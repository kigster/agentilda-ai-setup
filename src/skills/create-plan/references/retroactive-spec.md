# Retroactive specifications — the provenance line

A plan numbered `NNN.MM` where `MM > 0` documents work that **already shipped**.
Its `spec.md` must open by saying so.

## Why this is not optional

A specification's form carries a claim: that somebody thought this through
before it was built. Writing a `spec.md` dated today and filing it as an
ordinary plan makes that claim falsely — the same defect as a sign-off nobody
gave. The document would read, to anyone opening it in a year, as evidence of a
decision that was never made.

The number already carries the fact (`MM > 0`), but a number is easy to miss and
easy to misread as containment. The opening line makes it unmissable, and it is
the part that survives being copied, quoted or exported.

## The line

Put this immediately after the H1, before anything else:

```markdown
# Spec 018.01 — Verify against filed returns

> [!NOTE]
> **Written retroactively on 2026-08-17.** This documents work that shipped in
> #41 and #43, merged between plan 018 and plan 019. It describes what exists;
> it does not record a decision taken in advance.
```

Three things, all load-bearing:

1. **The date it was written**, not the date the work shipped.
2. **The pull requests it describes**, by number. These are the evidence, and
   they are what a reader checks the document against.
3. **The explicit disclaimer.** "Describes what exists" is the whole point.

## Choosing the anchor

`--after NNN` puts the plan in the gap following plan `NNN`. Choose `NNN` by
**when the work merged**, not by what it is about:

```bash
git log --diff-filter=A --format='%ad %s' -- .plans/018* .plans/019*
gh pr view 41 --json mergedAt
```

If the pull requests merged after 018's folder was created and before 019's, the
anchor is 018. Mechanical and auditable.

Anchoring by topic instead — "this is really about tenancy, so it belongs near
003" — invites an argument nobody can settle, and it is the wrong question: the
decimal is a **slot in time**, not a claim about subject matter.

## What does not deserve one

Most unmatched pull requests. The test is whether **somebody would need to read
it**: a capability with behaviour, an interface, or invariants that are not
obvious from the code.

"Fix a typo", "remove dead code" and "bump a dependency" are `[dev]` and
always were. Backfilling those produces an index that is longer without being
more informative, which makes the real plans harder to find.

## The lifecycle of a retroactive plan

It is born ⬜️ **Retroactive** — the feature is live, but has neither a
specification nor a plan. As you write it up:

| You write | It becomes |
| :-------- | :--------- |
| `spec.md` with the provenance line | ⚪️ New |
| `plan.md` describing what was actually built | ⭐️ Ready |
| `pull-requests.md` listing the merged PRs | ✅ Done |

Run `spec-plan-build resync dirs` after each, rather than renaming by hand.
