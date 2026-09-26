# SimpleCov must start before the gem's own code loads, or that code counts as
# never run. The badge lands in coverage/badge.svg for the README.
require "simplecov"
require "coverage/badge"

SimpleCov.start do
  add_filter %r{\A/(spec|test)/}
  enable_coverage :branch
  minimum_coverage 95
  formatter SimpleCov::Formatter::MultiFormatter.new(
    [SimpleCov::Formatter::HTMLFormatter, Coverage::Badge::Formatter]
  )
end
