# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`~/.agents` is Konstantin Gredeskoul's vendor-neutral home for instructions, context, skills and tooling shared across AI coding agents (Claude, Codex, Pi, Grok, etc.), plus **spec-plan-build**: a Ruby CLI that keeps a project's specifications, plans and pull requests joined up, and can drive specialist agents over them in parallel.

`bin/setup` symlinks this repo's shared folders into `~/.claude` (and `config/AGENTS.md` to `~/AGENTS.md` / `~/.claude/CLAUDE.md`), so a project working elsewhere on the machine sees these skills, agents and context files as if they were local. It never overwrites a real file or directory — conflicts are reported and skipped — and links are relative so the whole tree survives being cloned under a different `$HOME`.

## Commands

```bash
bundle install        # install gems
just doctor            # what `bin/setup` would link, touching nothing
just setup              # actually symlink into ~/.claude (bin/setup)
just relink               # repoint symlinks that aim somewhere else (bin/setup --force)

just lint                # standardrb — reports only, never rewrites
just format                # standardrb --fix, then mdformat on every *.md

just test                    # rspec
just test spec/spec_plan_build/ordinal_spec.rb                        # single file
just test spec/spec_plan_build/ordinal_spec.rb -e "some example name" # single example
just test-coverage           # rspec with SimpleCov; open coverage/index.html

just ci                # lint + test-coverage (what CircleCI runs)
just lefthook            # run all pre-commit hooks against the whole tree

just docs                  # regenerate context/feature-building/spec-plan-build.md from the state machine
```

`standard`, not `rubocop`, is the linter (see Gemfile comment: "standard is rubocop with the arguing removed"). `standardrb` ignores `skills/`, `plugins/`, `coverage/`, `tmp/` (see `.standard.yml`); `lib/` has its own `.standard.yml`.

`bin/` holds **Bash** executables, `scripts/` holds **Ruby** ones — deliberately separated so standardrb has one directory to lint and one to ignore entirely, and neither has to be configured around the other. `.envrc` puts both on `PATH`; run `direnv allow .` after cloning or after editing `.envrc`.

The `spec-plan-build` CLI itself (`scripts/spec-plan-build`):

```bash
spec-plan-build create tax rule dsl                                 # 003.00-⚪️-tax-rule-dsl
spec-plan-build create --after 002 k1 sync                          # 002.01-🕰️-k1-sync (retroactive)
spec-plan-build status                                              # every plan, state, PRs; exits 1 on a lie
spec-plan-build states                                              # the state machine, as a diagram
spec-plan-build resync dirs [--commit]                              # folder emoji vs folder contents
spec-plan-build resync prs [--commit]                               # [NNN.MM] prefixes on PR titles
spec-plan-build linear import --prefix TAX [--commit | --format json]
spec-plan-build run [--commit] [-j N] [--isolation worktree|shared] [--plan NNN,...]  # drive the agents
spec-plan-build docs -o context/feature-building/spec-plan-build.md # regenerate conventions from the state machine
```

And the sibling installer that populates `skills/`/`plugins/` for this repo itself (`scripts/install-sources`, plain Ruby, no bundler needed):

```bash
scripts/install-sources           # clone what's missing, update the rest
scripts/install-sources -f        # wipe .sources and re-clone every source fresh
scripts/install-sources list      # what's configured, and what's installed from where
```

Everything that writes to disk or GitHub is a **dry run until `--commit`** — folder names and PR titles are things other people join on, so previewing before mutating is the whole point of the tool. `install-sources` is the exception: it always writes, because everything it touches (`skills/`, `plugins/`, `.sources/`) is declared regenerable in `.gitignore`.

## The workflow, step by step

A feature moves through five specialists, one state at a time, never further than its own documents currently justify. This is the same machine `spec-plan-build states` draws and `documentation.rb` generates prose from — if you change who handles what, those two commands are the staleness check.

