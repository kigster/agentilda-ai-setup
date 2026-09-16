# Tell 'just' to run bash so recipes can use bashisms and `set -euo pipefail`.
set shell := ["bash", "-c"]

# The `-` matters: `rbenv init bash` prints human instructions ("skipping
# ~/.bash_login: already configured"), which eval then tries to run, and the
# recipe dies with "skipping: command not found". `rbenv init - bash` prints
# the shell code that is meant to be eval'd.
rbenv := 'eval "$(rbenv init - bash 2>/dev/null || true)"; '

# The agentilda gem used to live in workflow/ and now comes from rubygems, so
# what is left here, scripts/ and spec/, is linted and tested from the root
# against the one Gemfile. CircleCI runs the same two commands.
#
# This repo is linted with `standard`, not rubocop: the Gemfile says so, and
# standard is rubocop with the arguing removed.
bundle := rbenv + 'BUNDLE_GEMFILE=Gemfile bundle exec '

# The installed gem, not a checkout. bin/setup puts it there with
# `gem install agentilda`, and `just install-gems` does the same by hand.
tilda := rbenv + 'agentilda'

[no-exit-message]
recipes:
    just --choose

# Setup local repository for your specific needs before running install
init:
    #!/usr/bin/env bash
    [[ -f configuration.yml ]] || cp configuration.example.yml configuration.yml
    echo -e "\n\e[1;34mINFO: This folder contains a git-ignored file configuration.yml."
    echo -e "You should carefully review this file and understand it's capabilities"
    echo -e "before simply running the installer (eg \e[0;32mbin/install --help\e[0m)"
    echo
    echo -e "\e[0;33mPress any key to enter the editor and edit your configuration....\e[0m"
    read -n 1 -s -r -p ""

    ${EDITOR:-vim} configuration.yml
      

# Copy this checkout into ~/.agents, then link ~/.agents into ~/.claude
install *args:
    bin/install {{ args }}

# Install gems this repo depends on
install-gems:
    {{ rbenv }} gem install agentilda agent-lock -N

# Install gem dependencies only
bundle:
    {{ rbenv }} bundle --version >/dev/null 2>&1 || gem install bundler
    {{ rbenv }} bundle install

# The linking step on its own. `just install` runs it for you
setup:
    bin/setup

# Show what `just install` would copy and link, without touching anything
doctor:
    bin/install --dry-run

# Repoint symlinks that aim somewhere else (never touches real files)
relink:
    bin/setup --force

build: install

# Lint
lint:
    {{ bundle }} standardrb

# Lint and reformat, then reformat markdown — pass --fix or paths as arguments
format *args:
    {{ bundle }} standardrb --fix {{ args }}
    /usr/bin/find . -name '*.md' -not -path './coverage/*' -not -path './.git/*' \
        -exec mdformat --wrap no {} \; -print

# Run the specs
test *args:
    {{ bundle }} rspec {{ args }}

# Run the specs with a coverage report
test-coverage *args:
    export COVERAGE=true; {{ bundle }} rspec {{ args }}
    @echo "open coverage/index.html"

ci: lint test-coverage

alias check-all := ci

# Remove generated artifacts
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    find . -name .DS_Store -delete -print || true
    rm -rf coverage tmp/* .rspec_status

# Run all lefthook pre-commit hooks
lefthook:
    {{ bundle }} lefthook run pre-commit --all-files

# agentilda --version
version:
    @{{ tilda }} --version

# ---------------------------------------------------------------- agentilda

# Create the next numbered plan folder: `just spec-create tax rule dsl`
spec-create *words:
    {{ tilda }} create {{ words }}

# Create a retroactive plan in the gap after NNN: `just spec-retro 002 schedule k1`
spec-retro after *words:
    {{ tilda }} create --after {{ after }} {{ words }}

# The status table: every plan, its state, and its pull requests
spec-status *args:
    {{ tilda }} list-plans {{ args }}

# Write .plans/INDEX.md — every plan, its goal, PRs and documents
spec-index *args:
    {{ tilda }} index {{ args }}

# Show which folder emojis disagree with their contents
resync-dirs-check:
    {{ tilda }} resync dirs

# Rename folders so their emoji matches their contents
resync-dirs:
    {{ tilda }} resync dirs --commit

# Show which pull request titles are missing an [NNN.MM] prefix
resync-prs-check:
    {{ tilda }} resync prs

# Add the missing [NNN.MM] prefixes to pull request titles
resync-prs:
    {{ tilda }} resync prs --commit

# Show what would be created in Linear: `just linear-check TAX`
linear-check prefix *args:
    {{ tilda }} linear import --prefix {{ prefix }} {{ args }}

# Create the Linear projects and issues: `just linear-import TAX`
linear-import prefix *args:
    {{ tilda }} linear import --prefix {{ prefix }} --commit {{ args }}

# Emit the same import as JSON, for the Linear MCP transport
linear-json prefix *args:
    {{ tilda }} linear import --prefix {{ prefix }} --format json {{ args }}

# Regenerate context/feature-building/agentilda.md from the state machine
docs:
    mkdir -p context/feature-building
    {{ tilda }} docs --output context/feature-building/agentilda.md
    mdformat --wrap no context/feature-building/agentilda.md
