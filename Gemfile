# `true` = install missing gems automatically
source "https://rubygems.org"

gem "aasm" # State Machine
gem "concurrent-ruby"    # Concurrency Primitives
gem "fuzzy-string-match" # Jaro-Winkler, for matching a pull request title to a plan folder
gem "parallel"           # Fan work out over threads or processes
gem "pastel"             # ANSI Coloring
gem "strings"            # Wrap text the way TTY::Box wraps it, so a box can be sized to its wrapped height
gem "unicode-display_width" # How many terminal cells a string occupies
gem "tty-box"            # We'll only use TTY::Box.error(), info(), warn(), success().
gem "tty-progressbar"    # Same as above, except when we can tell how far along we are
gem "tty-spinner"        # Use for parallel execution, and reporting the status
gem "tty-command"        # if we need to execute any external command
gem "tty-screen"         # screen detection utilities
gem "dry-cli"            # That's what we use for creating CLI entry points with commands & subcommands
gem "dry-inflector"      # String inflection utilities
gem "dry-initializer"    # Keyword-argument initializers for plain classes
gem "dry-monads"         # Monads for functional programming

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

unless File.exist?(".standard.yml")
  File.open(".standard.yml", "w") do |f|
    f.puts <<~EOF
      fix: true               # default: false
      parallel: true          # default: false
      format: progress        # default: Standard::Formatter
      ruby_version: 4.0       # default: RUBY_VERSION
      default_ignores: false  # default: true

      ignore:                 # default: []
        - 'vendor/**/*'

      plugins:                # default: []
        - standard-rails

      extend_config:          # default: []
        - .standard_ext.yml"
    EOF
  end
end
