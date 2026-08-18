# `~/.agents` — Konstantin Gredeskoul's AI setup

A vendor-neutral home for the instructions, context, skills and tooling that
several different AI coding agents share, plus **spec-plan-build**: a small Ruby
system that keeps a project's specifications, plans and pull requests joined up,
and can drive specialist agents over them in parallel.

```bash
git clone <this repo> ~/.agents
cd ~/.agents
bundle install
bin/setup            # symlinks into ~/.claude; --dry-run to preview
direnv allow .       # puts bin/ and scripts/ on PATH
```

______________________________________________________________________

## What is in here

| Path | What it is |
| :--- | :--------- |
| `AGENTS.md` | The instructions every agent reads. Symlinked to `~/AGENTS.md` and `~/.claude/CLAUDE.md` |
| `context/` | Durable reference an agent loads on demand — languages, databases, conventions |
| `agents/` | Specialist definitions for the multi-agent harness |
| `skills/` | Claude skills. Symlinked one-by-one into `~/.claude/skills/` |
| `bin/` | **Bash** executables |
| `scripts/` | **Ruby** executables |
| `lib/spec_plan_build/` | The library behind `spec-plan-build` |
| `spec/` | RSpec suite |

`bin` holds shell and `scripts` holds Ruby deliberately: `standardrb` then has a
directory it must lint and one it can ignore entirely, and neither has to be
configured around the other. `.envrc` puts both on `PATH`.

### Vendor neutrality

`AGENTS.md`, `context/` and `scripts/` are portable — any agent that can read a
file and run a command uses them. `skills/` is Anthropic's format and is only
installed for Claude. `bin/setup` never replaces a real file or directory, so
running it against an existing `~/.claude` is safe; it reports conflicts and
skips them.

______________________________________________________________________

## Spec → Plan → Build

Every project keeps its plans in a `.plans/` directory. Each feature gets one
folder, and **the folder's name is its state**.

```
.plans/000.00-⚪️-initial-spec
       001.00-✅-dev-foundation
       001.01-✅-schedule-k1-backfill   ← shipped between 001 and 002,
       002.00-⭐️-tenancy-households        specified afterwards
```

Three phases, each with a file that proves it happened:

| Phase | State | The file that proves it |
| :---- | :---- | :---------------------- |
| **spec** | ⚪️ New | `spec.md` |
| **plan** | ⭐️ Ready | `plan.md` |
| **build** | 🟡 → ✅ | `pull-requests.md` |

A folder may not claim a phase whose file is missing. That is not a convention
anyone has to remember — it is a state machine with guards, and the tool refuses
transitions whose requirements do not hold.

**The full conventions are generated, never hand-written:**

```bash
spec-plan-build docs -o context/feature-building/spec-plan-build.md
```

The status vocabulary, the transition table and the numbering rules live in
`lib/spec_plan_build/lifecycle.rb` and the document is derived from them. This
system previously had three hand-maintained copies of that table and they
disagreed — the folder-creation script could mint statuses the reader did not
recognise, and could not mint six that it required.

### The number is an identity

`NNN.MM`, always. `000.00` is the first plan of a project; after that it is the
highest major plus one. `MM` is `00` for an ordinary plan and `01`–`99` for a
**retroactive** one — work that shipped with no specification and was documented
afterwards.

`001.01` is a *sibling of 001 that arrived later*, not a part of it.

The number is set once and never changes: branch names, pull request titles and
every `pull-requests.md` join on it, and renumbering breaks all of them
silently. `status` reports any number claimed by two folders.

______________________________________________________________________

## Day to day

```bash
spec-plan-build create tax rule dsl          # 003.00-⚪️-tax-rule-dsl
spec-plan-build create --after 002 k1 sync   # 002.01-⬜️-k1-sync (retroactive)
spec-plan-build status                       # the table; exits 1 if a name lies
spec-plan-build resync dirs                  # folder emoji vs folder contents
spec-plan-build resync prs                   # [NNN.MM] prefixes on PR titles
spec-plan-build docs                         # regenerate the conventions
```

**Everything that writes is a dry run until `--commit`.** Folder names and pull
request titles are things other people join on; changing one silently is how
work ends up filed under a plan that did not do it.

