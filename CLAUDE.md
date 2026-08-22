# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`~/.agents` is Konstantin Gredeskoul's vendor-neutral home for instructions, context, skills and tooling shared across AI coding agents (Claude, Codex, Pi, Grok, etc.), plus **spec-plan-build**: a Ruby CLI that keeps a project's specifications, plans and pull requests joined up, and can drive specialist agents over them in parallel.

`bin/setup` symlinks this repo's shared folders into `~/.claude` (and `AGENTS.md` to `~/AGENTS.md` / `~/.claude/CLAUDE.md`), so a project working elsewhere on the machine sees these skills, agents and context files as if they were local. It never overwrites a real file or directory — conflicts are reported and skipped — and links are relative so the whole tree survives being cloned under a different `$HOME`.

## Commands

```bash
bundle install        # install gems
just doctor            # what `bin/setup` would link, touching nothing
just setup              # actually symlink into ~/.claude (bin/setup)
just relink              # repoint symlinks that aim somewhere else (bin/setup --force)

just lint                # standardrb — reports only, never rewrites
just format               # standardrb --fix, then mdformat on every *.md
just test                  # rspec
just test spec/spec_plan_build/ordinal_spec.rb            # single file
just test spec/spec_plan_build/ordinal_spec.rb -e "some example name"  # single example
just test-coverage         # rspec with SimpleCov; open coverage/index.html
just ci                     # lint + test-coverage (what CircleCI runs)
just lefthook               # run all pre-commit hooks against the whole tree

just docs                    # regenerate context/feature-building/spec-plan-build.md from the state machine
```

`standard`, not `rubocop`, is the linter (see Gemfile comment: "standard is rubocop with the arguing removed"). `standardrb` ignores `skills/`, `plugins/`, `coverage/`, `tmp/` (see `.standard.yml`); `lib/` has its own `.standard.yml`.

`bin/` holds **Bash** executables, `scripts/` holds **Ruby** ones — deliberately separated so standardrb has one directory to lint and one to ignore entirely, and neither has to be configured around the other. `.envrc` puts both on `PATH`; run `direnv allow .` after cloning or after editing `.envrc`.

The `spec-plan-build` CLI itself (`scripts/spec-plan-build`, aliased via `just spec-*` recipes):

```bash
spec-plan-build create tax rule dsl              # 003.00-⚪️-tax-rule-dsl
spec-plan-build create --after 002 k1 sync       # 002.01-retroactive plan
spec-plan-build status                            # table of every plan, state, PRs; exits 1 on a name that lies
spec-plan-build resync dirs [--commit]              # folder emoji vs folder contents
spec-plan-build resync prs [--commit]                # [NNN.MM] prefixes on PR titles
spec-plan-build linear import --prefix TAX [--commit | --format json]
spec-plan-build run [--commit] [-j N] [--isolation worktree|shared]  # drive the agent harness
spec-plan-build docs -o context/feature-building/spec-plan-build.md   # regenerate conventions from lifecycle.rb
```

Everything that writes to disk or GitHub is a **dry run until `--commit`** — folder names and PR titles are things other people join on, so previewing before mutating is the whole point of the tool.

## Architecture

### `lib/spec_plan_build/` — the library

Entry point `lib/spec_plan_build.rb` requires each component only if the file exists (`File.exist?` guard), so the suite stays green while the library is built out incrementally. Key pieces:

