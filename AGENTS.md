# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Skills to Activate Upon Start

- /unslop

## Skills to Activate when Writing Plans, Specs or Coding

- /superpowers:brainstorm
- /writing-plans

## What this repository is

`~/.agents` is Konstantin Gredeskoul's vendor-neutral home for instructions, context, skills and tooling shared across AI coding agents (Claude, Codex, Pi, Grok, etc.), plus **agentilda**: a Ruby CLI that keeps a project's specifications, plans and pull requests joined up, and can drive specialist agents over them in parallel.

`bin/setup` symlinks this repo's shared folders into `~/.claude` (and `config/AGENTS.md` to `~/AGENTS.md` / `~/.claude/CLAUDE.md`), so a project working elsewhere on the machine sees these skills, agents and context files as if they were local. It never overwrites a real file or directory: conflicts are reported and skipped. Links are relative, so the whole tree survives being cloned under a different `$HOME`.

## Commands

```bash
bundle install                           # install gems
just doctor                              # what `bin/install` would copy and link, touching nothing
just install                             # copy into ~/.agents, then link into ~/.claude
just relink                              # repoint symlinks that aim somewhere else (bin/setup --force)

just lint                                # standardrb, reports only, never rewrites
just format                              # standardrb --fix, then mdformat on every *.md

just test                                # rspec
just test spec/agentilda/ordinal_spec.rb                        # single file
just test spec/agentilda/ordinal_spec.rb -e "some example name" # single example
just test-coverage                       # rspec with SimpleCov; open coverage/index.html

just ci                                  # lint + test-coverage (what CircleCI runs)
just lefthook                            # run all pre-commit hooks against the whole tree

just docs                                # regenerate context/feature-building/agentilda.md from the state machine
```

`standard`, not `rubocop`, is the linter (see Gemfile comment: "standard is rubocop with the arguing removed"). `standardrb` ignores `skills/`, `plugins/`, `coverage/`, `tmp/` (see `.standard.yml`). One config at the root governs the whole tree: lint runs from here so it sees `scripts/` and `workflow/` alike, with `BUNDLE_GEMFILE` pointed at the gem.

Executables sit in three places, by what they need in order to run. `bin/` holds **Bash**, `scripts/` holds the one **Ruby** executable that must work on a machine with no bundle yet, and `workflow/exe/` holds the gem's, which resolve `BUNDLE_GEMFILE` from their own location and so run the same from `PATH` as from another project's root. `.envrc` puts all three on `PATH`; run `direnv allow .` after cloning or after editing `.envrc`.

The `agentilda` CLI itself (`workflow/exe/agentilda`), which also answers to `tilda`, a symlink beside it for the times you are typing it twenty times an hour:

```bash
agentilda create tax rule dsl                                 # 003.00-⚪️-tax-rule-dsl
agentilda create --after 002 k1 sync                          # 002.01-🕰️-k1-sync (retroactive)
agentilda list-plans                                          # every plan, state, PRs; exits 1 on a lie
agentilda states                                              # the state machine, as a diagram
agentilda agents list                                         # every specialist, what it handles, what it advances to
agentilda agents describe luke-implementer                    # one specialist in full, prompt included
agentilda describe luke-implementer                           # the same, without the `agents` in front
agentilda resync dirs [--commit]                              # folder emoji vs folder contents
agentilda resync prs [--commit]                               # [NNN.MM] prefixes on PR titles
agentilda linear import --prefix TAX [--commit | --format json]
agentilda run [--commit] [-j N] [--isolation worktree|shared] [--plan NNN,...]  # drive the agents
agentilda docs -o context/feature-building/agentilda.md # regenerate conventions from the state machine
```

And the sibling installer that populates `skills/`/`plugins/` for this repo itself (`scripts/install-sources`, plain Ruby, no bundler needed):

```bash
scripts/install-sources           # clone what's missing, update the rest
scripts/install-sources -n        # say what it would install and unlink, touch nothing
scripts/install-sources -f        # wipe .sources and re-clone every source fresh
scripts/install-sources list      # what's configured, and what's installed from where
```

Everything that writes to disk or GitHub is a **dry run until `--commit`**. Folder names and PR titles are things other people join on, so previewing before mutating is the whole point of the tool. `install-sources` is the exception: it always writes, because everything it touches (`skills/`, `plugins/`, `.sources/`) is declared regenerable in `.gitignore`.

## The workflow, step by step

A feature moves through five specialists, one state at a time, never further than its own documents currently justify. This is the same machine `agentilda states` draws and `documentation.rb` generates prose from. Change who handles what, and those two commands are the staleness check.

