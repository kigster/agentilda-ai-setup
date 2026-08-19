# Initial Setup

This specification is about the initial setup of the agents repo.

## 1. Checkout

The initial setup relies on the script `bin/setup`:

```bash

bin/setup — wire ~/.agents into ~/.claude.

  bin/setup              # link everything that is not already there
  bin/setup --dry-run    # say what it would do, touch nothing
  bin/setup --force      # also repoint symlinks aimed somewhere else

What it does:

  ~/AGENTS.md            -> .agents/AGENTS.md
  ~/.claude/CLAUDE.md    -> ../.agents/AGENTS.md
  ~/.claude/<dir>        -> ../.agents/<dir>          for each shared folder

It is a RECONCILER, not an installer: run it as often as you like. Anything
already correct is reported and left alone, so the safe response to "did I
ever link that?" is to run it again.

Two rules it will not break:

  1. It never replaces a real file or directory. ~/.claude holds Claude
     Code's own state — settings.json, projects/, history — and a setup
     script that overwrites those is a data-loss bug wearing a helpful hat.
     Conflicts are reported and skipped.

  2. Links are RELATIVE. ~/.claude/skills/foo -> ../../.agents/skills/foo
     survives this whole tree being cloned to another machine under a
     different $HOME, which absolute paths do not.

Where a shared folder already exists in ~/.claude as a real directory — as
skills/ does, holding one symlink per skill — setup descends one level and
links the children that are missing. That case is the whole reason this
script exists: skills added after the initial link were invisible to Claude
Code because nothing ever linked them.

```

