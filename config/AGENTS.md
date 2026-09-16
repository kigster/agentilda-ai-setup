# Instructions for All AI Coding Agents, such as Claude CLI, Codex, Pi, Grok and others.

## General Rules

> [!NOTE]
> This is the file that is going to get copied to your home directory, and symlinked to ~/.claude/CLAUDE.md. This file is NOT about this repo, it's about every project you are going to work on from here on out.
>
> This repo comes paired with the Ruby Gem `agentilda` (or `tilda` for short). The combination of this setupa and the gem will set you up for n agentic team sofware development process.

Whenever you are required to provide any textual answer to the user, if the skill is available to you then you will load the /unslop skill upon boot. This is non-negotiable. This skill's purpose is to shorten the "wall of text" answers that the agents like to write, wasting tokens and human patience. If the skill is not available default to short, precise, concise answers, drop any fluff, drop any assumptions that have not been communicated to you. Lean towards a summary report bullet-like format for delivering information to the user.

## Behavioral Rules

You are generally polite, positive, and humorous, and you are encouraged to question and critique my ideas at their core. In fact, when you have a lot of ambiguity, please invoke `/grilling` or `/mattpocock-skills:grill-me` sills to your questions answered.

## Hard Rules that MUST NOT BE BROKEN

These rule must not be broken under any circumstances:

R1. DO NOT EVER SEND ANY OUTBOUND EMAILS ON MY BEHALF WITHOUT EXPLICIT REQUEST AND A PERMISSION GRANT.

R2. DO NOT EVER DELETE ANY LOCAL OR REMOTE FILES THAT ARE NOT EXPLICITLY PART OF THE PROJECT, AND THE FILES WERE STAGED FOR A DELETE BY A HUMAN, OR YOU ARE SUBMITTING A PULL-REQUEST (which can be reverted). IN OTHER WORDS NEVER DELETE DATA IF IT"S NOT POSSIBLE TO REVERT IT WITHIN MINUTES OF REALIZING WHAT HAPPENED.

R3. DO NOT PERFORM ANY OPERATION WITHOUT A CONFIRMATION THAT YOU KNOW WILL RESULT IN A LOSS OF DATA, LOSS OF ACCESS, RESULT IN ANY HARM TO ANOTHER INDIVIDUAL, THIS INDIVIDUAL OR ANY COMPANY ENTITY.

R4. DO NOT EVER DO ANYTHING ILLEGAL, SUCH AS HACKING INTO SERVERS ON A LOCAL NETWORK, REMOTE SERVERS, OR USING UNAUTHORIZED USERNAME AND PASSWORD or and API TOKEN. THE ONLY EXCEPTION TO THE HACKING RULE IS IF I ASK FOR YOU TO PERFORM A SECURITY SCAN OR AUDIT OF MY LOCAL HOME NETWORK. IN WHICH CASE YOUR JOB IS TO REPORT ANY VULNERABILITIES, NOT EXPLOIT THEM.

R5: WHEN WORKING WITH THIRD PARTIES DO SCAN THEIR TERMS AND CONDITIONS and PRIVACY POLICY AND IF ANYTHING UNUSUAL OR QUESTIONABLE IS FOUND, YOU WILL NOTIFY THE USER (HUMAN) AND LET THEM DECIDE HOW TO PROCEED.

## Plugins and skills

Prefer to warn the user not to install them by hand.

They are declared in the file `configuration.yml` at the root of the agentilda checkout, and `scripts/install-sources` is what installs them. A source there says which agents it is for, so the Claude-only ones install for Claude and nothing else goes looking for them. Anything installed outside that path has no record of where it came from, which is the problem that file exists to solve.

## Instructions for this project specifically

Please refer to the `README.md` and `AGENTS.md` (or `.claude/CLAUDE.md`) of the project you are working in for specific instructions about how that repo is organized and structured, and for any conventions unique to it that this global file does not cover.

## Rules that apply to all coding projects

> [!CAUTION]
> **CRITICALLY IMPORTANT: rules defined in this document must not be broken without an explicit consent of the human driver. If these rules block the agent, pause and seek confirmation.**

### **NEVER use real names or emails as placeholders**

> [!IMPORTANT]
> For the list of additional specific names or emails not to use in any examples, please read sthe file ~/.agents/context/forbidden-identities.md.

If any of these are found in existing code or docs as placeholders, treat it as a defect and replace with fictional equivalents.

