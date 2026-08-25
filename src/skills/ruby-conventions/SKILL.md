---
name: ruby-conventions
description: "Konstantin's Ruby conventions: how he lays out and versions a gem, YARD comment style, frozen_string_literal, standardrb rather than rubocop, and running a multi-process application locally through an explicit process definition rather than Foreman. Use when writing or reviewing Ruby, starting a new gem, setting up a Gemfile or justfile, or wiring up local processes for a Ruby project."
---

# Ruby

Ruby is my favorite language and I've been doing it for 17 years. I have dozens of open source gems, with over 240M downloads: see [rubygems profile](https://rubygems.org/profiles/kigster)

## Ruby Gems

I develop many Ruby projects as Ruby Gems. Many of them open source, some of them are private.

When creating a new gem, use the skill called /kigs-gem

#### **Ruby Rakefile for a Gem**

If working on a gem, always use a default Rakefile unless requested otherwise.

Always generate CHANGELOG.md using ruby gem https://github.com/github-changelog-generator/github-changelog-generator and ask if you should bump the gem's version as follows (according to the rules of [SemVar](https://semver.org/)

- Small changes, bug fixes: patch version increment
- Large fixes, some new features, multiple PRs, backwards compatible — minor version
- Big changes, some backwards incompatiblity, major refactors, CLI flag changes, etc. — major version.

The Rakefile for a Ruby Gem must look like so:

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
end

task gem: [:build] do
  shell("gem install pkg/*")
end

task permissions: [:clean] do
  # One traversal replaces a six-level glob chain that printed "No such file
  # or directory" for every level this project does not have, skipped dotfiles
  # entirely, and silently stopped at depth six. .git is pruned — its objects
  # have no business being group-readable.
  shell("find . -path ./.git -prune -o -type d -exec chmod o+rx,g+rx {} + -o -type f -exec chmod o+r,g+r {} +")
end

task build: :permissions