| #   | State                             | Who acts                                | What happens                                                                                                                                                                                                                                                                                                                    |
| :-- | :-------------------------------- | :-------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | ⚪️ New                            | `agentilda create`                | Mints the plan folder. For a genuinely new feature (not `--after`/`--prs`), scaffolds `spec.md`'s four fixed headings (*What we are trying to achieve*, *Why it matters*, *What already exists*, *What research needs to settle*), attempts a best-effort first pass via `claude -p`, and opens it. A human finishes the brief. |
| 2   | 🔎 Researched                     | `leah-researcher`                       | Fans work out across parallel sub-agents, appends spec.md's `## Research` chapter. That heading *is* the transition. Nobody else may write it, not even empty.                                                                                                                                                                 |
| 3   | ⭐️ Planned                        | `yoda-writer`, then `palpatine-planner` | `yoda-writer` turns the brief + research into Goal/Non-Goals/In-Out-of-scope/Conclusion, or writes `blocked.md` when a question is a human's to answer. `palpatine-planner` then decomposes the finished spec into `plan.md`'s non-overlapping work units.                                                                      |
| 4   | 🟡 Building → 🟢 Ready for Review | `luke-implementer`                      | Builds one work unit at a time: source and tests, no commits. Opens a `[NNN.MM] …` pull request as each lands.                                                                                                                                                                                                              |
| 5   | 👀 In Review → 🔴 / ✅            | `hansolo-reviewer`                      | Reads the diff against the plan; requests changes (back to 🟢 once fixed) or approves. Never merges. That line is enforced in code (`Executor::UNGRANTABLE`), not just in the prompt.                                                                                                                                          |

Off to the side, at any point: ⭕️/🅱️ **Blocked** (a decision only a human can make, never offered to an agent by the loop) and ☢️ **Deferred** or ❌ **Discarded**.

Blocks drain by hand, one answer at a time. Whoever writes `blocked.md` **must** number each open question as its own `## B1`, `## B2` heading, and each answer as `## A1`, `## A2`, where `## A1` settles `## B1`. That notation is the only part of the file a program can read: a question written any other way leaves the folder looking unblocked and `unblock` reporting nothing to drain. A human writes the answers in as `## A<n>` sections, attributed and dated, and runs `agentilda unblock NNN --commit`, which hands the folder to `lando-broker`: it folds each answered question into the document that question was stopping (`spec.md` for what and why, `plan.md` for how and in what order), deletes the question, and deletes the file when none are left. `blocked.md` holds open questions and the answers not yet folded, and the ⭕️/🅱️ invariant reads the `## B<n>` headings, so the pass that empties the file is the pass that lets the folder out. A partial drain is a normal, successful run; whatever is still open keeps the plan blocked, correctly. `lando-broker` never answers anything itself, and `run` cannot reach it, because a blocked plan waiting on a human is the one thing an autonomous loop must not quietly resolve.

### Invoking it: slash command or the binary directly

Both paths run the same `workflow/exe/agentilda`. The difference is which guardrails come along.

- **`workflow/exe/agentilda <command>` directly.** The whole tool, no Claude required. Use this for scripting, CI, or driving it from any other agent.
- **A Claude Code slash command**, via `src/commands/*.md` (`/plan-create`, `/plan-research`, `/plan-run`, `/plan-status`, `/plan-unblock`, `/plan-resync-dirs`, `/plan-resync-prs`, `/plan-docs`, `/plan-insert`, `/plan-linear-import`). A thin wrapper around the same binary, plus the constraints that erode if left to memory. `/plan-create` won't seed a `## Research` heading or pre-write Goals. `/plan-run` insists on confirming scope, `--commit`, and parallelism first. **Prefer the slash command inside a Claude Code session.** It carries the constraints `src/commands/plan-create.md` documents in full.

`skills/` and `workflow/agents/*.md` are a separate concern from the above: Claude's general skill/specialist library, not part of invoking `agentilda` itself. `workflow/agents/*.md` *is* where the five specialists above are defined, plus `lando-broker`. Frontmatter `handles:`/`advances_to:` is exactly what `Agents#for_status` reads to route a plan.

## Architecture

### `.plans/` convention (what the tool operates on, in *other* repositories)

Each feature gets one folder under `.plans/`, and the folder name *is* its state: `NNN.MM-<emoji>-<slug>`, e.g. `002.00-⭐️-tenancy-households`. A folder may not claim a phase whose file is missing. That's enforced by the state machine's guards, not by convention alone. See the workflow table above for what proves each state.

### `workflow/lib/agentilda/` quick file map

Entry point `workflow/lib/agentilda.rb` requires each component only if the file exists, so the suite stays green while the library is built out incrementally.

