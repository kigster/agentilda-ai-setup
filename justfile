# Tell 'just' to run bash so recipes can use bashisms and `set -euo pipefail`.
set shell := ["bash", "-c"]

version := `grep 'VERSION *=' lib/spec_plan_build.rb | head -1 | awk -F'"' '{print $2}' | tr -d '\n'`

# The `-` matters: `rbenv init bash` prints human instructions ("skipping
# ~/.bash_login: already configured"), which eval then tries to run, and the
# recipe dies with "skipping: command not found". `rbenv init - bash` prints
# the shell code that is meant to be eval'd.
rbenv := 'eval "$(rbenv init - bash 2>/dev/null || true)"; bundle exec '

# This repo is linted with `standard`, not rubocop: the Gemfile says so, and
# standard is rubocop with the arguing removed.
spb := 'bundle exec scripts/spec-plan-build'

[no-exit-message]
recipes:
    just --choose

# Install gems and wire ~/.agents into ~/.claude
install: bundle setup

# Install gem dependencies only
bundle:
    {{ rbenv }} --version >/dev/null 2>&1 || gem install bundler
    bundle install

# Symlink AGENTS.md and the shared folders into ~/.claude
setup:
    bin/setup

# Show what `just setup` would link, without touching anything
doctor:
    bin/setup --dry-run

# Repoint symlinks that aim somewhere else (never touches real files)
relink:
    bin/setup --force

build: install

# Lint
lint:
    {{ rbenv }} standardrb

# Lint and reformat, then reformat markdown — pass --fix or paths as arguments
format *args:
    {{ rbenv }} standardrb --fix {{ args }}
    /usr/bin/find . -name '*.md' -not -path './coverage/*' -not -path './.git/*' \
        -exec mdformat --wrap no {} \; -print

# Run the specs
test *args:
    {{ rbenv }} rspec {{ args }}

# Run the specs with a coverage report
test-coverage *args:
    export COVERAGE=true; {{ rbenv }} rspec {{ args }}
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
    {{ rbenv }} lefthook run pre-commit --all-files

# Print the current version
version:
    @echo "{{ version }}"

# ---------------------------------------------------------------- spec-plan-build

# Create the next numbered plan folder: `just spec-create tax rule dsl`
spec-create *words:
    {{ spb }} create {{ words }}

# Create a retroactive plan in the gap after NNN: `just spec-retro 002 schedule k1`
spec-retro after *words:
    {{ spb }} create --after {{ after }} {{ words }}

# The status table: every plan, its state, and its pull requests
spec-status *args:
    {{ spb }} status {{ args }}

# Write .plans/INDEX.md — every plan, its goal, PRs and documents
spec-index *args:
    {{ spb }} index {{ args }}

# Show which folder emojis disagree with their contents
resync-dirs-check:
    {{ spb }} resync dirs

# Rename folders so their emoji matches their contents
resync-dirs:
    {{ spb }} resync dirs --commit

# Show which pull request titles are missing an [NNN.MM] prefix
resync-prs-check:
    {{ spb }} resync prs

# Add the missing [NNN.MM] prefixes to pull request titles
resync-prs:
    {{ spb }} resync prs --commit

# Regenerate context/feature-building/spec-plan-build.md from the state machine
docs: bundle
    {{ spb }} docs --output context/feature-building/spec-plan-build.md
    mdformat --wrap no context/feature-building/spec-plan-build.md
