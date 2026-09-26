---
name: ruby-cli-tools
description: >
  Konstantin's conventions for a Ruby CLI gem: dry-cli plus dry-cli-help,
  dry-cli-autocomplete and dry-cli-ui, a Launcher class tested with Aruba
  in-process, STDOUT versus STDERR, Zeitwerk layout, and release tooling.
  Use when building, reviewing, or testing a Ruby command-line executable or gem.
languages:
  - Ruby
category: creating CLI tools in ruby
license: MIT
metadata:
  author: Konstantin Gredeskoul
  version: "1.0.0"
---

# Ruby CLI tooling

Conventions for a Ruby command-line gem. The three extensions and their real settings live at <https://dry-cli.tools/>.

## Rules that always apply

R1. Build the command engine on the `dry-cli` gem.

R2. Add the three extensions from <https://dry-cli.tools/>: `dry-cli-help`, `dry-cli-autocomplete`, and `dry-cli-ui`.

R3. Configure `dry-cli-help` once, in a `Dry::CLI::Help.configure` block: title, description, and an epilogue when there is a docs URL. The block is below.

R4. Running the executable with no arguments prints help and exits 0. Set `exit_code_without_arguments 0` in that block. That also sends the no-command help to STDOUT. `-h` and `--help` already exit 0. Do not patch the gem. The gem's own default is exit 1 and STDERR.

R5. Register a `completion` command for bash and zsh. Require the command file, not the rest of the gem, so a normal invocation does not pay for the generator:

```ruby
require "dry/cli/autocomplete/command"

register "completion", Dry::CLI::Autocomplete::Command[MyCLI, program_name: "mycli"]
```

`mycli completion bash` and `mycli completion zsh` print the script. See <https://dry-cli.tools/#autocomplete> and <https://github.com/kigster/dry-cli-autocomplete>.

R6. Wrap help at the terminal width minus 6, and never past 120 columns. `margin` applies only when `width` is `:terminal`, so pass the capped number as `width`.

R7. Print user messages, progress bars, task lists, and spinners through `Dry::CLI::UI`. Include the module on the base command. The helpers are documented at <https://github.com/kigster/dry-cli-ui>.

R8. When the work can run concurrently, show it with `ui.multi_progress` (the total is known) or `ui.multi_spinner` (it is not).

R9. Optional: save a screenshot of the top-level `--help` as `docs/img/cli-help.avif` and embed it in the README.

