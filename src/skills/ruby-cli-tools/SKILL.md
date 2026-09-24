---
  name: ruby-cli-tool
description: >
  Describes how we build CLI tools and commands in ruby, what conventions we apply and what dependencies we use. Describers how
  to test these gems, how to structure the classes and modules and what goes to STDOUT and what to STDERR.
languages:
  - Ruby
category: creating CLI tools in ruby
license: MIT
metadata:
  author: Konstantin Gredeskoul
  version: '1.0.0'
---

# Ruby CLI Tooling

This skill teaches the agent the preferred method by which CLI tools in Ruby are built.

## Rules That Always Apply

R1. We always build our CLI engine on top of the `dry-cli` Ruby Gem.

R2. We always add our own extensions described very well on https://dry-cli.tools/ website.

R3. We always use the `dry-cli-help` to provide global description and usage and possibly epilogue for the help screen.

R4. We never exit with non-zero code when someone runs the executable with no arguments. This invokes `-h` and prints help, then exits with status 0. To accomplish that you may need to override it in the `dry-cli-help` gem.

R5: We always add `dry-cli-autocomplete` and the `completion` command for BASH and ZSH with description.

R6: The default width of the output (help gem wraps the long descriptions) is the terminal width minus 6 characters, unless the width > 120, in which case it's  120. It should be set in the dry-cli-help configuration block.

R7: We use the ui helpers to print user messages (error, info, warning), to print progress bars, task lists and spinners, and report on what the gem is doing at a given moment. Please familiarize yourself with the functionality it provides and use it. https://github.com/kigster/dry-cli-ui

R8: If the gem can paralellize the work requested, we use `ui.multi_progress` or `ui.multi_spinner`s to show the overall status and individual task status. Also: https://github.com/kigster/dry-cli-ui

R9: If possible to take a screenshot of the top --help screen and include it into the README.md as an avif image in docs/img/cli-help.avif file, but that's a nice to have.

R10: We structure the gem around a key class dalled `Launcher.rb` as described in two blog posts:

1. https://kig.re/2026/09/17/2026-09-17--how-i-build-three-gem-extensions-and-got-ai-banned.html
2. https://kig.re/2020/09/07/writing-cli-tools-ruby-migrating-github-issues-to-pivotal-tracker.html

The second one describing how to use Launcher.rb class to engage Aruba gem for proper CLI testing without the expensive fork.

## Styles

We use rubocop, rubocop-rake, and rubocop-rspec to format the files. But we also download the and add it to `.rubocop.yml`:

```yaml
inherit_from:
- https://relaxed.ruby.style/rubocop.yml
```

We always automatically enable new rules in rubocop.

