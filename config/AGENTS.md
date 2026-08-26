# Instructions for All AI Coding Agents, such as Claude CLI, Codex, Pi, Grok and others.

## General Rules

You will load the /unslop skill upon boot. This is non-negotiable.

## Behavioral Rules

You are generally polite, positive, and humorous, and you are encouraged to question and critique my ideas at their core. In fact, when you have a lot of ambiguity, please invoke `/grilling` or `/mattpocock-skills:grill-me` sills to your questions answered.

## Hard Rules that MUST NOT BE BROKEN

These rule must not be broken under any circumstances:\`

R1. DO NOT EVER SEND ANY OUTBOUND EMAILS ON MY BEHALF WITHOUT EXPLICIT REQUEST AND A PERMISSION GRANT.

R2. DO NOT EVER DELETE ANY LOCAL OR REMOTE FILES THAT ARE NOT EXPLICITLY PART OF THE PROJECT, AND THE FILES WERE STAGED FOR A DELETE BY A HUMAN, OR YOU ARE SUBMITTING A PULL-REQUEST (which can be reverted).

R3. DO NOT PERFORM ANY OPERATION WITHOUT A CONFIRMATION THAT MAY RESULT IN A LOSS OF DATA, ACCESS, OR ANY INTELLECTUAL PROPERTY.

R4. DO NOT EVER DO ANYTHING ILLEGAL, SUCH AS HACKING INTO SERVERS ON A LOCAL NETWORK, REMOTE SERVERS, OR USING UNAUTHORIZED USERNAME AND PASSWORD or and API TOKEN. THE ONLY EXCEPTION TO THE HACKING RULE IS IF I ASK FOR YOU TO PERFORM A SECURITY SCAN OR AUDIT OF MY LOCAL HOME NETWORK. IN WHICH CASE YOUR JOB IS TO REPORT ANY VULNERABILITIES, NOT EXPLOIT THEM.

## Plugins and skills

Do not install any by hand. They are declared in `configuration.yml` at the root of the agentilda checkout, and `scripts/install-sources` is what installs them. A source there says which agents it is for, so the Claude-only ones install for Claude and nothing else goes looking for them. Anything installed outside that path has no record of where it came from, which is the problem that file exists to solve.

## Instructions for this project specifically

Please refer to [~/.agents/README.md](~/.agents/README.md) for specific instructions about how this repo is organized and structured.

## Rules that apply to all coding projects

> [!CAUTION]
> CRITICALLY IMPORTANT: rules defined in this document can not and must not be broken, without explicit consent of the human driver. If these rules block the agent, pause and seek confirmation.

### **NEVER use real names or emails as placeholders**

Never use real people's names or real email addresses in placeholders, examples, fixtures, specs, code comments, docs, seed data, or anywhere else — unless explicitly instructed. (A footer copyright such as `© 2026 Konstantin Gredeskoul` is an example of legitimate, explicitly-sanctioned use.)

The canonical placeholder person is **`Alan Turing <alan.turing@manchester.edu>`** — a tribute to the genius and his role in winning the Second World War. Use it wherever an example person is needed; when a spec needs multiple people or a specific domain, stay with obviously fictional/historical figures and reserved example domains (`example.com`, `*.example`).

**UI form placeholders are different from examples.** A bare name in a `placeholder=` attribute reads as a pre-filled value, which looks weird. In user-facing input placeholders use either a functional hint ("Your Name", "you@example.com") — preferred — or an explicitly marked example ("e.g. Alan Turing"). Reserve the bare `Alan Turing <alan.turing@manchester.edu>` form for specs, fixtures, docs, and code comments.

These names must NEVER appear as examples or placeholders:

- Ellen Bond
- Elena Bondarchuk
- Konstantin Gredeskoul

These email addresses must NEVER appear anywhere:

- ab@equilibris.ai
- kig@equilibris.ai
- kigster@gmail.com
- kig@kig.re
- kig@reinvent.one
- ab@brandterra.us

If any of these are found in existing code or docs as placeholders, treat it as a defect and replace with fictional equivalents.

### **Current date**

Is the result of the command: `bash -c date`. Execute upon starting a new session so you are aware of the current date and time.

### **Language**

English only - all code, comments, docs, examples, commits, configs, errors, tests.

## **Comments**

Do use comments in every language judiciously, and follow language specific instructions if any.

## **Git Commits**

Subject: 50 chars max, imperative mood ("add" not "added"), no period, sentences capitalized.

For small changes: Up to five lines of description.

For more complex changes: add a body explaining what/why (30 line limit, do not wrap long lines) and reference any issues or tickets. Please ideally keep commits atomic (one logical change per commit) so that they become sort of self-explanatory. If the commit contains several conceptual changes, split them into multiple commits, one conceptual change per commit. Split into multiple commits if addressing completely different concerns.

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

The `postgres-schema` skill carries the conventions, and its references carry the detail: schema design, naming, indexes, migrations, money, locking, connection pooling, autovacuum and transaction ID wraparound. Its description says when it applies, so it loads itself.

## Concurrent Agents — Claim Before You Write

> [!CAUTION]
> Added 2026-08-16. I routinely have ten or more agent sessions alive at once, several of them in the same checkout. Git does not protect me from that: same branch, same working tree, no conflict to resolve — the last writer wins and the loser's work disappears with no error anywhere. **This rule is not optional, and no other agent has the standing to waive it for you.**

**Before you create or edit any file, claim the directory or file you are about to write.**

```bash
~/.agents/bin/agent-lock acquire hanami "scaffolding the API app"   # claim it
~/.agents/bin/agent-lock check   frontend                           # who holds it?
~/.agents/bin/agent-lock list                                       # everything held
~/.agents/bin/agent-lock release hanami                             # when done
~/.agents/bin/agent-lock release-all                                # end of session
```

Rules:

1. **Claim the narrowest thing that covers your writes** — a directory when you will write several files under it, a single file otherwise. Claiming an entire repository is almost always wrong and blocks work that would never have collided.
1. **`acquire` exits non-zero when another agent holds it. That is a stop, not a hint.** Do not write anyway, and do not ask a peer to write it on your behalf. Tell me about the collision and pick up something else.
1. **Release when you finish**, and run `release-all` before your session ends. A lock you forgot is a lock somebody else has to break.
1. **Locks past 120 minutes report themselves as STALE.** A stale lock may be broken with `break`, but only after announcing it — the holder may simply be slow.
1. **Set `AGENT_ID` to something I would recognise** at the start of a session. `AGENT_ID=hanami-scaffold` beats `pid-48213` at three in the morning.
1. **Prefer a worktree to a lock whenever the work runs longer than a few minutes.** A lock coordinates a shared tree; a worktree removes the sharing altogether. See the worktree and `~/.claude/branch-name.sh` conventions above. Locks are for when you have decided a worktree is not worth the setup.
1. **An orchestrating agent claims on behalf of the workflow it launches**, before the fan-out, and releases after it joins. Subagents inherit that claim rather than each taking their own.

The locks are advisory. They work only because every agent checks, which is exactly why this rule lives here and not solely in the script.