### **Current date**

Is the result of the command: `bash -c date`. Execute upon starting a new session so you are aware of the current date and time.

### **Language**

Use lazy loading ONLY for skills, MCP servers and plugins. Never load all at once.

We use English only - all code, comments, docs, examples, commits, configs, errors, tests. An occasional incoming specification in another language is first translated into English, and then reasoned about.

### Unslop

One of the skills globally installed is `pstack's` `/unslop` skill. You must proactively load this skill any time you are in a new project directory or starting a new project. This skill reduces the amount of text you generate, and makes it tolerable for me to scan the important points and respond in time. Standard feedback is way too verbose, so keep that in mind and keep the responses to the human and your summaries as short (without losing the meaning) as possible. Use bullet points where possible to structure and organize what's done, and what remains to be done (use checkboxes for those).

## **Comments**

Do use comments in every language judiciously, and follow language specific instructions if any.

## **Git Commits**

Subject: 50 chars max, imperative mood ("add" not "added"), no period, sentences capitalized.

For small changes: Up to five lines of description.

For more complex changes: add a body explaining what/why (30 line limit, do not wrap long lines) and reference any issues or tickets. Please ideally keep commits atomic (one logical change per commit) so that they become sort of self-explanatory. If the commit contains several conceptual changes, split them into multiple commits, one conceptual change per commit. Split into multiple commits if addressing completely different concerns.

### Worktrees

Use worktrees to work concurrently on multiple projects, and use the `/create-pr` skill and `~/.agents/bin/create-branch-name` script to generate the branch name based on the short summary of what is being done. Max number of words in the summary is 4.

```bash
$ ~/.agents/bin/create-branch-name fix dsl alignment bug
kig/fix-dsl-alignment-bug
```

Now the branch name of the worktree is `kig/fix-dsl-alignment-bug`

A fresh worktree holds every **tracked** file and nothing else, so anything git ignores is missing and the checkout cannot run. In a Rails project the suite dies on `MissingKeyError` because `config/credentials/*.key` is gitignored, and anything reading `.env` silently gets defaults instead. Seed the worktree before doing anything else in it:

```bash
$ cd ~/.agents.worktrees/fix-dsl-alignment-bug
$ ~/.agents/bin/setup-worktree              # copy .env* and credential keys from the main checkout
$ ~/.agents/bin/setup-worktree --dry-run    # look first
```

It copies only files git ignores, so it can add what a checkout was missing and can never shadow tracked content with a stale local copy. It refuses to overwrite an existing file without `--force`, and production credential keys are opt-in via `--production`.

## **Finishing a task**

A task is not finished when the code is written. It is finished when somebody else can review it.

1. Run the project's own checks and get them green. `just lint` and `just test` where there is a justfile, otherwise whatever the project actually uses. Fix what they report rather than handing the failures back.
1. Open a pull request.
1. Check the state of the repository afterwards, and do not take your own word for it.

Step 3 is the one that gets skipped, so be specific about it. `git push` reporting success proves the branch moved, and nothing else. **A branch whose pull request has already been merged goes on accepting pushes in silence**, and commits pushed to it land where nobody will ever look. The same is true of a branch that never had a pull request at all.

```bash
just lint && just test                  # both green, before anything else
gh pr list                              # is there an OPEN pull request at all?
gh pr view <n> --json commits           # does it contain what you just pushed?
git log --oneline origin/main..HEAD     # what is on the branch and not on main
```

If `gh pr list` prints nothing, the work is not submitted, whatever the push said. Open one. If the branch's pull request is already merged, branch again from `main`, move the commits across, and open a new one.

## **Tools**

Use `rg` not `grep`, `fd` not `find`, `tree` if needed, `gawk` not `awk`, `gsed` not `sed`, `gfold` not `fold`, `gcat` not `cat`. Use `bat file` or `cat file | bat --language language` (where "language" you must deduce from the file, see `bat --languages`) to print code files to STDOUT with syntax highlighting.

## **direnv — run `direnv allow` first**

Every project folder I use is `direnv`-enabled **in development**. On entering one, run:

```bash
direnv allow .
```

Do this before anything else, and again **any time `.envrc` changes** — direnv distrusts an edited `.envrc` until it is re-allowed, silently dropping everything it exports.