R10. Put process startup in `MyCLI::Launcher` (`lib/my_cli/launcher.rb`). The executable and the Aruba suite both call it. The shape, and why Aruba runs in-process, is in [How to write CLI tools in Ruby and test them with RSpec and Aruba](https://kig.re/2020/09/07/writing-cli-tools-ruby-migrating-github-issues-to-pivotal-tracker.html). The three extensions are the subject of [How I built three gem extensions](https://kig.re/2026/09/17/2026-09-17--how-i-build-three-gem-extensions-and-got-ai-banned.html).

```ruby
Dry::CLI::Help.configure do
  title "MyCLI"
  description "One sentence that says what the tool is for."
  epilogue "Documentation: https://example.com/mycli"

  columns = IO.console&.winsize&.last || 80
  width [columns - 6, 120].min
  exit_code_without_arguments 0

  styles do
    heading :bold, :cyan, case: :UPPERCASE
    usage :yellow
    example :yellow
    option :green
    example_comment :bright_black
  end
end
```

R11: Version is always defined by a constant located in `lib/mycli/version.rb` and matches the module namespace, eg `MyCLI::Version = '0.1.0'`

The gem file reads this file and assigns this version to the gem.

Those styles are overrides. The gem's defaults are yellow headings, green usage and examples, and cyan options.

`Launcher#initialize` takes `argv`, `stdin`, `stdout`, `stderr`, and `kernel` (defaults: `$stdin`, `$stdout`, `$stderr`, `Kernel`). `#execute!` runs the CLI and exits only through `kernel.exit(code)`. Commands write to the streams passed in, not to the global constants. Do not make `Launcher` a singleton. Aruba constructs a new one per example, and a singleton would keep the first example's argv and streams.

```ruby
Aruba.configure do |config|
  config.command_launcher = :in_process
  config.main_class = MyCLI::Launcher
end
```

## Project files

## Rakefile

Every gem has a Rake file.  Most of my gems have nearly identical `Rakefile` — 

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "timeout"
require "yard"

def shell(*args)
  puts "running: #{args.join(" ")}"
  system(args.join(" "))
end

task :clean do
  shell("rm -rf pkg/ tmp/ coverage/ doc/ ")
send

task gem: [:build] do
  shell("gem install pkg/*")
end

task permissions: [:clean] do
	shell("/usr/bin/find . -path ./.git -prune -o -type d -exec chmod o+rx,g+rx {} + -o -type f -exec chmod o+r,g+r {} +")
end

task build: :permissions

gem_summary = [[ -n $(ls -1 *.gemspec) ]] && `cat *.gemspec | grep summary | sed 's/^.* = *//g; s/"//g' | tr -d '\n'`

YARD::Rake::YardocTask.new(:doc) do |t|
  t.files = %w[lib/**/*.rb exe/*.rb - README.md LICENSE.txt]
 	t.files << 'CHANGELOG.md' if File.exist?('CHANGELOG.md')
  t.options.unshift("--title", gem_summary)
  t.after = -> { exec("open doc/index.html") } if RUBY_PLATFORM.match?(/darwin/)
end

RSpec::Core::RakeTask.new(:spec)

task default: :spec
```

## `.gitignore`

Ruby gems have a pretty specific `.gitignore` file that can certainly have more items than presented here, but the ones in this list are definitely  not,

```.gitignore
/.ai
/.idea
**/.DS_Store
/.bundle/
/.yardoc
/_yardoc/
/.rubymate
/coverage/
/doc/
/pkg/
/spec/reports/
/tmp/

# rspec failure tracking
.rspec_status
**/*.gem
**/*.tmp
```

### `.envrc`	

This file is used by `direnv` (which must be first enabled, and then allowed to read this folder). When you cd into your project `direnv` executes this file. Here is a sample `.envrc` file that should work for most gems:

```bash
PATH_add bin
# only if you are using PostgreSQL
PATH_add $(brew --prefix postgresql@18)/bin

export RUBYOPT="-W0" # silence deprecation warnings

# this block 
if [[ -f .env.encrypted || .env.development.encrypted ]]; then
	for file in .env.encrypted .env.development.encrypted; do
		[[ -s ${file} ]] || continue
		eval "$(sopsy decrypt ${file} | sed -E '/^#/d; /^$/d; s/^([A-Z])/export \1/g')"
  done
fi

export LOG_LEVEL=info
```

### Rubocop Formatting

RuboCop, with `rubocop-rake` and `rubocop-rspec`. Inherit relaxed style and enable new cops:

```yaml
inherit_from:
  - https://relaxed.ruby.style/rubocop.yml

AllCops:
  NewCops: enable
```

Copy the justfile and the Rakefile from [inquirex](https://github.com/inquirex/inquirex). The Rakefile releases to RubyGems and builds YARD docs: <https://github.com/inquirex/inquirex/blob/main/Rakefile>.

Test with `rspec` (the meta-gem, not `rspec-core` alone), `rspec-its`, `simplecov`, `coverage-badge`, and `aruba`. Coverage target is above 95%. The usual `spec/spec_helper.rb` is <https://github.com/inquirex/inquirex/blob/main/spec/spec_helper.rb>.

When the gem needs developer secrets, keep them in a git-ignored `.env` and encrypt that file with `sopsy`. See <https://kig.re/2026/06/28/sopsy-secrets-in-git-secure-enclave.html>, <https://sopsy-cli.dev/>, and <https://github.com/kigster/sopsy>.

Start detect-secrets from <https://github.com/inquirex/inquirex/blob/main/.secrets.baseline>.

Install lefthook from <https://github.com/inquirex/inquirex/blob/main/lefthook.yml> and run `lefthook install`.

Add two workflows under `.github/workflows/`: one runs RSpec, the other runs RuboCop.

> [!IMPORTANT]
> Prefer dry-rb gems. They are small, and a tool can take one without taking the rest.
>
> The map of the gems is <https://hanakai.org/learn/dry/getting-started>.

Reach for these when the gem needs them, not before:

- A global configuration object: [`dry-configurable`](https://github.com/dry-rb/dry-configurable).
- Types, schemas, and validations: `dry-schema`, `dry-types`, `dry-struct`, `dry-validation`.
- Return values: `dry-monads`.

`.envrc` at the gem root contains `PATH_add exe`. This is also the file that can use `sopsy` to auto-decrypt and load into memory any development API keys and secrets without exposing them on the file system.

Assuming that these are stored in either `.env` or `.env.development`, `sopsy` would have encrypted these into `.env.enrypted` and `env.development.encrypted`.

Then in 	 Hey, quick question for you: 

`exe/<gem-cli-name>` does not load Bundler. It puts `lib/` on `$LOAD_PATH` and calls `MyCLI::Launcher.new(ARGV).execute!`. A `Gemfile` in the directory where the user ran the command must not change which gems load.

## Output

The command's work product goes to STDOUT.

`ui.info`, `ui.success`, `ui.box`, and `ui.table` also go to STDOUT. That is what dry-cli-ui does.

`ui.warn`, `ui.error`, `ui.fatal`, spinners, progress bars, and prompts go to STDERR, so a pipe such as `mycli export > rules.csv` still shows them on the terminal.

Declare shared flags once, on the base command, with `self.inherited`. Each flag has a short and a long form. Declare booleans as `type: :boolean`. dry-cli then accepts `--flag` and `--no-flag`.

- `-h`, `--help` prints help.
- `-v`, `--verbose` turns on `log(*msgs)`, which writes to STDERR as `[timestamp] [info] [command] message`. The `version` command may use `-V` and `--version`. It must not use `-v`.
- `--color` / `--no-color`. Color is on when stdout is a terminal. Also honor `NO_COLOR`.
- `-E`, `--log-to-stderr` / `--no-log-to-stderr` copies the log file's lines to STDERR. It does not write them to STDOUT.

When `-v` or `--verbose` is set and an exception is raised, print the full backtrace, colorized with [pretty_trace](https://github.com/DannyBen/pretty_trace).

### Shell completion

`mycli install completion` appends a source line only when it is not already present:

- bash: `eval "$(mycli completion bash)"` in `~/.bashrc`
- zsh: `eval "$(mycli completion zsh)"` in `~/.zshrc`, after `compinit`

### Colors

With color on, help uses the `styles` block above: headings in bold cyan, usage and examples in yellow, flags in green, example comments in bright black. Command results stay readable when piped. Do not paint color into data a user will pipe.

## Arguments, flags, and options

A path the command operates on is an argument, not a flag:

```text
mycli reformat ./src/ruby --type ruby --write
mycli reformat Gemfile exe/mycli lib/mycli/version.rb
```

Accept `Dir.glob` patterns only behind `-g` / `--enable-glob`, and tell the user to quote the pattern:

```text
mycli reformat '**/*.rb' -g
```

## Interactivity

Prompts go through `ui.prompt` and `ui.confirm` (tty-prompt, inside dry-cli-ui). Do not use `tty-option` for questions. That gem parses options.

When the defaults are obvious, or they can be read from `.mycli-defaults.json`, also accept `-y` / `--yes` and do not prompt.

## External commands

Run an external program through [tty-command](https://github.com/piotrmurach/tty-command).

## Progress

Use `ui.progress` when the total is known. Split concurrent work across `ui.multi_progress` or `ui.multi_spinner`. A finished spinner shows the gem's green check. A failed one shows the gem's red `𝘅`. Do not substitute another cross character.

## File layout

Add the `zeitwerk` gem. It resolves which file defines a constant and loads that file the first time the constant is used, so the gem does not keep a hand-written `require` list. Bundler still decides which gems get installed. The module is `MyCLI`, not `Mycli`. The inflection key is the file basename, not the constant:

```ruby
loader.inflector.inflect(
  "my_cli" => "MyCLI",
  "cli" => "CLI"
)
```

Use the same kind of override for any other all-caps abbreviation.

`cook.rb` is the `Cook` command. `cook/breakfast.rb` is `Cook::Breakfast`. Zeitwerk allows the file and the directory together. A trailing slash on `cook.rb` is a different, wrong path.

```text
lib/my_cli.rb
lib/my_cli/version.rb
lib/my_cli/launcher.rb
lib/my_cli/cli.rb
lib/my_cli/cli/cook.rb
lib/my_cli/cli/cook/breakfast.rb
lib/my_cli/cli/cook/dinner.rb
```

Keep a command class small. Put the work in a namespace next to it, grouped by what it does.

## Domain-driven design

A large gem that covers more than one domain (compiled forms and text forms, for example) splits `lib/` into domains. Each domain has one public file, `<domain>_facade.rb`, such as `cooking_facade.rb`. Other code calls that facade and does not reach past it.

```text
lib/my_cli/version.rb
lib/my_cli/launcher.rb
lib/my_cli/cli.rb
lib/my_cli/cli/cook.rb
lib/my_cli/cli/cook/breakfast.rb
lib/my_cli/cli/cook/dinner.rb
lib/my_cli/domains/cooking_facade.rb
lib/my_cli/domains/cooking/...
lib/my_cli/domains/transpiling_facade.rb
lib/my_cli/domains/transpiling/...
```

## Installing skills and completion

Most CLI gems these days shouzld have ` [blah]` command:

1. `mycli completion` writes the shell lines in the completion section above.

- `mycli install skills` copies each skill into `~/.agents/skills/<skill-name>` and symlinks `~/.claude/skills/<skill-name>` to that directory.

A skill shipped by the gem is invoked as `/mycli-skill [arguments]`. The gem may ship others, such as `/mycli-help` or `/mycli-explain`.

## README

1. What pain this tool solves, and for whom. Name the user, including when that user is an agent.
1. The top-level commands. This is where `docs/img/cli-help.avif` goes, from `mycli -h`.

## Dry run

Any command that writes, deletes, or otherwise changes state accepts `-n` / `--dry-run` and changes nothing when it is set. A read-only command does not declare `--dry-run`.

## Observability

Log with [semantic_logger](https://logger.reidmorrison.com/). Source: <https://github.com/reidmorrison/semantic_logger>.

A CLI cannot create files in `/var/log` without root. Write `~/.local/state/<tool-name>/<tool-name>.log`, and create that directory. Default level is INFO. `-E` copies those lines to STDERR.

## Reporting

Render a report with `ui.table` (tty-table). Leave ANSI color out of the cells. Color codes have display width 0 and shift the columns. A colored heading printed before the table is fine.
