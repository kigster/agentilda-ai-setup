---
name: ruby-cli-add-subcommand-to
description: >
  Add a subcommand under an existing command of a dry-cli Ruby gem (for
  example `mycli cook breakfast`), following the ruby-cli-tools conventions:
  nested registration, Zeitwerk file layout, flags, -n and -i where they
  apply, specs, README and CHANGELOG. Use when the user runs
  /ruby-cli-add-subcommand-to, or asks to nest a command under another one in
  a Ruby CLI built on dry-cli.
argument-hint: "[COMMAND] [SUBCOMMAND] [what it does, in a few words]"
metadata:
  author: Konstantin Gredeskoul
  version: "1.0.0"
---

# Add a subcommand to a Ruby CLI gem

Arguments: `$ARGUMENTS`. The first word is the parent command, the second is the new subcommand, and anything after them says what the subcommand does.

- No arguments: list the gem's registered commands and ask which one is the parent.
- Only a parent: ask for the subcommand's name and purpose.

Load the `ruby-cli-add-command` skill and follow it. Everything there applies to a subcommand: reading the gem first, deciding on `-n`, `-i` and `-y`, the specs, the README and CHANGELOG, and the verification. This skill covers only what nesting changes.

## What nesting changes

**The parent must exist.** If `COMMAND` is not registered, stop and offer `/ruby-cli-add-command COMMAND` first.

**The parent may be a leaf today.** If `COMMAND` is registered as a command class with no subcommands, adding one changes what `mycli COMMAND` does on its own. Ask which the user wants:

1. The parent becomes a namespace only. `mycli COMMAND` then lists its subcommands, and what it used to do moves into a subcommand the user names.
1. The parent keeps its behaviour and also gains subcommands.

Do not pick for them. Either choice changes what an existing invocation does, and scripts may depend on it. Record the answer in the CHANGELOG.

**Registration nests.** Register the subcommand inside the parent's block in `cli.rb`, the same way any existing nested command is registered:

```ruby
register "cook", aliases: ["c"] do |prefix|
  prefix.register "breakfast", CLI::Cook::Breakfast
end
```

**The file nests.** `lib/<gem>/cli/<command>/<subcommand>.rb` defines `CLI::<Command>::<Subcommand>`. Zeitwerk allows `cook.rb` and a `cook/` directory side by side. If `<command>.rb` does not exist yet because the parent is only a namespace, Zeitwerk makes the module from the directory; do not add an empty file for it.

**The spec nests too:** `spec/<gem>/cli/<command>/<subcommand>_spec.rb`. Also check that `mycli COMMAND` alone, and `mycli COMMAND -h`, now list the new subcommand.

**Flags shared by the parent's subcommands** go on a base class for that group, declared once with `self.inherited`, the same way the gem's global flags are. Do not copy them onto each subcommand.

**Verify** with the steps from `ruby-cli-add-command`, plus:

```bash
bundle exec exe/<gem> <command>             # lists the new subcommand
bundle exec exe/<gem> <command> <sub> -h    # its help reads correctly
bundle exec exe/<gem> completion zsh | rg <sub>  # completion knows about it
```