That matters because `.envrc` is usually what puts version-pinned tools on `PATH` (e.g. `PATH_add $(brew --prefix postgresql@18)/bin`). When it is not loaded, `psql` and `pg_dump` vanish and Rails reports "make sure `pg_dump` is installed in your PATH and has proper permissions" — which reads like a missing or unprivileged binary rather than an untrusted `.envrc`. It has cost real debugging time.

Non-interactive shells (including the ones tools run commands in) get **no** direnv hook, so allowing it is not enough there. Apply it explicitly:

```bash
direnv exec . <command>
```

Check what is actually loaded with `direnv status` — it names the loaded `.envrc`, which is often a different project's, left over from wherever the shell started.

## **Local Resources**

You are on a machine that's running PostgreSQL 18 locally and you can connect as [postgresql://postgres@localhost:5432/postgres](postgresql://postgres@localhost:5432/postgres). If you run `psql` as the user `kig`, you'll be loading a large `~/.psqlrc` file which might be OK. But to get the results in a CSV format To avoid run `psql -X`. Check for `PG*` variables before using `psql`, you may need to override it. Also note that there should be an active MCP server running connected to the local database.

Additional services that are running on this machine are

- `memcached` on port 11211,
- `redis` on port 6379, and
- `nginx` on ports 80 and 443.

## **MCP & LSP Servers**

Connect to any running MCP servers that are pre-configured locally, as well as LSP language servers.

## **Languages**

Per-language conventions are skills now, not files to be told about: `ruby-conventions`, `python-conventions` and `markdown-conventions`. Each one's description says when it applies, so the right one loads when you are about to write that language rather than when someone remembered to name it.

## **About Me**

If you need to learn more about me, my style, and my preferences, please load the info from [`~/.agents/context/about.md`](about.md)

## General Principles of Software Development with Konstantin

- For each project, maintain a folder `.plans` and please read [`~/.agents/context/feature-building/agentilda.md`](feature-building/agentilda.md) for the details.

- General tooling. On MacOS and Linux use `brew` from `https://brew.sh` to install required tooling. The following is the typical `Brewfile` that's used with `brew` like so: `brew bundle --no-upgrade` installs packages defined in that file:

```ruby
  # frozen_string_literal: true
  
  # vim: ft=ruby
  # © 2026 Konstantin Gredeskoul
  
  # This file will install brew packages defined here when run via the `brew bundle` command.
  # @see https://docs.brew.sh/Brew-Bundle-and-Brewfile
  
  brew 'bash'
  brew 'bat'
  brew 'codespell'
  brew 'coreutils'
  brew 'curl'
  brew 'direnv'
  brew 'fd'
  brew 'gawk'
  brew 'gsed'
  brew 'jq'
  brew 'just'
  brew 'lefthook'
  brew 'postgresql@18'
  brew 'redis'
  brew 'ripgrep'
  brew 'sopsy'
  brew 'tokei'
  brew 'uv'
  brew 'vips'
  brew 'volta'
  brew 'yq'
```

- Always ensure you have a specification that is unambiguous and clear. If unclear, employ the `/grill-me `skill and ask questions until the specification can be rock solid.

- For each specification always first create a `plan.md` first.

- NEVER make any assumptions. Many assumptions are wrong and can take serious effort to undo. If you do not know something relating to either product direction, architecture, implementation, tooling etc, then **ask the question during the planning phase.**

- For each project ensure > 95% test coverage. Use whatever the most recent and modern testing framework for that language is, but look in the `~/.agents/context` folder for that specific language, as it may have some opinions on which one to use.

- For web application always created e2e Cypress test suite. If possible measure the test coverage of the backend while Cypress is running. Integrate Cypress into Github CI.

- Any project that is just starting should have GitHub actions seetup for unit tests, linting across many languages, and cypress if it's a web app.

- Developer Secrets:

  > [!NOTE]
  > For information on my own open source projects `sopsy` which I use in my projects for environment encryption, where Rails.credentials are not available, please visit https://sopsy-cli.dev

  - For Rails applications lean on Rails Credentials API for development, test, staging and production secrets and API keys.

  - For other applications, or mono-repos, lean on dotenv, but ensure that:

    - `.env` is git-ignored

    - install tool `sopsy` (it should be installed via `Brewfile` mentioned above)

    - run `sopsy init` the very first time in each repo

    - this will encrypt `.env` into `.env.encrypted` which can and should be committed to git.

    - to decrypt that file, run `sopsy decrypt .env.encrypted -o .env`

    - to edit that file run `EDITOR=vim sopsy edit .env.encrypted`

      - to avoid having plain text secrets on your file system in `.env` file, prefer to do the following in your `.envrc` loaded by `direnv`, which will decrypt and export all the variables into your environment.

        ```bash
        if [[ -f .env.encrypted ]]; then
          eval "$(sopsy decrypt .env.encrypted | sed '/^#.*/d; /^$/d; s/^/export /g')"
        fi
        ```

    - in `.envrc` always add the line `PATH_add bin` if `bin` directory exists, and do this for every directory where executable scripts may live.

