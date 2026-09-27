---
name: ruby-cli-add-command
description: >
  Add a new top-level command to an existing dry-cli Ruby gem, following the
  ruby-cli-tools conventions: command class, registration, flags, -n and -i
  where they apply, Aruba and unit specs, README and CHANGELOG. Use when the
  user runs /ruby-cli-add-command, or asks to add a command, verb or action to
  a Ruby CLI that is built on dry-cli.
argument-hint: "COMMAND [what it does, in a few words]"
metadata:
  author: Konstantin Gredeskoul
  version: "1.0.0"
---

# Add a command to a Ruby CLI gem

Arguments: `$ARGUMENTS`. The first word is the command name; anything after it says what the command does. With no arguments, ask for the name and the purpose before touching a file.

Load the `ruby-cli-tools` skill first. Every convention this skill applies (streams, flags, `-n`, `-i`, Zeitwerk layout, Aruba in-process) is defined there, and this skill only says where each one lands for a new command.

## 1. Read the gem before writing

Find, and read, each of these. They decide where the new code goes.

- `lib/<gem>/cli.rb`: the registry. Note how existing commands are registered and whether aliases are used.
- The base command every command inherits from, and the shared flags it declares with `self.inherited`.
- `lib/<gem>/launcher.rb`, and how a command reaches STDIN.
- One existing command and its spec, as the pattern to copy.

If the gem has no Launcher or no base command, it does not follow the conventions yet. Say so, and ask whether to add those first or to match what is there. Adding a command in a different style than its neighbours makes the gem harder to read than either style alone.

A command named like an existing one, or like one of its aliases, is a collision. Stop and ask.

## 2. Decide what the command declares

Answer these from the purpose, and ask only about what the purpose leaves open:

- **Does it change state** (files, network, a database)? Then it takes `-n` / `--dry-run`, and a dry run changes nothing. A read-only command does not declare it.
- **Does it take options?** Then it takes `-i` / `--interactive`, with the behaviour in the skill's Interactivity section.
- **Are its defaults obvious, or readable from the defaults file?** Then it also takes `-y` / `--yes`.
- **What is its work product?** That goes to STDOUT, uncolored when piped. Everything else goes to STDERR.
- **Paths it operates on** are arguments, not flags.

Every option has a short and a long form, and booleans are `type: :boolean`.

## 3. Write it

- `lib/<gem>/cli/<command>.rb`: the command class. Keep it to parsing and delegating; put the work in a namespace next to it, grouped by what it does (or behind the domain facade, if the gem has domains).
- Register it in `cli.rb` the same way its neighbours are registered. Shell completion reads the registry, so there is nothing else to wire up.
- `spec/<gem>/cli/<command>_spec.rb`: Aruba, in-process, with `run_command_and_stop(cmd, fail_on_error: false)`. Cover the exit code, what lands on STDOUT and what lands on STDERR, `--help`, a bad argument, and `--dry-run` changing nothing when the command has it.
- If it has `-i`: a unit spec that feeds answers through a `StringIO` whose `tty?` returns true, including ENTER keeping a default and a bad answer being asked again. Also check that `-i` without a terminal fails, and that `-i -y` is a usage error.
- `README.md`: add the command where the top-level commands are listed. `CHANGELOG.md`: add a line under the unreleased heading.

## 4. Verify

Run each, and report what it printed:

```bash
bundle exec rake                   # specs and RuboCop, both green
bundle exec exe/<gem>              # the new command appears in the listing
bundle exec exe/<gem> <command> -h # its help reads correctly
```

Then run the command once for real with representative arguments, and once more with `-n` if it has it.
