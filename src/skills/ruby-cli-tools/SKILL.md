---
name: ruby-cli-tools
description: >
  Konstantin's conventions for Ruby gems and command-line tools, plus a generator
  that creates a new gem with them already applied: dry-cli with dry-cli-help,
  dry-cli-autocomplete and dry-cli-ui, a Launcher tested in-process with Aruba,
  Zeitwerk, RSpec with SimpleCov, and release tooling. Use whenever the user wants
  to create, scaffold or start a new gem or Ruby CLI, or is building, reviewing or
  testing a Ruby command-line executable, even if they only say "new gem" or
  "bundle gem".
languages:
  - Ruby
category: creating CLI tools in ruby
license: MIT
metadata:
  author: Konstantin Gredeskoul
  version: "1.1.0"
---

# Ruby CLI tooling

Conventions for a Ruby gem, and for the command line most of these gems ship. The three dry-cli extensions and their settings live at <https://dry-cli.tools/>.

This skill's directory holds three things besides this file:

- `scripts/create-gem`: generates a gem with `bundle gem`, then applies everything below.
- `scripts/scaffold.rb`: the part of `create-gem` that renders the templates. You do not run it yourself.
- `assets/templates/`: the files a new gem starts from. These are the source of truth for the Rakefile, `.rubocop.yml`, `.envrc`, `spec_helper.rb`, the Launcher, the command registry and the Aruba setup. Read the template rather than retyping its content from memory.

## Creating a new gem

The script prompts for its values when run on a terminal. Your Bash tool has no terminal, so collect the answers first and pass them as flags.

1. Ask the user for each value in one `AskUserQuestion` call, with the default as the first option marked "(Recommended)", so accepting every default takes one confirmation:

   | Question         | Flag                | Default                    | Choices                          |
   | :--------------- | :------------------ | :------------------------- | :------------------------------- |
   | Gem name         | `-n NAME`           | none; required             | lowercase, dashes nest modules   |
   | CI service       | `-c`                | `github`                   | `github`, `gitlab`, `circleci`   |
   | Test framework   | `-t`                | `rspec`                    | `rspec`, `minitest`, `test-unit` |
   | Linter           | `-l`                | `rubocop`                  | `rubocop`, `standard`            |
   | Command line     | `-u`                | yes, for a CLI gem         | yes adds `-u`; needs `-t rspec`  |
   | Native extension | `-x`                | `none`                     | `none`, `c`, `go`, `rust`        |
   | MIT license      | `--no-mit` when no  | yes                        |                                  |
   | GitHub username  | `--github-username` | `github.user` in gitconfig | ask only when that key is unset  |

   Take a value the user already gave in the request as answered, and do not ask it again.

1. Run the script from the directory that should contain the gem:

   ```bash
   <skill-dir>/scripts/create-gem -n acme-tool -c github -t rspec -l rubocop -u
   ```

   It runs `gem update --system` (a failure there only warns), `bundle gem` with `--exe --changelog --git --bundle`, adds the default gems, renders the templates, installs, and autocorrects with the chosen linter. It stops if the target directory already exists.

1. Done means `bundle exec rake` in the new gem has run and you have reported its result. Bundler's sample test fails on purpose, and it stays, so one failure is expected until the user writes a real test. With `-u`, run `exe/<gem> demo` as well.

What every gem gets:

- Tests: `rspec` (the meta-gem, not `rspec-core` alone) with `rspec-its`, or the chosen framework. `simplecov` with `coverage-badge`, starting in the spec or test helper, with a coverage floor of 95%.
- Development: `rake`, `yard`, the linter, and for RuboCop `rubocop-rake` and `rubocop-rspec`.
- `Rakefile`, `.envrc`, `.rubocop.yml` and the additions to `.gitignore` from `assets/`.

