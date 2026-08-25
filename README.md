# `~/.agents`

[![CircleCI](https://dl.circleci.com/status-badge/img/gh/kigster/dot-agents/tree/main.svg?style=svg&circle-token=CCIPRJ_DrNBun6pLLc988EVbduHJm_9ec6ada64b6bd9406d19ca4e1aa56a249c20087d)](https://dl.circleci.com/status-badge/redirect/gh/kigster/dot-agents/tree/main)

# Konstantin Gredeskoul's AI setup

A vendor-neutral home for the instructions, context, skills and tooling that several different AI coding agents share, plus **agentilda**: a small Ruby system that keeps a project's specifications, plans and pull requests joined up, and can drive specialist agents over them in parallel.

```bash
git clone <this repo> ~/github/you/agentilda   # anywhere; this is not the install
cd ~/github/you/agentilda
direnv allow .              # puts bin/, scripts/ and workflow/exe on PATH

scripts/install-sources     # assemble skills/ and plugins/ from configuration.yml
bin/install                 # copy the result to ~/.agents, then link ~/.claude
```

Two steps, and the checkout is neither of them. `install-sources` builds
`skills/` and `plugins/` in the checkout; `bin/install` copies what it built
into `~/.agents` with every symlink resolved, and then `bin/setup` links
`~/.agents` into `~/.claude` the way it always has. What that buys is a
`~/.agents` made of real files, so the checkout can be moved, renamed or
deleted afterwards and nothing dangles. What it costs is that an edit to
`src/skills/foo` reaches `~/.claude` only when you run it again.

`bin/install --dry-run` previews both steps. `--force` is required to
replace anything already installed, and to replace a `~/.agents` that is
still a symlink to a checkout from the old arrangement.

______________________________________________________________________

## What is in here

| Path                        | What it is                                                                                                                         |
| :-------------------------- | :--------------------------------------------------------------------------------------------------------------------------------- |
| `config/AGENTS.md`          | The instructions every agent reads. Symlinked to `~/AGENTS.md` and `~/.claude/CLAUDE.md`                                           |
| `context/`                  | Durable reference an agent loads on demand: languages, databases, conventions                                                      |
| `src/skills/`               | Skills authored in this repo (committed); folded into `skills/` by `install-sources`                                               |
| `src/commands/`             | Slash commands that wrap `agentilda` with the right guardrails baked in                                                            |
| `skills/`                   | Claude skills, **generated**, one directory per skill, symlinked into `~/.claude/skills/`                                          |
| `plugins/`                  | External plugin bundles (e.g. `pstack`), also generated, not committed                                                             |
| `configuration.example.yml` | Committed template for the git-ignored `configuration.yml`, the list `scripts/install-sources` pulls `skills/` and `plugins/` from |
| `bin/`                      | **Bash** executables. `setup` is a pure symlink reconciler                                                                         |
| `scripts/`                  | **Ruby**: `install-sources`, which runs before there is a bundle to run it in                                                      |
| `workflow/`                 | The `agentilda` gem: `exe/`, `lib/`, `agents/`, `spec/`, and its own Gemfile                                                       |

`bin` holds shell and `scripts` holds Ruby deliberately: `standardrb` then has a directory it must lint and one it can ignore entirely, and neither has to be configured around the other. `.envrc` puts both on `PATH`.

`skills/` and `plugins/` are **not committed**. Both are entirely regenerable from `configuration.yml` plus `skills-mine/` (which is committed, since it's this repo's own work). A skill that went stale with no way to tell where it came from was the exact problem `install-sources` exists to solve:

```bash
scripts/install-sources          # clone what's missing, update the rest
scripts/install-sources -f       # wipe and re-clone every source fresh
scripts/install-sources list     # what's configured, and what's installed from where
```

Add a repo to `configuration.yml` instead of installing something by hand. `type: skills` treats every `SKILL.md`-rooted directory found (at any depth) as its own skill; `type: plugin` installs the whole thing into `plugins/<name>` and, if it carries its own `skills/`, fans those out individually too.

A source that carries more than you want narrows itself with one regular expression, matched against the name each skill installs as:

```yaml
  - name: pstack
    type: plugin
    repo: git@github.com:cursor/plugins.git
    path: pstack
    include_skills: /\A(architect|unslop|why)\z/   # or exclude_skills, never both
```

Tightening a filter takes skills back as well as adding them: the next run unlinks whatever it installed last time and no longer installs, so `skills/` converges on what `configuration.yml` says. `bin/setup` then sweeps the matching dangling links out of `~/.claude/skills`.

### Vendor neutrality

`config/AGENTS.md`, `context/` and `scripts/` are portable — any agent that can read a file and run a command uses them. `skills/` is Anthropic's format and is only installed for Claude. `bin/setup` never replaces a real file or directory, so running it against an existing `~/.claude` is safe; it reports conflicts and skips them.

______________________________________________________________________

## Spec → Plan → Build

This repo comes with an opinionated and formalized workflow for designing product features and moving forward.

Every project keeps its plans in a `.plans/` directory. Each feature gets one folder, and **the folder's name is its state**.

```
.plans/000.00-⚪️-initial-spec
       001.00-✅-dev-foundation
       001.01-✅-schedule-k1-backfill   ← shipped between 001 and 002,
       002.00-⭐️-tenancy-households        specified afterwards
```

Three phases, each with a file that proves it happened:

| Phase     | State    | The file that proves it |
| :-------- | :------- | :---------------------- |
| **spec**  | ⚪️ New   | `spec.md`               |
| **plan**  | ⭐️ Ready | `plan.md`               |
| **build** | 🟡 → ✅  | `pull-requests.md`      |

A folder may not claim a phase whose file is missing. That is not a convention anyone has to remember — it is a state machine with guards, and the tool refuses transitions whose requirements do not hold.

### The lifecycle, step by step

A feature moves through five specialists, one state at a time, never two at once, and never further than its own documents currently justify:

1. **⚪️ New.** `agentilda create tax rule dsl` mints `.plans/003.00-⚪️-tax-rule-dsl/`. For a genuinely new feature it also scaffolds `spec.md` with a title and four fixed headings (*What we are trying to achieve*, *Why it matters*, *What already exists*, *What research needs to settle*), makes a best-effort attempt at them from what the project already has on disk, and opens it. You finish the brief by hand.
1. **🔎 Researched.** `leah-researcher` fans work out across parallel sub-agents and appends spec.md's `## Research` chapter: themes, findings, licensing, a closing `### Findings, Conclusion & References`. Nobody else may write that heading. It *is* the state transition, so an empty one seeds a lie.
1. **⭐️ Planned.** `yoda-writer` turns the brief plus the research into a complete specification: Goal, Non-Goals, In/Out of scope, Open questions, Conclusion. Or it writes `blocked.md` instead, when a question is a human's to answer, not a guess. `palpatine-planner` then decomposes the finished spec into `plan.md`'s non-overlapping work units, sized for independent sub-agents.
1. **🟡 Building → 🟢 Ready for Review.** `luke-implementer` builds one work unit at a time (source and tests, no commits) and opens a pull request titled `[003.00] …` as each lands.
1. **👀 In Review → 🔴 Changes Requested, or ✅ Approved & Merged.** `hansolo-reviewer` reads the diff against the plan and either requests changes (back to 🟢 once addressed) or approves. Nothing merges automatically: approving is reversible and attributable, merging changes a branch everyone else builds on, and that line is enforced in code, not just in the prompt.

Off to the side, at any point: ⭕️/🅱️ **Blocked** (an engineering or product decision only a human can make) and ☢️ **Deferred** or ❌ **Discarded**. Blocked plans are never assigned to an agent by the loop; one that could move them would make the states meaningless. `agentilda states` draws the whole machine, every legal transition included.

Blocks drain by hand, and in pieces. Answers are written into `blocked.md` as they arrive, and `agentilda unblock 003 --commit` hands the folder to `lando-broker`, which folds each answered question into the document it was stopping (`spec.md` for what and why, `plan.md` for how and in what order), deletes it, and deletes the file once nothing is left. `blocked.md` holds open questions and nothing else, so the pass that empties it is the pass that lets the folder out of ⭕️. Three answers out of four is a normal run: the plan stays blocked on the fourth, which is the truth.

### How you invoke it

Both paths end up running the same `workflow/exe/agentilda` binary, which `tilda` is a symlink to. The question is just who's driving.

- **Directly, from a terminal or a script**: `agentilda create …`, `agentilda run --commit`, etc. (see "Day to day" below). This is the whole tool; nothing about it requires Claude.
- **As a Claude Code slash command**, via `src/commands/*.md` (`/plan-create`, `/plan-research`, `/plan-run`, `/plan-status`, `/plan-resync-dirs`, `/plan-resync-prs`, `/plan-docs`, `/plan-insert`, `/plan-linear-import`). Each one is a thin wrapper around the same binary, plus the guardrails that erode if left to memory. `/plan-create` won't seed a `## Research` heading or write Goals ahead of the research. `/plan-run` insists you confirm scope, `--commit`, and parallelism before it runs anything.

Use the slash commands inside a Claude Code session, since they carry the constraints. Use the binary directly for scripting, CI, or any other agent. `skills/` and `workflow/agents/*.md` are a separate concern: those are Claude's general skill/specialist library, not part of invoking `agentilda` itself.

**The full conventions are generated, never hand-written:**

```bash
agentilda docs -o context/feature-building/agentilda.md
```

The status vocabulary and transition table live in `workflow/lib/agentilda/status.rb` and `state_machine.rb`, the numbering rules in `ordinal.rb`, and the document is derived from all three. This system previously had three hand-maintained copies of that table and they disagreed — the folder-creation script could mint statuses the reader did not recognise, and could not mint six that it required.

### The number is an identity

`NNN.MM`, always. `000.00` is the first plan of a project; after that it is the highest major plus one. `MM` is `00` for an ordinary plan and `01`–`99` for a **retroactive** one — work that shipped with no specification and was documented afterwards.

`001.01` is a *sibling of 001 that arrived later*, not a part of it.

The number is set once and never changes: branch names, pull request titles and every `pull-requests.md` join on it, and renumbering breaks all of them silently. `status` reports any number claimed by two folders.

______________________________________________________________________

## Day to day

```bash
agentilda create tax rule dsl          # 003.00-⚪️-tax-rule-dsl
agentilda create --after 002 k1 sync   # 002.01-⬜️-k1-sync (retroactive)
agentilda list-plans                       # the table; exits 1 if a name lies
agentilda resync dirs                  # folder emoji vs folder contents
agentilda resync prs                   # [NNN.MM] prefixes on PR titles
agentilda linear import --prefix TAX   # the plans, as Linear projects and issues
agentilda docs                         # regenerate the conventions
agentilda states                       # the state machine, as a diagram
agentilda run --commit --plan 003      # hand specific plans to the agents
```

**Everything that writes is a dry run until `--commit`.** Folder names and pull request titles are things other people join on; changing one silently is how work ends up filed under a plan that did not do it.

### `resync dirs`

Renames folders whose emoji their contents do not support — a ⚪️ that has grown a `plan.md` becomes ⭐️; a ✅ with an open pull request is walked back to 🟡. It records *why* for each rename, and it is idempotent.

It will never reclassify between ⭕️ Blocked and 🅱️ Product Blocked. Those share an invariant on purpose — both mean "a human must decide" — and only the folder name records *which* human.

### `resync prs`

Reads the branch name first, then the diff, and only when the diff touches exactly one plan. Anything ambiguous is **reported and never edited**, even with `--commit`. A pull request that resolves to no plan is proposed as `[dev]` and marked *assumed*, because asserting "this implements no specification" is the author's call, not the tool's. Where even that cannot be asserted the marker is `[none]`, which claims nothing and leaves the question open.

Requires `gh`. If `gh` prints nothing while exiting zero — the signature of an invalid `GH_TOKEN` shadowing a working keyring login — the tool says so rather than reporting an empty repository.

### `linear import`

Each plan folder becomes a Linear **project**; each `PR-n` work unit inside its `plan.md` becomes an **issue** in that project, carrying the pull requests that implement it. `--prefix` is the team key — the part before the dash in `TAX-41` — and Linear assigns the numbers itself.

It runs **one way**. The folder is the source of truth and Linear is a window onto it; nothing typed into Linear travels back to `.plans`.

The whole decision is made from disk, which is what makes the dry run worth reading: it is not a description of what a push would do, it is the object the push consumes. Each plan then records what it owns in a committed `linear.md`, and that record — a fingerprint per issue — is what makes the second run cost nothing.

Two transports apply the same plan:

```bash
agentilda linear import --prefix TAX --commit        # needs LINEAR_API_KEY
agentilda linear import --prefix TAX --format json   # for /plan-linear-import, over MCP
```

The JSON is shaped as the Linear MCP server's own `save_project` and `save_issue` arguments, so both transports read one contract and cannot drift apart.

Two states — 💩 Scrapped by Review and 😱 Rolled Back — are **not imported at all**. Where they belong on a board is a statement about how a team works, not about the plan, and this tool does not know that. It says so and skips them; deciding is one entry in `Linear::PLACEMENTS`.

A pull request that names no work unit its plan declares is likewise **reported, never guessed at** — filing it under the nearest unit would bury exactly the discrepancy worth seeing.

______________________________________________________________________

## The multi-agent harness

Specialists are defined in `workflow/agents/*.md`. The frontmatter routes them (`handles:`/`advances_to:` are exactly what `agentilda run` reads to decide who takes a plan); the body is the prompt.

| Agent               | Handles | Advances to | Does                                                                |
| :------------------ | :------ | :---------- | :------------------------------------------------------------------ |
| `leah-researcher`   | ⚪️      | 🔎          | fans out parallel research, writes spec.md's `## Research` chapter  |
| `yoda-writer`       | 🔎, 🕰️  | ⭐️          | writes Goal/Non-Goals/Conclusion, or blocks with numbered questions |
| `palpatine-planner` | ⭐️      | 🟡          | decomposes the spec into `plan.md`'s concurrent work units          |
| `luke-implementer`  | 🟡, 🔴  | 🟢          | builds one work unit, source and tests, no commits                  |
| `hansolo-reviewer`  | 🟢, 👀  | ✅          | adversarial review; requests changes or approves, never merges      |
| `lando-broker`      | ⭕️, 🅱️  | ⭐️          | folds answered blocks into spec.md/plan.md; never invoked by the loop |

```bash
agentilda run                              # dry run: who would take what
agentilda run --commit                     # one git worktree per plan, in parallel
agentilda run --commit -j 4                # …four at a time
agentilda run --isolation shared           # one tree, serial; no git needed
agentilda run --commit --plan 003,005.01   # only these plans, see below
agentilda unblock 003                      # what 003 is still waiting on a human for
agentilda unblock 003 --commit             # fold in whatever has been answered
agentilda states                           # the whole machine, as a diagram
```

### Handing off several plans at once with `--plan`

`run` with no `--plan` loops the **whole tree**. That is exactly wrong right after a batch step creates several plans at once: a bare `run` per `create` starts N overlapping whole-tree loops, each claiming worktrees for plans the others are also touching. `--plan NNN,NNN.MM,...` scopes a round to just the plans named, refusing up front if one doesn't exist rather than silently running everything, and it scopes pushing along with it. The shape that works: create every plan, verify each with `status`, then one `run --commit --plan ...` handoff at the end. Full constraints for that shape (the four headings, what a brief must never write, when to block instead of guess) live in `src/commands/plan-create.md`.

### Isolation, and why it is the default

Under `--isolation worktree` each plan gets **its own git worktree on its own branch**, named `<user>/NNN.MM-slug`. Agents on different plans then share nothing, and the round runs genuinely in parallel — `cores - 2`, capped at 12.

Two agents editing one checkout produce no git conflict: same branch, same files, so the last writer simply wins and the loser's work vanishes with nothing anywhere to say it happened. A lock coordinates a shared tree; a worktree removes the sharing. **Concurrency is therefore refused without isolation** — `--isolation shared` forces one job.

The branch name is not decoration: `<user>/002.00-slug` is exactly what `resync prs` reads first, so the plan number carries itself from worktree creation to a merged pull request with nobody having to remember it.

Worktrees an agent left untouched are pruned. Dirty ones are kept — they are the output. Review one with `git -C <repo>.worktrees/<plan> diff`.

### When it stops

The loop ends at a **fixed point** — a round in which no plan changed state — after two consecutive dry rounds, or at the `--rounds` ceiling. `settled?` reports when every plan is done or deliberately parked.

Progress is read from disk, never from what an agent claims: after each attempt the runner re-runs `resync dirs` and re-reads the folder name, so an agent that reports success but wrote nothing shows as `no change`.

**Blocked plans are never assigned to anyone.** ⭕️ and 🅱️ mean a human decides; an agent that could move them would make the states meaningless. They are reported at the end with a pointer to their `blocked.md`.

### The autonomy boundary

Agents may read anything and write source, tests and a plan's own markdown. They may **not** commit, push, or create or edit a pull request.

That is enforced twice: `--disallowedTools` before, and a check that `HEAD` has not moved after. A round that committed is reported as a failure. A prompt is a request; a check is a guarantee, and only one of the two survives a model deciding it knows better.

______________________________________________________________________

## Development

```bash
just              # pick a recipe
just test         # rspec
just lint         # standardrb (reports; never rewrites)
just format       # standardrb --fix, then mdformat
just ci           # lint + coverage
just doctor       # what bin/install would copy and link, touching nothing
```

CircleCI runs the suite and the linter, and asserts `bin/setup` reaches a fixed point by running it twice and diffing — the bug it exists to prevent is drift going unnoticed, not a first run failing.

______________________________________________________________________

© 2026 Konstantin Gredeskoul