- **`state_machine.rb`** — the single source of truth for plan lifecycle topology, built on `aasm`. States live in a directory name, not a database column (`aasm_read_state`/`aasm_write_state` just read/write `@key`); a successful transition renames the folder (`after_all_transitions :rename!`). The guard for entering any state is that state's own invariant (`Status#satisfied_by?`) — there is no separate "is this allowed" table. `SPINE` defines the forward path a bare `promote!` walks; blocking, deferring, discarding, and rejection are named explicitly off that spine. `FAMILIES` groups states a folder's *contents* alone cannot distinguish (e.g. `blocked`/`product_blocked`, or `building`/`ready_for_review`/`in_review`/`rejected`) — within a family the current name always wins over re-derivation.
- **`status.rb`** — `Status` is a `Data.define` describing one state: its emoji, label, required files, and an `invariant` proc. This is read by both the state machine (validating a transition) and `resync` (catching drift between a folder's name and its contents), so the two can never disagree about what a state means.
- **`ordinal.rb`** — the `NNN.MM` numbering scheme (`000.00` is first; `MM` `01`-`99` marks a retroactive plan documenting work that already shipped).
- **`tree.rb`**, **`creator.rb`**, **`resync.rb`**, **`reporter.rb`**, **`index.rb`** — read/write the `.plans/` directory tree, create new plan folders, reconcile folder names and PR title prefixes against actual contents, and render the status table / `INDEX.md`.
- **`brief.rb`** — for a genuinely new feature (not `--after`/`--prs`), `create` scaffolds `spec.md` with a title and four fixed headings and shells out to `claude -p` (read-only tools, no web) to make a best-effort attempt at them from what the repo already has on disk, then opens the file. See "Writing a plan's `spec.md`" below for what it must never write.
- **`github.rb`**, **`pull_request.rb`** — talk to `gh` to associate pull requests with plan numbers.
- **`linear/`** (`api.rb`, `import.rb`, `mapping.rb`, `push.rb`, `issue.rb`, `unit.rb`, `fuzzy.rb`, `attribution.rb`, `survey.rb`) — one-way export of `.plans` into Linear: each plan folder becomes a Linear project, each `PR-n` work unit in its `plan.md` becomes an issue. Nothing typed into Linear flows back; a committed `linear.md` per plan is the fingerprint that makes re-running the import a no-op. `fuzzy.rb` uses Jaro-Winkler matching to associate PRs/work units when titles aren't exact.
- **`agent.rb`**, **`worktree.rb`**, **`executor.rb`**, **`runner.rb`** — the multi-agent harness: assign plans to specialist agents, isolate each plan in its own git worktree (`<user>/NNN.MM-slug` branch) under `--isolation worktree`, run them in parallel (`Parallel`, capped at `cores - 2`, max 12), and verify afterward that `HEAD` didn't move (agents may edit source/tests/plan docs but must never commit, push, or touch PRs — enforced by `--disallowedTools` plus a post-hoc check). `run --plan NNN,NNN.MM,...` scopes a round to specific plans instead of the whole tree — see the batch-create note below.
- **`documentation.rb`** — generates `context/feature-building/spec-plan-build.md` (including the lifecycle diagram) directly from `state_machine.rb`/`status.rb`, so the docs cannot drift from the code the way three previously hand-maintained copies of this table did.
- **`diagram.rb`** — `spec-plan-build states` renders the same machine as a terminal-friendly unicode diagram (main spine, off-spine rejoins, every other transition, terminal states, look-alike families), derived the same way `documentation.rb` is.
- **`cli.rb`** — `Dry::CLI` command definitions; each command is a thin shell that parses flags, calls one library object, and prints the result. Convention: deliverables go to STDOUT, progress/boxes go to STDERR (so every command composes in a pipe).

### `.plans/` convention (what the tool operates on, in *other* repositories)

Each feature gets one folder under `.plans/`, and the folder name *is* its state: `NNN.MM-<emoji>-<slug>`, e.g. `002.00-⭐️-tenancy-households`. Three phases, each proved by a file's existence: **spec** (⚪️ New → `spec.md`), **plan** (⭐️ Ready → `plan.md`), **build** (🟡→✅ → `pull-requests.md`). A folder may not claim a phase whose file is missing — this is enforced by the state machine's guards, not by convention alone.

### The multi-agent harness (`agents/*.md`)

Specialist agents are markdown files whose frontmatter routes them and whose body is the prompt:

| Agent | Handles | Advances to | Does |
|---|---|---|---|
| `yoda-writer` | ⚪️ ⬜️ | ⭐️ | grills and writes `spec.md`, or blocks with numbered questions |
| `palpatine-planner` | ⭐️ | 🟡 | decomposes into concurrently-executable work units |
| `luke-implementer` | 🟡 | ✅ | builds one work unit, source and tests |
| `hansolo-reviewer` | any | — | adversarial review; writes nothing, returns a verdict |

`spec-plan-build run` assigns plans to these agents and loops until a fixed point (a round where nothing changed), reading progress back off disk (re-running `resync dirs`) rather than trusting an agent's own claim of success. Blocked states (⭕️ / 🅱️) are never assigned — they mean a human decides.

### Repo layout

| Path | What it is |
|---|---|
| `config/AGENTS.md` | The instructions every agent reads; symlinked to `~/AGENTS.md` and `~/.claude/CLAUDE.md` by `bin/setup` |
| `context/` | Durable reference loaded on demand — per-language conventions (`context/languages/`), PostgreSQL, the spec-plan-build lifecycle doc, an "about me" file |
| `agents/` | Specialist agent definitions for the multi-agent harness (table above) |
| `skills/` | Claude skills, one directory per skill, each symlinked individually into `~/.claude/skills/` |
| `commands/` | Slash-command definitions (e.g. `/create-pr`, `/plan-create`, `/plan-run`, `/plan-linear-import`) that back the `spec-plan-build` workflow |
| `bin/` | Bash executables (`setup`, `agent-lock`, `create-branch-name`, `plan-number`, `create-plan-folder`, plugin installers) |
| `scripts/` | Ruby executables — currently just `spec-plan-build`, the CLI entry point |
| `lib/spec_plan_build/` | The library described above |
| `spec/` | RSpec suite, mirroring `lib/spec_plan_build/` |
| `plugins/` | Vendored/external Claude plugins (not linted; see `.standard.yml` ignore list) |

### Vendor neutrality

`config/AGENTS.md`, `context/` and `scripts/` are portable — any agent that can read a file and run a command can use them. `skills/` is Anthropic's format and is installed only for Claude.

## Project-specific conventions worth knowing before editing

- **Concurrency safety**: many agent sessions may run against this checkout at once. Before creating or editing a file, claim it with `bin/agent-lock acquire <id> "<reason>"` (narrowest scope that covers the writes); release with `bin/agent-lock release <id>` or `release-all` at session end. Prefer a git worktree over a lock for anything longer than a few minutes.
- **Numbering is permanent**: a plan's `NNN.MM` is set once and joined on by branch names, PR titles and `pull-requests.md`; renumbering breaks those links silently.
- **`resync` never guesses across ambiguity**: `resync prs` only edits a PR title when the diff touches exactly one plan; anything ambiguous is reported, never edited, even with `--commit`.
- **Real names/emails**: never use real people's names or emails as placeholders anywhere in this repo (code, docs, specs, fixtures). Use `Alan Turing <alan.turing@manchester.edu>` as the canonical example person. See `config/AGENTS.md` for the specific list of names/emails that must never appear.
- **Commit messages**: imperative mood, ≤50-char subject, no period; body only for non-trivial changes, explaining what/why, ≤30 lines, atomic (one conceptual change per commit).
- **Writing a plan's `spec.md`**: the four headings `create` scaffolds (`## What we are trying to achieve`, `## Why it matters`, `## What already exists`, `## What research needs to settle`) are the whole of what belongs there before a specialist agent touches it. Never add Goals, Non-Goals or a conclusion — that is `yoda-writer`'s chapter, written after research, and pre-writing it decides the answer before the research runs. Never write a `## Research` heading, not even empty — it is the 🔎 Researched state transition, so seeding it flips the folder's state and the agent loop skips `leah-researcher` entirely. Full constraints, and the shape for creating several plans at once (batch the creates, verify each with `status`, one `run --commit --plan NNN,...` handoff — never one `run` per `create`), are in `commands/plan-create.md`.