- **`state_machine.rb`** and **`status.rb`**: the single source of truth for lifecycle topology (`aasm`) and what each state requires (`Status#satisfied_by?`). States live in a directory name, not a database column; a transition renames the folder. The two are read together, so a transition guard and a drift check can never disagree about what a state means.
- **`ordinal.rb`**: the `NNN.MM` numbering scheme.
- **`tree.rb`**, **`creator.rb`**, **`brief.rb`**, **`resync.rb`**, **`reporter.rb`**, **`index.rb`**: read and write the `.plans/` tree. Mint folders, scaffold and draft a new feature's brief, reconcile folder names and PR prefixes against contents, render `status`/`INDEX.md`.
- **`github.rb`**, **`pull_request.rb`**: talk to `gh` to associate pull requests with plan numbers.
- **`linear/`**: one-way export of `.plans` into Linear projects and issues. A committed `linear.md` per plan is the fingerprint that makes re-running it free.
- **`agent.rb`**, **`worktree.rb`**, **`executor.rb`**, **`runner.rb`**: the multi-agent harness. Routes a plan to the specialist that `handles:` its state, isolates it in its own git worktree, runs rounds in parallel, verifies `HEAD` didn't move afterward. `Runner#in_scope?` is what `run --plan` filters on.
- **`transcript.rb`**: reads the newline-delimited JSON `claude -p --output-format stream-json --verbose --include-partial-messages` writes as it works, and turns it into the two things a spinner line carries: the short phrase there is room for, so a line says `yoda-writer: editing spec.md` rather than only `yoda-writer`, and the token meter beside it. Tokens are counted off `message_delta` events, never off `assistant` ones, whose output count is the placeholder the API sends when a message starts. `claude` leaves a sub-agent's spend out of its parent's total and reports it separately as one unsplit number, so sub-agents are counted per task and folded into ↑. Every invocation's raw stream is also kept under `$TMPDIR/agentilda-traces`, one file per run, minus the character-by-character deltas that `--include-partial-messages` also emits; `jq -r 'select(.type=="result").result' <trace>` gets the agent's final answer back out of a run that failed.
- **`progress_log.rb`** and **`tally.rb`**: what a run says about itself. `progress_log` lays each `--log` line out as fixed-width columns (time, plan, state, agent, pid, seconds alive) so one shared log file stays readable while several runs append to it; `tally` is the closing report: plans addressed, wall clock, sub-agents spawned per agent, average agents running at once, and the tokens the whole run spent.
- **`unblocker.rb`**: what `unblock` actually does. Resolves each number on the command line, hands the drainable ones to `lando-broker` one at a time, and counts the `## B<n>` headings off disk before and after, so "folded B3" means the heading is gone rather than that an agent said so.
- **`documentation.rb`** and **`diagram.rb`**: generate the Markdown conventions doc and the terminal diagram, both directly off `state_machine.rb`/`status.rb`, so neither drifts from the code the way three previously hand-maintained copies of this table did.
- **`cli.rb`**: `Dry::CLI` command definitions. Each is a thin shell that parses flags, calls one library object, and prints the result. Deliverables go to STDOUT, progress to STDERR, so every command composes in a pipe.

### Repo layout

| Path                        | What it is                                                                                                                                                                                                    |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `config/AGENTS.md`          | The instructions every agent reads; symlinked to `~/AGENTS.md` and `~/.claude/CLAUDE.md` by `bin/setup`                                                                                                       |
| `configuration.example.yml` | Committed template for configuration.yml, which is per-machine and git-ignored. Declarative list `scripts/install-sources` fills `skills/`/`plugins/` from, by cloning a repo or running an installer command |
| `context/`                  | Durable reference loaded on demand: per-language conventions, PostgreSQL, the agentilda lifecycle doc, `skills-used.md`                                                                                       |
| `src/skills/`               | Skills authored in this repo, **committed**. Folded into `skills/` by `install-sources`                                                                                                                       |
| `src/commands/`             | Slash commands wrapping `agentilda` (table above)                                                                                                                                                             |
| `skills/`                   | Claude skills, **generated** by `install-sources`, not committed. One directory per skill, symlinked into `~/.claude/skills/`                                                                                 |
| `plugins/`                  | External plugin bundles (e.g. `pstack`), also generated, not committed                                                                                                                                        |
| `bin/`                      | Bash executables of the installer half. `setup` is a pure symlink reconciler, nothing more                                                                                                                    |
| `scripts/`                  | `install-sources`, the one Ruby executable that has to run before `bundle install` ever has                                                                                                                   |
| `workflow/`                 | The `agentilda` gem, and nothing that installs anything: `exe/`, `lib/`, `agents/`, `spec/`, its own Gemfile                                                                                                  |
| `workflow/lib/agentilda/`   | The library described above                                                                                                                                                                                   |
| `workflow/agents/`          | The six specialist definitions from the workflow table above                                                                                                                                                  |