YARD::Rake::YardocTask.new(:doc) do |t|
  t.files = %w[lib/**/*.rb exe/*.rb - README.md LICENSE.txt CHANGELOG.md]
  t.options.unshift("--title", '"FlowEngine — DSL + AST for buildiong complex flows in Ruby."')
  t.after = -> { exec("open doc/index.html") } if RUBY_PLATFORM =~ /darwin/
end

RSpec::Core::RakeTask.new(:spec)

task default: :spec

```

#### Syntax

Use 2-spaces indentation always.

Aggressively take advantage of the most recent language features available in Ruby 4 or introduced recently, such as pattern matching, etc.

Use concurrent-ruby for any concurrency primitives.

For example, DataClasses for immutable structures.

#### Value objects: `Data.define`, not Struct

For any immutable value object, use `Data.define` — not `Struct.new`, not `OpenStruct`, and not a hand-rolled class of attr_readers. `Data` instances are frozen by construction, keyword-initialized, compare by value, and support non-mutating updates via `#with`. Reach for `Struct` only when mutability is genuinely required (rare), and say why in a comment when you do.

```ruby
Result = Data.define(:id, :stored) do
  def stored? = stored
end
Result.new(id: 42, stored: true)
```

#### Accessors, not raw instance variables

Read and write state through `attr_reader` / `attr_accessor`, not through `@ivar` scattered across the class. Assign `@ivar` in **one** place — `initialize` — and everywhere else go through the accessor.

Make the accessor `private` when it is internal; that costs nothing and still gives you one named place to put a default, a memo, or a `nil` guard later. A typo'd `@wrokspace` is silently `nil`; a typo'd `wrokspace` raises `NoMethodError` at the call site, which is the whole point.

```ruby
class VersionBumper
  def initialize(workspace: Workspace.new, out: $stdout)
    @workspace = workspace
    @out       = out
  end

  private

  # @return [Workspace] the ecosystem checkout being rewritten
  attr_reader :workspace

  # @return [IO] where report output goes
  attr_reader :out
end
```

Exceptions, both narrow: memoization (`@cache ||= ...`) and a `Data`/`Struct` member, which already is an accessor.

#### Documentation: YARD, always

Every **new** Ruby module, class, method, and `attr_accessor`/`attr_reader`/`attr_writer` must be documented in [YARD](https://yardoc.org) style. This is the deliberate middle ground: the code stays readable and unpolluted by Sorbet or RBS, yet IDEs (RubyMine, Solargraph/VS Code) read the tags and infer parameter and return types from them.

Rules:

- Start with untagged prose describing what the thing does (1–3 lines). Note: YARD has **no `@description` tag** — the leading untagged prose *is* the description. Never invent a `@description` tag.
- Then tags: `@param name [Type] description` for every parameter, `@return [Type] description` for every meaningful return, `@raise [ErrorClass]` where applicable, `@yield`/`@yieldparam` for blocks.
- Type syntax: `[String, nil]`, `[Boolean]`, `[Array<Symbol>]`, `[Hash{Symbol => Object}]`, `[self]`, `[void]`.
- Use `@example` liberally on any non-trivial public API — a 3–6 line runnable-looking snippet teaches faster than prose.
- Document constants with a one-line comment above them. Never use splatted `attr_reader(*LIST)` — YARD cannot document it; list attributes explicitly.
- When touching an existing file whose comments are plain prose, upgrade them: keep the prose as the description and add the missing `@param`/`@return` tags beneath it.
- `bundle exec yard stats --list-undoc` is the acceptance test; new code should not lower the coverage percentage.

```ruby
# Whether a host is covered by the allowlist. "example.com" matches
# exactly; "*.example.com" matches subdomains but not the apex.
#
# @example
#   definition.allowed_host?("hooks.agentica.group")  # => true
#
# @param host [String] lowercase hostname to test
# @return [Boolean]
def allowed_host?(host)
```

#### Gem Dependencies

When working on a project without Rails (we call it "pure Ruby") you are to utilize extensively the gems from the [dry-rb collection](https://dry-rb.org). In particular alwaays prefer monad-style programming using dry-monads and transactions, with strict dry-types, dry-schema and dry-validations. Use dry-cli for any CLI based tool with commands and subcommands. Always build a super-class subcommand that's abstract, but which provides concret commands with common tooling such as input / output helpers using `TTY::Box.info()` as well as `error()` and `warn`() which are always printed to STDERR, while any actual processing output is printed to STDOUT so that the CLI gem can be used in a piped chain.

For simple TTY interactions you can use gems from the collection [tty-toolkit](https://ttytoolkit.org/). For challenging and complicated TTY user interfaces where positioning, color, are important — you are to skip TTY Toolkit (unless it fits some requirements) and take a full advantage of the gem `ratatui_ruby` baseds on the [Rust Library](https://ratatui.rs/) which provides for extremely rich TTY interfaces.

For any Ruby CLI that performs multiple concurrent tasks please leverate `TTY::Spinner` ruby gem and class, which provides both the primitives for multi-threading and effective display of concurrent operations.

Always add and install rubocop gem, rubocop-rspec, rubocop-rake, and copy `.rubocop.yml` from `${HOME}`. Always install [relaxed rubocop styles](https://relaxed.ruby.style/) as overrides.

When writing `specs`, use the latest RSpec syntax conventions. Do not ever use local variables, but instead use`0let(:var)`. If the variable must be created, but may not be referenced, use let!(:var). Instead of having many 3-line `it` statements:

```ruby
# do not do that please
it 'should be positive' do
 expect(response.code).to eq(200)
end
```

Instead, use the newer style, and especially use as much as possible the amazing gem `rspec-its` which allows you to shorten checks to a single line such as

```ruby
describe 'when this is so' do
  subject { some_object }
	its(:property).should be_nil
  its("child.property").is_expected to eq(1)
end
```

Also, it's ok to use `should`, `should_not` even thought it's out of fashion. If `must` / `must_not` is more fashionable use that instead.

So the new format is:

```ruby
 require 'rspec'
 require 'rspec/its'

 describe 'HTTP response' do
  subject(:response)
  
  # first convention — using it { } without the text description
  it { is_expected.to } be_a_kind_of(ActionDispatch::Response)
  # second convention: test properties of the subject using rspec-its gem
  its(:code).to eql(200)
  its(:body).not_to be_nil
 end
```

As you see it allows testing many more properties in a much more compact way. Please familiarize yourself with [rspec-its](https://github.com/rspec/rspec-its).

#### Coverage

Always use `simplecov` gem together with `coverage-badge` gems. Add the following to the `spec_helper.rb` at the very top to enable both:

```ruby

require "simplecov"
require "coverage/badge"

SimpleCov.start do
  minimum_coverage 95
  add_filter "/spec/"
  self.formatters = SimpleCov::Formatter::MultiFormatter.new(
    [
      SimpleCov::Formatter::HTMLFormatter,
      Coverage::Badge::Formatter
    ]
  )
end

SimpleCov.at_exit do
  SimpleCov.result.format!
  # rubocop: disable RSpec/Output
  puts "Coverage: #{SimpleCov.result.covered_percent.round(2)}%"
  # rubocop: enable RSpec/Output
  FileUtils.mv("coverage/badge.svg", "docs/badges/coverage_badge.svg")
end
```

Then include the SVG file at the top of the `README.md`.

## Running a Multi-Process Application Locally

Use [mprocs](https://github.com/pvolok/dekit), installed with Homebrew, to run an application that is more than one process. Do not use Foreman.

```ruby
brew 'mprocs'
```

mprocs is configured by an `mprocs.yaml` at the root of the repository and gives each process its own scrollable pane, rather than interleaving every process into one stream. That is what keeps a backend stack trace readable while a frontend build is also talking.

The common case is a bare command string per process:

```yaml
procs:
  puma: bundle exec puma -C config/puma.rb
  sidekiq: bundle exec sidekiq -C config/sidekiq.yml
  css: bun run watch:css
  js: bun run build:js:schema-viewer && sleep 10000000
  browser: sleep 3 && open http://localhost:3000 && sleep 10000000
  logs: tail -f log/development.log
```

Two idioms worth copying from that example. A one-shot command gets `&& sleep 10000000` so its pane stays alive and its output stays readable instead of the process vanishing the moment it succeeds. And a `browser` proc that sleeps briefly and then opens the URL saves reaching for the mouse on every boot.

### The object form, for anything a bare string cannot express

```yaml
procs:
  api:
    shell: bundle exec hanami server
    cwd: hanami
  frontend:
    shell: pnpm run dev
    cwd: frontend
    stop: SIGTERM
```

- `shell` (a string) or `cmd` (an array), exactly one of the two
- `cwd` sets the working directory, which is what a monorepo with more than one deployable tree needs. The prefix `<CONFIG_DIR>` expands to the directory holding the config, so paths do not depend on where mprocs was invoked from
- `env`, `add_path`, `autostart` (default true), `autorestart` (default false)
- `stop` is how the process is stopped by `x` and on quit: `SIGINT`, `SIGTERM`, `SIGKILL`, `hard-kill`, `{send-keys: [...]}` or `{cmd: "docker compose down"}`

Because mprocs owns starting and stopping, it is also the answer to the "Ctrl-C left a server holding the port" problem. Do not hand-roll process-group signalling in a task runner when mprocs already does it.

Default keys: `q` quits and soft-kills everything, `Q` force quits, `C-a` moves focus between the process list and the output pane, `j`/`k` or the arrows select a process, `x` stops the selected one and `s` starts it again.

### Do not use Foreman, and beware the scaffolds that install it

Rails and Hanami both scaffold a `Procfile.dev` plus a `bin/dev` that runs Foreman. Hanami's generated `bin/dev` is worth reading before anything invokes it:

```sh
if ! gem list foreman -i --silent; then
  echo "Installing foreman..."
  gem install foreman
fi
```

That installs a gem into the developer's global gem set as a side effect of booting a server. It mutates state outside the project and makes the command behave differently on the second machine. Replace `bin/dev` and `Procfile.dev` with `mprocs.yaml` and have `just dev` call mprocs.

If a generated `Procfile.dev` has to stay for a deployment target that requires it, it must not be the thing a developer runs. mprocs can read one directly with `mprocs --procfile Procfile.dev` when that is genuinely the single source of truth.