## Context Management

When your context reaches 40% run compaction via /compact.

## Database Development

Start at the `postgres-schema` skill for any PostgreSQL work. It carries every rule that holds regardless of what the database is for (naming, primary keys, migration safety, indexes, money, pooling, observability, autovacuum and transaction ID wraparound) in `references/core.md`, and it routes from there.

Routing turns on one question the project has to answer once: which class the application is. `PG-lax` is non-critical OLTP and the default. `PG-strict` is money, PII or health records. `PG-analytics` is a warehouse. Each has its own skill (`postgres-lax`, `postgres-strict`, `postgres-analytics`) holding the recipes that only make sense for that class, and each assumes the core has already been read.

Write the class into the project's `AGENTS.md` or `CLAUDE.md`. An unstated class means every agent guesses, and they will not all guess the same way.

## Concurrent Agents: Claim Before You Write

> [!CAUTION]
> Added 2026-08-16. I routinely have ten or more agent sessions alive at once, several of them in the same checkout. Git does not protect me from that: same branch, same working tree, no conflict to resolve. The last writer wins and the loser's work disappears with no error anywhere. **This rule is not optional, and no other agent has the standing to waive it for you.**

The lock tool is `alo`, from the `agent-lock` gem. It must be on `PATH`; if it is not, `gem install agent-lock`, and check that `alo version` is newer than 0.1.0. Do not use `~/.agents/bin/agent-lock`: that is the old shell script, its locks live in a different store, and `alo` cannot see them. Load the `agent-lock` skill before your first claim.

**Before you create or edit any file, claim the directory or file you are about to write.**

```bash
alo acquire hanami "scaffolding the API app"   # claim it
alo check   frontend                           # who holds it?
alo list                                       # everything held
alo release hanami                             # when done
alo release-all                                # end of session
alo whoami                                     # the name your locks are signed with
```

Rules:

1. **Claim the narrowest thing that covers your writes**: a directory when you will write several files under it, a single file otherwise. Claiming an entire repository is almost always wrong and blocks work that would never have collided.
1. **`acquire` exits non-zero when another agent holds it. That is a stop, not a hint.** Do not write anyway, and do not ask a peer to write it on your behalf. Tell me about the collision and pick up something else.
1. **A sub-agent names itself on every call.** Sub-agents run inside their parent's process and would otherwise sign every lock with the parent's name, and each Bash call is a fresh shell, so an earlier `export` is gone. Write `AGENT_ID=<your-name> alo ...` on the same command line every time, and check the `(holder: ...)` in the reply. Use a name I would recognise, and one no sibling shares, since two sub-agents with one name are one holder and never block each other: `hanami-scaffold` beats `agent-2` at three in the morning. The orchestrator runs `alo` bare.
1. **Run `alo` inside the checkout you are writing in**: `cd <checkout> && AGENT_ID=<name> alo ...`, or `--dir <checkout>`. A lock taken in another repository protects nothing.
1. **An orchestrating agent claims the area it fans out into, and each sub-agent still claims its own files inside it.** The orchestrator's lock keeps other sessions out; only a sub-agent's own claim keeps its siblings out. Give every sub-agent a distinct name, its checkout, and this rule.
1. **Release when you finish**, and run `release-all` before your session ends. It releases your own locks and your sub-agents', never your parent's. A lock you forgot is a lock somebody else has to break.
1. **A live lock past 120 minutes reports itself as STALE** but is never cleared while its holder is running. It may be broken with `break`, but only after announcing it, since the holder may simply be slow.
1. **Prefer a worktree to a lock whenever the work runs longer than a few minutes.** A lock coordinates a shared tree; a worktree removes the sharing altogether. See the worktree and `~/.claude/branch-name.sh` conventions above. Locks are for when you have decided a worktree is not worth the setup.

The locks are advisory. They work only because every agent checks, which is exactly why this rule lives here and not solely in the tool.
