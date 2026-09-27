# SimpleCov must start before the gem's own code loads, or that code counts as
# never run. The badge lands in docs/badges/coverage_badge.svg for the README.
require "simplecov"
require "coverage/badge"
require "fileutils"

SimpleCov.start do
  # SimpleCov 1.x gives project-relative paths without a leading slash; 0.22 kept it.
  skip %r{\A/?(spec|test)/}
  enable_coverage :branch
  minimum_coverage 95
  formatter SimpleCov::Formatter::MultiFormatter.new(
    [SimpleCov::Formatter::HTMLFormatter, Coverage::Badge::Formatter]
  )
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

SimpleCov.at_exit do
  SimpleCov.result.format!
  puts "Coverage: #{SimpleCov.result.covered_percent.round(2)}%" # rubocop:disable RSpec/Output
  FileUtils.mkdir_p("docs/badges")
  FileUtils.mv("coverage/badge.svg", "docs/badges/coverage_badge.svg")
end
