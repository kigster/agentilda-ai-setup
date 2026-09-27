# SimpleCov must start before the gem's own code loads, or that code counts as
# never run. The badge lands in coverage/badge.svg for the README.
require "simplecov"
require "coverage/badge"
require "fileutils"

SimpleCov.start do
  skip %r{\A/(spec|test)/}
  enable_coverage :branch
  minimum_coverage 95
  formatter SimpleCov::Formatter::MultiFormatter.new(
    [SimpleCov::Formatter::HTMLFormatter, Coverage::Badge::Formatter]
  )
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

SimpleCov.at_exit do
  SimpleCov.result.format!
  # rubocop: disable-next RSpec/Output
  puts "Coverage: #{SimpleCov.result.covered_percent.round(2)}%"
  FileUtils.mkdir_p("docs/badges")
  FileUtils.mv("coverage/badge.svg", "docs/badges/coverage_badge.svg")
end
