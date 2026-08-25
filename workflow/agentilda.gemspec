# frozen_string_literal: true

require_relative "lib/agentilda/version"

Gem::Specification.new do |spec|
  spec.name = "agentilda"
  spec.version = Agentilda::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "Agentic specification-driven development: spec, plan, build, review"
  spec.description = <<~TEXT
    Keeps a project's specifications, plans and pull requests joined up, and
    drives specialist agents over them in parallel. A feature's state is its
    folder name under .plans, so a transition renames a directory rather than
    updating a row, and nothing can claim a phase whose document is missing.
  TEXT
  spec.homepage = "https://github.com/kigster/agentilda"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }

  # Globbed rather than taken from `git ls-files`, so building the gem does not
  # require a git checkout — the same reason the executables resolve their own
  # bundle rather than trusting the caller's working directory.
  spec.files = Dir.chdir(__dir__) do
    Dir.glob(["lib/**/*.rb", "agents/*.md", "exe/*", "bin/*"]).select { |f| File.file?(f) }
  end

  spec.bindir = "exe"
  # `tilda` is a symlink to `agentilda` in the checkout; named here so that
  # installing the gem writes both, rather than only the one git recorded.
  spec.executables = %w[agentilda tilda]
  spec.require_paths = ["lib"]

  spec.add_dependency "aasm"
  spec.add_dependency "concurrent-ruby"
  spec.add_dependency "dry-cli"
  spec.add_dependency "dry-cli-autocomplete"
  spec.add_dependency "dry-inflector"
  spec.add_dependency "dry-monads"
  spec.add_dependency "fuzzy-string-match"
  spec.add_dependency "parallel"
  spec.add_dependency "pastel"
  spec.add_dependency "strings"
  spec.add_dependency "tty-box"
  spec.add_dependency "tty-command"
  spec.add_dependency "tty-progressbar"
  spec.add_dependency "tty-screen"
  spec.add_dependency "tty-spinner"
  spec.add_dependency "unicode-display_width"
end