With `-u` the gem also gets the command line the rest of this skill describes: a Launcher, a Zeitwerk loader, a registry with `version`, `completion` and a `demo` command that runs jobs in parallel threads under `ui.multi_progress`, and an Aruba suite covering all three. The gem's module takes the `CLI` spelling (`MyCLI`, `Acme::CLI`), and the gemspec requires Ruby 4.0, which dry-cli-help and dry-cli-ui need.

## Rules that always apply

R1. Build the command engine on the `dry-cli` gem.

R2. Add the three extensions from <https://dry-cli.tools/>: `dry-cli-help`, `dry-cli-autocomplete`, and `dry-cli-ui`.

R3. Configure `dry-cli-help` once, in a `Dry::CLI::Help.configure` block: title, description, and an epilogue when there is a docs URL. The block, with the house styles, is in `assets/templates/ui/lib/__PATH__/cli.rb.nest.erb`. Those styles are overrides: the gem's own defaults are yellow headings, green usage and examples, and cyan options.

R4. Running the executable with no arguments prints help and exits 0. Set `exit_code_without_arguments 0` in that block, which also sends the no-command help to STDOUT. `-h` and `--help` already exit 0. Leave the gem unpatched: its own default is exit 1 and STDERR.

R5. Register a `completion` command for bash and zsh. Require the command file, not the rest of the gem, so a normal invocation does not pay for the generator:

```ruby
require "dry/cli/autocomplete/command"

register "completion", Dry::CLI::Autocomplete::Command[MyCLI, program_name: "mycli"]
```

`mycli completion bash` and `mycli completion zsh` print the script. See <https://dry-cli.tools/#autocomplete> and <https://github.com/kigster/dry-cli-autocomplete>. The command prints to `$stdout` rather than the stream dry-cli hands it, so an in-process Aruba test reads it with RSpec's `output(...).to_stdout`.

R6. Wrap help at the terminal width minus 6, and never past 120 columns. `margin` applies only when `width` is `:terminal`, so pass the capped number as `width`.

R7. Print user messages, progress bars, task lists, and spinners through `Dry::CLI::UI`. Include the module on the base command. The helpers are documented at <https://github.com/kigster/dry-cli-ui>.

R8. When the work can run concurrently, show it with `ui.multi_progress` (the total is known) or `ui.multi_spinner` (it is not). The generated `demo` command is the working example.

R9. Optional: save a screenshot of the top-level `--help` as `docs/img/cli-help.avif` and embed it in the README.

