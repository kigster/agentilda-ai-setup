# Agent~ (agentilda)

[![CircleCI](https://dl.circleci.com/status-badge/img/gh/kigster/agentilda/tree/main.svg?style=svg&circle-token=CCIPRJ_DrNBun6pLLc988EVbduHJm_9ec6ada64b6bd9406d19ca4e1aa56a249c20087d)](https://dl.circleci.com/status-badge/redirect/gh/kigster/agentilda/tree/main)



>  [!NOTE]
>
> A vendor-neutral home for the AI instructions, context, skills and tooling that several different AI coding agents share, plus **agentilda**: a small Ruby CLI gem that keeps projects specifications, plans and pull requests joined up, and can drive a team of dedicated agents from specification to completion of a given task, with review harness and proper planning.

------

## Customizing Configuration

Before you proceed to install anything, it is strongly recommended that you:

```bash
cp configuration.example.yml configuration.yml
vim configuration.yml
```

Configuration file defines what skills and plugins and going to get installed in you two global directories:

* `~/.agents` (receivies actual files — eg copies of skills, plugins, etc, does not depend on this repo checkout post install)
* `~/.claude/` (receive symlinks into `~/.agents` to reduce duplication, although some claude-specific plugins are supported as well.)

### Features

* Installs plugins and skills from remote repositories ensuring latest versions
* Can install partial skills from a given repo based on regular expression matching
* Can install plugins by executing commands
* Can install plugins targeting specific AI agent 
* Comes with an executable `agentilda` which a CLI tool written in Ruby that drives a multi-agent workflow, manages `.plans` folders for project (where spec and plans live), syncs with Linear and much more.

## Quick Install

```bash
git clone <this repo> agentilda   # anywhere; this is not the install
cd agentilda
direnv allow .                    # puts bin/, scripts/ & workflow/exe on PATH

bin/install
```

There are three granular steps that you can run independently, or you can skip to the next section and insetall all at once.

1. `scripts/install-sources` assembles `skills/` and `plugins/` in the checkout from `configuration.yml`. Both are **generated** — nothing under either is committed, so a fresh clone has neither until this has run.
1. `bin/install` copies the result into `~/.agents` with every symlink resolved, so it holds real files and the checkout can afterwards be moved, renamed or deleted with nothing left dangling.
1. `bin/setup` links `~/.agents` into `~/.claude`, so that there is no duplication.

## Aggregated Installer

`bin/install` runs all three. The first is not optional and not silent: if `skills/` is missing after the build, it stops rather than installing a tree with no skills in it and reporting success. That usually means `configuration.yml` was only just seeded and is waiting to be read. `--no-sources` skips the build for a checkout you have already built.

`bin/install --dry-run` previews the lot. `--force` is required to replace anything already installed, and to replace a `~/.agents` that is still a symlink to a checkout from the old arrangement.

The trade, deliberately: an edit to `src/skills/foo` reaches `~/.claude` only when you run it again.

### Configuring what gets installed

`configuration.yml` is the file the installer reads. It is git-ignored and per machine, because which skills and which coding agents a machine should have is a property of that machine. A first run copies `configuration.example.yml` across and then stops, so you get to read it before it installs anything.

It has two top-level keys. `agents:` names the coding agents themselves and the vendor's own install line for each:

```bash
scripts/install-sources agents            # which are configured, and which are on PATH
scripts/install-sources agents install    # install the ones that are missing
```

`sources:` names where skills and plugins come from. A source clones a repository (`type: skills` or `type: plugin`) or runs a command (`type: command`, for something like Braintrust's `bt`, which ships its skill through its own CLI rather than a repository). Any source can narrow itself:

```yaml
- name: ruby-marketplace
  type: skills
  repo: https://github.com/hoblin/claude-ruby-marketplace.git
  path: plugins
  include_skills: /\A(rspec|activerecord)\z/   # or exclude_skills, never both
  agents: [claude]                             # or exclude_agents, never both
```

Filters are matched against the name a thing installs as, not its path inside the source. `agents:` is matched against the `agents:` block above, and a source no configured agent would read is skipped and reported rather than installing skills nothing can load.

**Tightening a filter takes skills back as well as adding them.** The next run unlinks whatever it installed last time and no longer installs, so `skills/` converges on what the file says rather than accumulating.

### Keeping it up to date

```bash
bin/install --force            # rebuild, re-copy, re-link; --force replaces what is there
scripts/install-sources -f     # wipe .sources and re-clone every source from scratch
bin/setup --force              # repoint symlinks that aim somewhere else
bin/install --dry-run          # preview all of it, touch nothing
```

`bin/install` never replaces anything already in `~/.agents` without `--force`, and refuses outright to replace a `~/.agents` that is still a symlink to a checkout from the old arrangement.

______________________________________________________________________

## What is in here

| Path                        | What it is                                                   |
| :-------------------------- | :----------------------------------------------------------- |
| `config/AGENTS.md`          | The instructions every agent reads. Symlinked to `~/AGENTS.md` and `~/.claude/CLAUDE.md` |
| `context/`                  | What every agent gets regardless, including about.md which you should update to be about you. |
| `src/skills/`               | Skills authored in this repo (committed); folded into `skills/` by `install-sources` |
| `src/commands/`             | Slash commands that wrap `agentilda` with the right guardrails baked in |
| `skills/`                   | Claude skills, **generated**, one directory per skill, symlinked into `~/.claude/skills/` |
| `plugins/`                  | External plugin bundles (e.g. `pstack`), also generated, not committed |
| `configuration.example.yml` | Committed template for the git-ignored `configuration.yml`, the list `scripts/install-sources` pulls `skills/` and `plugins/` from |
| `bin/`                      | **Bash** executables. `setup` is a pure symlink reconciler   |
| `scripts/`                  | **Ruby**: `install-sources`, which runs before there is a bundle to run it in |
| `docs/`                     | Documentation for people rather than context for agents: runbooks, the coverage badge, usage notes |
|                             |                                                              |

Executables sit in three places, by what each needs in order to run. `bin/` holds shell, `scripts/` holds the one Ruby executable that must work before a bundle exists.

`skills/` and `plugins/` are **not committed**. Both are entirely regenerable from `configuration.yml` plus `src/skills/` (which is committed, since it's this repo's own work). A skill that went stale with no way to tell where it came from was the exact problem `install-sources` exists to solve:

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

## Agentic Workflow

This repository originallhy contained a ruby gem that was the orchestrator of the Agentic Team Workflow. This gem has since been moved out of this repository into it's own, and (hopefully) by the time you read this, it will also be on RubyGems, so you can install it with `gem install agentilda`.

The gem is a Ruby CLI command `tilda` that keeps a project's specifications, plans and pull requests documents in the `.plans`, and drives a team of specialist agents over them. The agents implement the following workflow:

```
# Hppy path
⚪️ New ──▶ 
    🔎 Researched ──▶ 
        ⭐️ Planned ──▶ o
            🟡 Building ──▶ 
                🎨 Building UI ──▶ 
                    🟢 Ready for Review ──▶ 
                    👀 In Review ──▶ 
                        ✅ Approved
```

There are five agents, each tuned for a specific task.

 * research, 
 * then a written specification, 
 * then a plan, 
 * then a frontend end, backend, 
 * submit PR, 
 * and perform an adversarial review.

Install the gem with `gem install agentilda` and then run `tilda -h` for more options. It's also recommended to add command completion to your shell. Eg, for zsh:

```bash
# ~/.zshrc
grep -q agentilda "${HOME}"/.zshrc || echo 'eval "$(agentilda completion zsh)"' >> "${HOME}/.zshrc"
```
______________________________________________________________________

© 2026 Konstantin Gredeskoul, MIT License