### `resync dirs`

Renames folders whose emoji their contents do not support — a ⚪️ that has grown
a `plan.md` becomes ⭐️; a ✅ with an open pull request is walked back to 🟡. It
records *why* for each rename, and it is idempotent.

It will never reclassify between ⭕️ Blocked and 🅱️ Product Blocked. Those share
an invariant on purpose — both mean "a human must decide" — and only the folder
name records *which* human.

### `resync prs`

Reads the branch name first, then the diff, and only when the diff touches
exactly one plan. Anything ambiguous is **reported and never edited**, even with
`--commit`. A pull request that resolves to no plan is proposed as `[DEV.00]`
and marked *assumed*, because asserting "this implements no specification" is
the author's call, not the tool's.

Requires `gh`. If `gh` prints nothing while exiting zero — the signature of an
invalid `GH_TOKEN` shadowing a working keyring login — the tool says so rather
than reporting an empty repository.

______________________________________________________________________

## The multi-agent harness

Specialists are defined in `agents/*.md`. The frontmatter routes them; the body
is the prompt.

| Agent | Handles | Advances to | Does |
| :---- | :------ | :---------- | :--- |
| `spec-writer` | ⚪️ ⬜️ | ⭐️ | grills and writes `spec.md`, or blocks with numbered questions |
| `planner` | ⭐️ | 🟡 | decomposes into concurrently-executable work units |
| `implementer` | 🟡 | ✅ | builds one work unit, source and tests |
| `reviewer` | any | — | adversarial; writes nothing, returns a verdict |

```bash
spec-plan-build run                  # dry run: who would take what
spec-plan-build run --commit         # one git worktree per plan, in parallel
spec-plan-build run --commit -j 4    # …four at a time
spec-plan-build run --isolation shared   # one tree, serial; no git needed
```

### Isolation, and why it is the default

Under `--isolation worktree` each plan gets **its own git worktree on its own
branch**, named `<user>/NNN.MM-slug`. Agents on different plans then share
nothing, and the round runs genuinely in parallel — `cores - 2`, capped at 12.

Two agents editing one checkout produce no git conflict: same branch, same
files, so the last writer simply wins and the loser's work vanishes with nothing
anywhere to say it happened. A lock coordinates a shared tree; a worktree
removes the sharing. **Concurrency is therefore refused without isolation** —
`--isolation shared` forces one job.

The branch name is not decoration: `<user>/002.00-slug` is exactly what
`resync prs` reads first, so the plan number carries itself from worktree
creation to a merged pull request with nobody having to remember it.

Worktrees an agent left untouched are pruned. Dirty ones are kept — they are the
output. Review one with `git -C <repo>.worktrees/<plan> diff`.

### When it stops

The loop ends at a **fixed point** — a round in which no plan changed state —
after two consecutive dry rounds, or at the `--rounds` ceiling. `settled?`
reports when every plan is done or deliberately parked.

Progress is read from disk, never from what an agent claims: after each attempt
the runner re-runs `resync dirs` and re-reads the folder name, so an agent that
reports success but wrote nothing shows as `no change`.

**Blocked plans are never assigned to anyone.** ⭕️ and 🅱️ mean a human decides;
an agent that could move them would make the states meaningless. They are
reported at the end with a pointer to their `blocked.md`.

### The autonomy boundary

Agents may read anything and write source, tests and a plan's own markdown.
They may **not** commit, push, or create or edit a pull request.

That is enforced twice: `--disallowedTools` before, and a check that `HEAD` has
not moved after. A round that committed is reported as a failure. A prompt is a
request; a check is a guarantee, and only one of the two survives a model
deciding it knows better.

______________________________________________________________________

## Development

```bash
just              # pick a recipe
just test         # rspec
just lint         # standardrb (reports; never rewrites)
just format       # standardrb --fix, then mdformat
just ci           # lint + coverage
just doctor       # what bin/setup would link, touching nothing
```

CircleCI runs the suite and the linter, and asserts `bin/setup` reaches a fixed
point by running it twice and diffing — the bug it exists to prevent is drift
going unnoticed, not a first run failing.

______________________________________________________________________

© 2026 Konstantin Gredeskoul