R10. Put process startup in `MyCLI::Launcher` (`lib/my_cli/launcher.rb`). The executable and the Aruba suite both call it. The shape, and why Aruba runs in-process, is in [How to write CLI tools in Ruby and test them with RSpec and Aruba](https://kig.re/2020/09/07/writing-cli-tools-ruby-migrating-github-issues-to-pivotal-tracker.html). The three extensions are the subject of [How I built three gem extensions](https://kig.re/2026/09/17/2026-09-17--how-i-build-three-gem-extensions-and-got-ai-banned.html).

R11. The version is a constant in `lib/my_cli/version.rb` inside the gem's namespace, `MyCLI::VERSION = "0.1.0"`. The gemspec reads it from there. Zeitwerk's gem loader expects that file to define `VERSION`, spelled exactly so.

R12. Every command that takes options also accepts `-i` / `--interactive`. See [Interactivity](#interactivity).

### The help configuration (R3, R4, R6)

```ruby
Dry::CLI::Help.configure do
  title "MyCLI"
  description "One sentence that says what the tool is for."
  epilogue "Documentation: https://example.com/mycli"
end
```

### The Launcher

`Launcher#initialize` takes `argv`, `stdin`, `stdout`, `stderr`, and `kernel` (defaults: `$stdin`, `$stdout`, `$stderr`, `Kernel`). `#execute!` runs the CLI and exits only through `kernel.exit(code)`. Commands write to the streams passed in, not to the global constants. Build a new Launcher per run: Aruba constructs one per example, and a singleton would keep the first example's argv and streams. The template is `assets/templates/ui/lib/__PATH__/launcher.rb.nest.erb`, and the Aruba configuration is `assets/templates/ui-rspec/spec/support/aruba.rb.erb`.

In-process Aruba supports `run_command_and_stop` only. For a command expected to fail, pass `fail_on_error: false` and check `have_exit_status`.

`exe/<gem-cli-name>` does not load Bundler. It puts `lib/` on `$LOAD_PATH` and calls `MyCLI::Launcher.new(ARGV).execute!`. A `Gemfile` in the directory where the user ran the command must not change which gems load.

Things the Launcher has to cover, because dry-cli and Aruba do not:

- **STDIN.** dry-cli hands a command `out` and `err`, never an input stream. The Launcher stores its `stdin` where the base command's `ui` can read it for the length of one run, falling back to `$stdin`. Without this, prompts in an in-process test read the real terminal.
- **Load order.** Require `dry/cli` and its extensions in `lib/my_cli.rb`, before Zeitwerk is set up. `Launcher` names `Dry::CLI` before Zeitwerk has loaded `cli.rb`, and an eager-loading spec suite will not notice.
- **A closed pipe.** `mycli export | head` must exit 0 quietly. Rescue `Errno::EPIPE` in the Launcher, and in `exe/` call `Signal.trap("PIPE", "SYSTEM_DEFAULT")`.

In specs, run commands with `run_command_and_stop(cmd, fail_on_error: false)`. The in-process launcher raises `NotImplementedError` on `run_command`, and it cannot feed STDIN to a running command. Test `-i` answers in a unit spec against the command, with a `StringIO` whose `tty?` returns true.

## Scaffolding a new gem

Start with `create-gem`, which sits next to this file. It wraps `bundle gem`, then finishes what `bundle gem` leaves undone:

- Fills in the gemspec's `TODO` summary, description and `allowed_push_host`, turns on `rubygems_mfa_required`, and adds the runtime dependencies from R1, R2 and [File layout](#file-layout).
- Adds the development gems from [RuboCop](#rubocop) and the testing paragraph to the `Gemfile`.
- Writes `.rubocop.yml`, deletes the template's deliberately failing example, runs `bundle install` and `rubocop -A`.

The result builds with `gem build` and passes `bundle exec rake` before a line of it has been written by hand.

```text
create-gem recipe box                    # gem recipe_box, module RecipeBox; rspec, GitHub Actions
create-gem -c circleci -t minitest -s "Sync recipes." recipe box
create-gem -i recipe box                 # ask for each value, ENTER keeps the default
```

- Words are joined with underscores. A dash means a namespace to bundler: `recipe-box` is `Recipe::Box`.
- `-t` and `-c` win over `~/.bundle/config`, which `bundle gem` would otherwise obey and ignore the flags.
- Without `-i` it never waits for input and never opens an editor. With `-i` it needs a terminal, offers the other flags as defaults, and opens the gemspec in `$VISUAL` or `$EDITOR` at the end.

## Project files

The generator writes these from `assets/`; for an existing gem, copy them from there.

- `Rakefile`: build, local install, world-readable permissions before packaging (`.env*` files excepted), YARD docs (`rake doc`), and the test task as the default.
- `.gitignore`: the lines in `assets/gitignore` on top of Bundler's.
- `.envrc`: puts `bin` and `exe` on `PATH`, and decrypts `.env.encrypted` and `.env.development.encrypted` with `sopsy` into the environment, never onto disk. Add `PATH_add $(brew --prefix postgresql@18)/bin` when the gem uses PostgreSQL.
- `.rubocop.yml`: relaxed.ruby.style with new cops enabled, plus `rubocop-rake` and `rubocop-rspec`.

Copy the justfile from [inquirex](https://github.com/inquirex/inquirex). Coverage target is above 95%.

### Rakefile

Every gem has a `Rakefile`, and most of Konstantin's are nearly identical:

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yard"

def shell(*args)
  puts "running: #{args.join(" ")}"
  system(args.join(" "))
end

task :clean do
  shell("rm -rf pkg/ tmp/ coverage/ doc/")
end

task gem: [:build] do
  shell("gem install pkg/*")
end

task permissions: [:clean] do
  shell("/usr/bin/find . -path ./.git -prune -o -type d -exec chmod o+rx,g+rx {} + -o -type f -exec chmod o+r,g+r {} +")
end

task build: :permissions

gem_summary = Dir["*.gemspec"].first&.then { |f| Gem::Specification.load(f).summary } || "Documentation"

YARD::Rake::YardocTask.new(:doc) do |t|
  t.files = %w[lib/**/*.rb exe/* - README.md LICENSE.txt]
  t.files << "CHANGELOG.md" if File.exist?("CHANGELOG.md")
  t.options.unshift("--title", gem_summary)
  t.after = -> { system("open doc/index.html") } if RUBY_PLATFORM.match?(/darwin/)
end

RSpec::Core::RakeTask.new(:spec)

task default: :spec
```

### `.gitignore`

A gem's `.gitignore` may hold more than this, but never less:

```gitignore
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

`direnv` runs this file on `cd` into the gem, once `direnv allow .` has trusted it. It puts `bin` and `exe` on `PATH`, and decrypts any `sopsy`-encrypted secrets straight into the environment, so no plain-text `.env` sits on disk. `sopsy` encrypts `.env` to `.env.encrypted` and `.env.development` to `.env.development.encrypted`.

```bash
PATH_add bin
PATH_add exe
# Only when the gem uses PostgreSQL.
PATH_add "$(brew --prefix postgresql@18)/bin"

export RUBYOPT="-W0" # silence deprecation warnings

# Export every variable from whichever encrypted env files exist.
for file in .env.encrypted .env.development.encrypted; do
  [[ -s ${file} ]] || continue
  while IFS= read -r line; do
    [[ ${line} =~ ^[[:space:]]*# ]] && continue
    [[ -z ${line} ]] && continue
    [[ ${line} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    export "${line}"
  done < <(sopsy decrypt "${file}")
done

export LOG_LEVEL=info
```

### RuboCop

Lint with RuboCop, with `rubocop-rake` and `rubocop-rspec`. Inherit relaxed style and enable new cops:

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

## Output

The command's work product goes to STDOUT.

`ui.info`, `ui.success`, `ui.box`, and `ui.table` also go to STDOUT. That is what dry-cli-ui does.

`ui.warn`, `ui.error`, `ui.fatal`, spinners, progress bars, and prompts go to STDERR, so a pipe such as `mycli export > rules.csv` still shows them on the terminal.

Declare shared flags once, on the base command, with `self.inherited`. Each flag has a short and a long form. Declare booleans as `type: :boolean`. dry-cli then accepts `--flag` and `--no-flag`.

- `-h`, `--help` prints help.
- `-v`, `--verbose` turns on `log(*msgs)`, which writes to STDERR as `[timestamp] [info] [command] message`. The `version` command answers to `-V` and `--version`, leaving `-v` to verbose.
- `--color` / `--no-color`. Color is on when stdout is a terminal. Also honor `NO_COLOR`.
- `-E`, `--log-to-stderr` / `--no-log-to-stderr` copies the log file's lines to STDERR, never to STDOUT.

When `-v` or `--verbose` is set and an exception is raised, print the full backtrace, colorized with [pretty_trace](https://github.com/DannyBen/pretty_trace).

### Shell completion

`mycli install completion` appends a source line only when it is not already present:

- bash: `eval "$(mycli completion bash)"` in `~/.bashrc`
- zsh: `eval "$(mycli completion zsh)"` in `~/.zshrc`, after `compinit`

### Colors

With color on, help uses the `styles` block from R3: headings in bold cyan, usage and examples in yellow, flags in green, example comments in bright black. Command results stay readable when piped: keep color out of data a user will pipe.

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

dry-cli has no integer option type. Declare a numeric option as a string default and convert it with `Integer(value)`, which raises on bad input and so reaches the Launcher's error path.

## Interactivity

Prompts go through `ui.prompt` and `ui.confirm` (tty-prompt, inside dry-cli-ui). Questions belong there; `tty-option` is an option parser, not a prompt library.

`-i` / `--interactive` switches a command to asking for its options one at a time:

- Each question shows the value the command would use, in brackets: `CI service [github]:`. ENTER keeps it.
- That value comes from the flag when one was given, else `.mycli-defaults.json`, else the built-in default. dry-cli fills an option's `default:` in before `call` runs, which hides whether the user passed the flag and means the file would never be read. So an option the defaults file may set declares no `default:`; keep its built-in value in a constant, and name it in `desc` so help still shows it.
- A bad answer is rejected with the reason, and the same question is asked again. Validate with the same code the flag parser uses.
- Questions go to STDERR, like every prompt, so the command's STDOUT stays clean.
- With STDIN not a terminal, `-i` fails with a non-zero exit instead of hanging or reading garbage.

When the defaults are obvious, or they can be read from `.mycli-defaults.json`, also accept `-y` / `--yes` and do not prompt. `-i` and `-y` together are a usage error.

## External commands

Run an external program through [tty-command](https://github.com/piotrmurach/tty-command).

## Progress

Use `ui.progress` when the total is known. Split concurrent work across `ui.multi_progress` or `ui.multi_spinner`, which run each job on its own thread. A finished spinner shows the gem's green check, and a failed one the gem's red `𝘅`; keep those glyphs.

## File layout

Add the `zeitwerk` gem. It resolves which file defines a constant and loads that file the first time the constant is used, so the gem keeps no hand-written `require` list. Bundler still decides which gems get installed. The module is `MyCLI`, not `Mycli`. The inflection key is the file basename, not the constant:

```ruby
loader.inflector.inflect(
  "my_cli" => "MyCLI",
  "cli" => "CLI"
)
```

Use the same kind of override for any other all-caps abbreviation. A gem whose name has a dash (`acme-tool`, module `Acme::Tool`) loads with `Zeitwerk::Loader.for_gem_extension(Acme)` instead of `for_gem`.

`cook.rb` is the `Cook` command. `cook/breakfast.rb` is `Cook::Breakfast`. Zeitwerk allows the file and the directory together.

```text
lib/my_cli.rb
lib/my_cli/version.rb
lib/my_cli/launcher.rb
lib/my_cli/cli.rb
lib/my_cli/cli/cook.rb
lib/my_cli/cli/cook/breakfast.rb
lib/my_cli/cli/cook/dinner.rb
```

`exe/<gem-cli-name>` does not load Bundler. It puts `lib/` on `$LOAD_PATH` and calls `MyCLI::Launcher.new(ARGV).execute!`. A `Gemfile` in the directory where the user ran the command must not change which gems load.

Keep a command class small. Put the work in a namespace next to it, grouped by what it does.

## Domain-driven design

A large gem that covers more than one domain (compiled forms and text forms, for example) splits `lib/` into domains. Each domain has one public file, `<domain>_facade.rb`, such as `cooking_facade.rb`. Other code calls that facade and stays out of what is behind it.

```text
lib/my_cli/domains/cooking_facade.rb
lib/my_cli/domains/cooking/...
lib/my_cli/domains/transpiling_facade.rb
lib/my_cli/domains/transpiling/...
```

## Installing skills and completion

Most CLI gems should have an `install` command. A CLI gem that agents will drive has two subcommands:

- `mycli install completion` writes the shell lines from [Shell completion](#shell-completion).
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

Render a report with `ui.table` (tty-table). Keep ANSI color out of the cells: color codes have display width 0 and shift the columns. A colored heading printed before the table is fine.