| # | State | Who acts | What happens |
| :- | :--- | :--- | :--- |
| 1 | ⚪️ New | `spec-plan-build create` | Mints the plan folder; for a genuinely new feature (not `--after`/`--prs`) scaffolds `spec.md`'s four fixed headings — *What we are trying to achieve*, *Why it matters*, *What already exists*, *What research needs to settle* — attempts a best-effort first pass via `claude -p`, and opens it. A human finishes the brief. |
| 2 | 🔎 Researched | `leah-researcher` | Fans work out across parallel sub-agents, appends spec.md's `## Research` chapter. That heading *is* the transition — nobody else may write it, not even empty. |
| 3 | ⭐️ Planned | `yoda-writer`, then `palpatine-planner` | `yoda-writer` turns the brief + research into Goal/Non-Goals/In-Out-of-scope/Conclusion, or writes `blocked.md` when a question is a human's to answer. `palpatine-planner` then decomposes the finished spec into `plan.md`'s non-overlapping work units. |
| 4 | 🟡 Building → 🟢 Ready for Review | `luke-implementer` | Builds one work unit at a time — source and tests, no commits — opening a `[NNN.MM] …` pull request as each lands. |
| 5 | 👀 In Review → 🔴 / ✅ | `hansolo-reviewer` | Reads the diff against the plan; requests changes (back to 🟢 once fixed) or approves. Never merges — that line is enforced in code (`Executor::UNGRANTABLE`), not just in the prompt. |

Off to the side, at any point: ⭕️/🅱️ **Blocked** (an engineering or product decision only a human can make — never assigned to an agent) and ☢️ **Deferred** or ❌ **Discarded**.

### Invoking it — slash command or the binary directly

Both paths run the same `scripts/spec-plan-build`; the difference is which guardrails come along:

- **`scripts/spec-plan-build <command>` directly** — the whole tool, no Claude required. Use this for scripting, CI, or driving it from any other agent.
- **A Claude Code slash command**, `commands/*.md` (`/plan-create`, `/plan-research`, `/plan-run`, `/plan-status`, `/plan-resync-dirs`, `/plan-resync-prs`, `/plan-docs`, `/plan-insert`, `/plan-linear-import`) — a thin wrapper around the same binary plus the constraints that erode if left to memory: `/plan-create` won't seed a `## Research` heading or pre-write Goals; `/plan-run` insists on confirming scope, `--commit` and parallelism first. **Prefer the slash command inside a Claude Code session** — it carries the constraints `commands/plan-create.md` documents in full.

`skills/` and `agents/*.md` are a separate concern from the above — Claude's general skill/specialist library, not part of invoking `spec-plan-build` itself. `agents/*.md` *is* where the five specialists above are defined (frontmatter `handles:`/`advances_to:` is exactly what `Agents#for_status` reads to route a plan).

## Architecture

### `.plans/` convention (what the tool operates on, in *other* repositories)

Each feature gets one folder under `.plans/`, and the folder name *is* its state: `NNN.MM-<emoji>-<slug>`, e.g. `002.00-⭐️-tenancy-households`. A folder may not claim a phase whose file is missing — enforced by the state machine's guards, not by convention alone. See the workflow table above for what proves each state.

### `lib/spec_plan_build/` — quick file map

Entry point `lib/spec_plan_build.rb` requires each component only if the file exists, so the suite stays green while the library is built out incrementally.

- **`state_machine.rb`** / **`status.rb`** — the single source of truth for lifecycle topology (`aasm`) and what each state requires (`Status#satisfied_by?`). States live in a directory name, not a database column; a transition renames the folder. Both are read together so a transition guard and a drift check can never disagree about what a state means.
- **`ordinal.rb`** — the `NNN.MM` numbering scheme.
- **`tree.rb`**, **`creator.rb`**, **`brief.rb`**, **`resync.rb`**, **`reporter.rb`**, **`index.rb`** — read/write the `.plans/` tree: mint folders, scaffold and draft a new feature's brief, reconcile folder names and PR prefixes against contents, render `status`/`INDEX.md`.
- **`github.rb`**, **`pull_request.rb`** — talk to `gh` to associate pull requests with plan numbers.
- **`linear/`** — one-way export of `.plans` into Linear projects/issues; a committed `linear.md` per plan is the fingerprint that makes re-running it free.
- **`agent.rb`**, **`worktree.rb`**, **`executor.rb`**, **`runner.rb`** — the multi-agent harness: route a plan to the specialist that `handles:` its state, isolate it in its own git worktree, run rounds in parallel, verify `HEAD` didn't move afterward. `Runner#in_scope?` is what `run --plan` filters on.
- **`documentation.rb`** / **`diagram.rb`** — generate the Markdown conventions doc and the terminal diagram, both directly off `state_machine.rb`/`status.rb`, so neither can drift from the code the way three previously hand-maintained copies of this table did.
- **`cli.rb`** — `Dry::CLI` command definitions; each is a thin shell that parses flags, calls one library object, prints the result. Deliverables go to STDOUT, progress to STDERR, so every command composes in a pipe.