### Vendor neutrality

`config/AGENTS.md`, `context/` and `scripts/` are portable. Any agent that can read a file and run a command can use them. `skills/` is Anthropic's format and is installed only for Claude.

## Project-specific conventions worth knowing before editing

- **Every change ends green**: run `just lint` and `just test` before calling a code change done, and fix what they report rather than handing the failures back. `just ci` runs the pair the way CircleCI does. Nobody has to ask for this.
- **Concurrency safety**: many agent sessions may run against this checkout at once. Before creating or editing a file, claim it with `bin/agent-lock acquire <id> "<reason>"` (narrowest scope that covers the writes); release with `bin/agent-lock release <id>` or `release-all` at session end. Prefer a git worktree over a lock for anything longer than a few minutes.
- **Numbering is permanent**: a plan's `NNN.MM` is set once and joined on by branch names, PR titles and `pull-requests.md`; renumbering breaks those links silently.
- **`resync` never guesses across ambiguity**: `resync prs` only edits a PR title when the diff touches exactly one plan; anything ambiguous is reported, never edited, even with `--commit`.
- **Real names/emails**: never use real people's names or emails as placeholders anywhere in this repo (code, docs, specs, fixtures). Use `Alan Turing <alan.turing@manchester.edu>` as the canonical example person. See `config/AGENTS.md` for the specific list of names/emails that must never appear.
- **Commit messages**: imperative mood, ≤50-char subject, no period; body only for non-trivial changes, explaining what/why, ≤30 lines, atomic (one conceptual change per commit).
- **No co-author trailers**: never add `Co-Authored-By:` or `Claude-Session:` lines to a commit message or a pull request body. The author of a commit is the person who ran the session, and a trailer naming the model adds nothing a reader wants.
- **Writing prose in this repo**: apply `skills/unslop/SKILL.md`'s rules as you write, not as a cleanup pass after. No em dashes, no AI-tell phrasing (puffery, hedging, inline-header-colon lists), active voice, plain words over fancy synonyms. This applies going forward; prose predating this rule was not rewritten to match.
- **Writing a plan's `spec.md`**: the four headings `create` scaffolds are the whole of what belongs there before a specialist agent touches it. Never add Goals, Non-Goals, or a conclusion. That is `yoda-writer`'s chapter, written after research; pre-writing it decides the answer before the research runs. Never write a `## Research` heading, not even empty. It is the 🔎 Researched state transition, so seeding it flips the folder's state and the agent loop skips `leah-researcher` entirely. Full constraints, and the shape for creating several plans at once (batch the creates, verify each with `status`, one `run --commit --plan NNN,...` handoff, never one `run` per `create`), are in `src/commands/plan-create.md`.
- **`skills/` and `plugins/` are regenerated, not hand-maintained**: add a source to `configuration.yml` and run `scripts/install-sources` rather than installing a skill by hand into either directory. Anything installed outside that path has no record of where it came from, which is the exact problem the script exists to solve. A source that has no repository to clone, such as one installed by `npx skills add`, is `type: command` with an `install:` command line. That command runs with its working directory inside `.sources/<name>` and whatever it writes to `.claude/skills` and `.claude/plugins` there is installed the same way a clone's contents are. Never give it a global flag: `npx skills add … -g` writes to `~/.claude/skills`, where no manifest records it and no filter reaches it.
- **Which agents a source is for**: `agents: [claude]` **or** `exclude_agents: [claude]`, never both, matched against the top-level `agents:` block. Leaving both out means portable, which is what most sources are and what this repo is for, so the vendor-locked source is the one that has to say so. A source no configured agent would read is skipped and reported, and it prunes what it installed before, because being for nobody here is a decision rather than a failure. A source that could not be *fetched* keeps its links instead: a network that was down is not an instruction to uninstall anything.
- **Narrowing a source**: a source in `configuration.yml` takes `include_skills: /re/` **or** `exclude_skills: /re/`, never both, and the same pair for `_plugins`, matched against the name each thing installs as (`skills/<name>`, `plugins/<name>`), not its path inside the source. Tightening one unlinks what the previous run installed and no longer installs, so `skills/` converges rather than accumulating; `bin/setup` sweeps the dangling `~/.claude/skills` links that leaves behind. The skills pair governs the fan-out into `skills/` and the plugins pair governs which bundles get copied, and neither reaches inside a bundle. A `type: plugin` or `type: command` source also takes `adopt: [skills, plugins]`, which is how you take a command's skills and leave its bundle, or the other way round.
