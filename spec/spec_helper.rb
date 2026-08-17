# frozen_string_literal: true

require "fileutils"
require "simplecov"
require "coverage/badge"

# The badge is moved here at exit; without the directory the whole suite dies
# in `at_exit`, which reports as a passing run followed by a stack trace.
FileUtils.mkdir_p("docs/badges")

SimpleCov.start do
  # `track_files` is what makes the number mean anything: without it SimpleCov
  # only counts files some example happened to load, so a library nobody
  # requires reports 100% of nothing. With it, an untested file counts as 0%.
  track_files "lib/**/*.rb"

  add_filter %r{\A/spec/}
  add_filter %r{\A/bin/}

  enable_coverage :branch

  self.formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    Coverage::Badge::Formatter
  ]
end

SimpleCov.at_exit do
  SimpleCov.result.format!
  # rubocop: disable RSpec/Output
  puts "Coverage: #{SimpleCov.result.covered_percent.round(2)}%"
  # rubocop: enable RSpec/Output
  FileUtils.mv("coverage/badge.svg", "docs/badges/coverage_badge.svg")
end

require "rspec/its"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "spec_plan_build"

require_relative "support/plans_fixture"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed

  config.include PlansFixture

  # Every example tagged `:tree` gets its own throwaway `.plans` directory, so
  # the suite never reads or writes a real project.
  config.around(:each, :tree) do |example|
    Dir.mktmpdir("spec-plan-build") do |tmp|
      @plans_root = File.join(tmp, SpecPlanBuild::PLANS_DIR)
      FileUtils.mkdir_p(@plans_root)
      example.run
    end
  end
end