### Repo layout

| Path | What it is |
|---|---|
| `config/AGENTS.md` | The instructions every agent reads; symlinked to `~/AGENTS.md` and `~/.claude/CLAUDE.md` by `bin/setup` |
| `config/sources.yml` | Declarative list `scripts/install-sources` clones `skills/`/`plugins/` content from |
| `context/` | Durable reference loaded on demand — per-language conventions, PostgreSQL, the spec-plan-build lifecycle doc, `skills-used.md` |
| `agents/` | The five specialist definitions from the workflow table above |
| `skills/` | Claude skills — **generated** by `install-sources`, not committed; one directory per skill, symlinked into `~/.claude/skills/` |
| `skills-mine/` | Skills authored in this repo — **committed**; folded into `skills/` by `install-sources` |
| `plugins/` | External plugin bundles (e.g. `pstack`) — also generated, not committed |
| `commands/` | Slash commands wrapping `spec-plan-build` (table above) |
| `bin/` | Bash executables — `setup` is a pure symlink reconciler, nothing more |
| `scripts/` | Ruby executables — `spec-plan-build` and `install-sources` |
| `lib/spec_plan_build/` | The library described above |
| `spec/` | RSpec suite, mirroring `lib/spec_plan_build/` |

### Vendor neutrality

`config/AGENTS.md`, `context/` and `scripts/` are portable — any agent that can read a file and run a command can use them. `skills/` is Anthropic's format and is installed only for Claude.

## Project-specific conventions worth knowing before editing

- **Concurrency safety**: many agent sessions may run against this checkout at once. Before creating or editing a file, claim it with `bin/agent-lock acquire <id> "<reason>"` (narrowest scope that covers the writes); release with `bin/agent-lock release <id>` or `release-all` at session end. Prefer a git worktree over a lock for anything longer than a few minutes.
- **Numbering is permanent**: a plan's `NNN.MM` is set once and joined on by branch names, PR titles and `pull-requests.md`; renumbering breaks those links silently.
- **`resync` never guesses across ambiguity**: `resync prs` only edits a PR title when the diff touches exactly one plan; anything ambiguous is reported, never edited, even with `--commit`.
- **Real names/emails**: never use real people's names or emails as placeholders anywhere in this repo (code, docs, specs, fixtures). Use `Alan Turing <alan.turing@manchester.edu>` as the canonical example person. See `config/AGENTS.md` for the specific list of names/emails that must never appear.
- **Commit messages**: imperative mood, ≤50-char subject, no period; body only for non-trivial changes, explaining what/why, ≤30 lines, atomic (one conceptual change per commit).
- **Writing a plan's `spec.md`**: the four headings `create` scaffolds are the whole of what belongs there before a specialist agent touches it. Never add Goals, Non-Goals or a conclusion — that is `yoda-writer`'s chapter, written after research, and pre-writing it decides the answer before the research runs. Never write a `## Research` heading, not even empty — it is the 🔎 Researched state transition, so seeding it flips the folder's state and the agent loop skips `leah-researcher` entirely. Full constraints, and the shape for creating several plans at once (batch the creates, verify each with `status`, one `run --commit --plan NNN,...` handoff — never one `run` per `create`), are in `commands/plan-create.md`.
- **`skills/` and `plugins/` are regenerated, not hand-maintained**: add a repo to `config/sources.yml` and run `scripts/install-sources` rather than installing a skill by hand into either directory — anything installed outside that path has no record of where it came from, which is the exact problem the script exists to solve.