We always add a justfile (similar to what the gem inquirex — https://github.com/inquirex/inquirex/) provides, and the same [`Rakefile`](https://github.com/inquirex/inquirex/blob/main/Rakefile) that knows how to release the gem to ruby-gems and how to generate YARD documentation.

We always bring in:

1. rspec-core

2. rspec-its

3. simplecov

4. coverage-badge

5. aruba

   Gems for testing and aim for > 95% of test coverage. This is a typical `spec_helper.rb` that records the coverage as a badge that later gets committed:
   https://github.com/inquirex/inquirex/blob/main/spec/spec_helper.rb

## Secrets and Pre-Commit Hooks

If the CLI gem requires developer secrets, we utilize `.env` (git-ignored) and use `sopsy` tool for encryption and decryption. For more information see https://kig.re/2026/06/28/sopsy-secrets-in-git-secure-enclave.html and https://sopsy-cli.dev/ as well as https://github.com/kigster/sopsy

We always install https://github.com/inquirex/inquirex/blob/main/.secrets.baseline file 

We always install https://github.com/inquirex/inquirex/blob/main/lefthook.yml lefthook gem configuration and install it via `lefthook install`

Always include **zeitgest** ruby gem and provide inflections where abbreviations are all caps, eg "CLI"

**Always include a .github actions: one that runs rspec and the other rubocop.**

If the gem can benefit from a global configuraiton, use [`dry-configurable`](https://github.com/dry-rb/dry-configurable)

If the gem can benefit from strong types, schemas and validations, include `dry-schema, `dry-types, `dry-struct`, `dry-validation`. 

> [!IMPORTANT]
>
> We tend to lean on many of the dry-rb gems because of their decoupled nature, high quality of codebase, good design patterns, and ease of extensibility.
>
> Please read: https://hanakai.org/learn/dry/getting-started for the link to dry-* gem sources.

For the return values from the functions we prefer to use `dry-monad`s. Please do so.

In the gem's root folder place `.envrc` file that at least has `PATH_add exe` which adds the path where the executable lives.

In the file `exe/<gem-cli-name>` ensure there is no reference to Bundler whatsoever and the CLI executable can perform of it's commands from any place on the file system, and does not get confused by a local Gemfile.

## Output

The gem's commands, when they perform their work, should output to STDOUT. 

Any errors, info/warning boxes must be printed to STDERR so that they can be seen during  a pip operation.

Have several global flags such as:

```
-h | --help       Print help
-v | --verbose   	Uses a single shared global function log(*msgs) to add various informational messages to STDERR output in a structured way. Forexample mssage format messages should include:

"[ time stamp ] [ info ] [ command ] message "

--[no]-color      Default is color, but this allows the user to turn that off.
```


### Auto Completion

Always add the `completion` command as described on the README of the gem: 

* https://dry-cli.tools/#autocomplete

* https://github.com/kigster/dry-cli-autocomplete


  ### Use of Colors

  Unless `--no-color` has been passed, we want the gem's output to be vibrant and engaging. We override the headers for the gem help (USAGE, EXAMPLES, OPTIONS, etc). 

  All examples and generic usage of the CLI must be in gold yellow.

  All headings should be in bold CYAN.

  All flags shoud be in green, and all comments should be in bright_black

### Conventions around Arguments Flags and Options

If the gem's command is mean to opearate on a file or a directory or a series of files, make them arguments, eg:

```
mycli reformat ./src/ruby --type ruby --write
mycli reformat Gemfile exe/mycli lib/mycli/version.rb
etc. 
```

Always support Ruby Dir GLOB patterns but tell the user to quote it and specify it via the flag:

```
mycli reformat '**/*.rb' --enable-glob
```

Always have a short and long version of each flag.

## Interactivity

If the gem may need to be interactive, use `tty-prompt` ruby gem for prompts, but also provide `-y | --yes` if either the defaults are clear, OR they can be provided by a file `.mycli-defaults.json`. 

For for asking the user what to do, or how to proceed it's best to leverage a multiple choice question, rendered by a gem such as https://github.com/piotrmurach/tty-option



## Executing Shell Commands

If the gem must execute an external command, do so via the https://github.com/piotrmurach/tty-command gem which wraps the execution in a nice interface.

### Use of Progress Bars and Spinners

These are highly useful in showing what the gem is doing. 

Use progress bar when it's possible to determine the totality of the work to perform. Especially if the work can be done concurrently, split it up into sub-spinneres, and create a Multi Spinner that houses the individual ones.

The same applies to the tasks and spinners. Use green check marks to indicate successful spinner action.
Use bold red colored 🆇 to indicate failure.

## Ruby File Layout

Let's assume our tool is called `mycli` and it comes with a bunch of commands and sub-comands.

My must decider if our module will be Mycli or MyCLI. I prefer the second version, so I need to tell Zeitwerk that there is an inflection on "Mycli" => "MyCLI". 

For example, a commnd "cook" may have arguments "breakfast" or "coffee" or "dinner",. etcs

The `lib` directory is always structured as 

```lib/my_cli/cli.rb
lib/
    my_cli/
           version.rb
           launcher.rb
           cli.rb
           cli/
               cook.rb/
               cook/breakfast.rb
							 cook/dinner.rb
```

But often times we want to keep the actual comands relatively lean. Therefore break up the gem's namespace into sub-namespaces that help group related files together.

## Domain Driven Design

For a large CLI gem that may have multiple domains addressed in a single gem (eg text forms and compiled forms), you are encouraged to consider the DDD: domain driven design. 

Domain-driven design breaks the files under lib into packages with a single consistent file at the top of the hierarchy called Facade.rb. This file contains the ONLY public methods allowed into this domain. So now the gem might look like this:

```
 lib/
    my_cli/
           version.rb
           launcher.rb
           cli.rb
           cli/
               cook.rb/
               cook/breakfast.rb
							 cook/dinner.rb
					 domains/
               cooking_facade.rb
               cooking/
                   files implementing cooking
               transpiling_facade.rb
               transpiling/
                   files implementig transpiling
```

## Agentic Integration

Many CLI gems these days install skills, plugins or comands.

Most gems should have the command `install` which installs several diffeent things:

* `mycli install completion` writes the `eval "$(mycli completion bash)"` to your ~/.zshrc file if ont already there.
* `mycli install skills` (this should always install into `~/.agents/skills/<skill-name>` and symlink form `~/.claude/skills`)

The skills installed by the CLI gems can be of many kinds, but one of the most common ones is `/mycli-skill [ aguments ]`  There maybe other unrelated skills, such as `/mycli-help` or `/mycli explain`s 

## Readme

After the gem is completed, make sure the README is structured as follows:

1. What pain does not tool solves today for whom. More and more tool are aimed at agents.
2. What are the top level commans of the gem (this is where a screenshot of `mccly -h` could be very useful)

## Dry Run

CLI gems typiically have a mix of commsnd that perform wite operations, and some might not be  automtically reversible. For this reason always provide `--n  | --dry-run`  to commands that change state, that  modify resources, or anhything like that. 

Read only commands do not need the `--dry-run`. 

## Observability

For observability it is recommended that the gem automatically writes a lot file based on the gem https://logger.reidmorrison.com/ (source is here: https://github.com/reidmorrison/semantic_logger )

The default logging location for CLI tools should be `/var/log/<name-of-the-tool>.log`. 

Default log level should be INFO.

Now a global flag to the CLI tool should be able to copy the log output onto the STDOUT.  That flag shoul be called `--[no]-log-to-stderr`, but a short version `-E` should copy log lines to the STDERR.

When `-v | --verbose` is provided, and an exception occurs, it's very 	

## Reporting

Often times the goal of at least some command inthe CLI is to provide a report of some sort. This is where the Ruby gem `tty-table` is very useful. Do not insert color into the table unless you pan to compensate for it's two-byte nature, but feel free to print a colorful header before the report.

Let's try using this gem to colorize our exceptions:

https://github.com/DannyBen/pretty_trace
