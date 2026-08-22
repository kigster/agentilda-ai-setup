# [NNN.MM] [Feature Name] — Blocked

> [!CAUTION]
> This plan **cannot proceed** until a human decides the questions below.
> It is not deferred (we could proceed and chose not to) and not rejected (we
> decided never). It is stopped.

**Status:** ⭕️ Blocked — an engineer or the CTO must decide
_or_ 🅱️ Product Blocked — a product manager must decide

Pick one and set the folder emoji to match. The two states are identical to the
tooling on purpose — both mean "a human must decide" — and **only the folder
name records which human**, so nothing can re-derive it later.

**Blocked since:** YYYY-MM-DD
**Blocking:** what cannot start or finish while this stands
**Decision needed from:** a role, and a name if you have one

______________________________________________________________________

## The questions

Number them. They get referenced in conversation, in pull requests and in the
answer, and "the second one" is not a reference.

Keep the `B<n>` at the start of its line, as a heading or on its own. That is
what `spec-plan-build` counts to decide whether this plan is still stopped, and
a question it cannot see cannot stop anything.

### B1. [The question, as a question]

**What we need decided:** one sentence, phrased so that an answer is possible.
A question nobody can answer without more work is a task, not a blocker.

**Why it blocks:** what breaks or gets built wrong if we guess.

**Options, with what each costs:**

| Option | What it means | Cost / risk |
| :----- | :------------ | :---------- |
| A      |               |             |
| B      |               |             |

**Our recommendation:** name one, and say why. A blocker that offers no
recommendation makes the decider do the analysis twice.

**What we will do if we get no answer by [date]:** the default, stated in
advance. This is the difference between a blocker and a stall.

### B2. […]

______________________________________________________________________

## What is already decided

Anything settled that the decider does not need to reopen. Without this,
answering B1 turns into re-litigating the whole spec.

## Answers

An inbox, not a record. Write each answer here as it arrives, dated and
attributed, then run `spec-plan-build unblock NNN --commit`. That hands the
folder to `lando-broker`, which moves the decision into the document the
question was stopping (`spec.md` for what and why, `plan.md` for how and in
what order) and deletes the question from this file along with the answer.

- **B1** — YYYY-MM-DD, [who]: [what was decided, and any constraint that came
  with it]

An entry that names no decider, carries no date, or restates the options
instead of choosing one is not an answer. It stays here, and so does its
question.

Answer in pieces if that is how the answers arrive. Whatever is still open
above keeps the plan blocked, which is true. When the last question is folded
away this file goes with it, and the folder leaves Blocked on the next
`resync dirs` because there is nothing left in it to justify the name.
