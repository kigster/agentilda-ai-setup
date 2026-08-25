# `true` = install missing gems automatically
source "https://rubygems.org"

gem "aasm" # State Machine
gem "concurrent-ruby"    # Concurrency Primitives
gem "fuzzy-string-match" # Jaro-Winkler, for matching a pull request title to a plan folder
gem "parallel"           # Fan work out over threads or processes
gem "pastel"             # ANSI Coloring
gem "strings"            # Wrap text the way TTY::Box wraps it, so a box can be sized to its wrapped height
gem "unicode-display_width" # How many terminal cells a string occupies

gem "tty-spinner"     # Use for parallel execution, and reporting the status
gem "tty-progressbar" # Same as above, except when we can tell how far along we are
gem "tty-box"         # We'll only use TTY::Box.error(), info(), warn(), success().
# by creating a module that injects instance methods error(),
# info(), warn() and success() into any class that includes it
gem "tty-screen"      # screen detection utilities
gem "tty-command"     # if we need to execute any external command

# Dry-Rb Gems
gem "dry-cli-autocomplete" # add completion
gem "dry-cli"         # Commands and subcommands, in cli.rb
gem "dry-inflector"   # String inflection, in ordinal.rb
gem "dry-monads"      # Success/Failure, in creator.rb

group :development do
  gem "colored2"
  gem "irb"
  gem "standard"
end

group :test do
  gem "coverage-badge"
  gem "rspec"
  gem "rspec-its"
  gem "rspec_junit_formatter" # JUnit XML for CircleCI store_test_results
  gem "simplecov"
end
