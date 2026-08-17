# frozen_string_literal: true

require "dry/cli"
require "dry/initializer"
require "dry/monads"
require "dry/inflector"
require "finite_machine"
require "pastel"
require "tty/box"
require "tty/command"
require "tty/screen"
require "tty/spinner"
require "fileutils"

# Spec → Plan → Build.
#
# Three phases, each with a file that proves it happened, and a guarded state
# machine that refuses to let a plan folder claim a phase it has not reached.
#
#   spec   ⚪️ New          spec.md
#   plan   ⭐️ Ready        plan.md
#   build  🟡 → ✅         pull-requests.md
#
# The conventions are not documented anywhere else by hand: the status
# vocabulary, the numbering rules and the transition table live here and are
# emitted by `spec-plan-build docs`. Three hand-maintained copies of that table
# have already drifted apart, which is why there is now exactly one.
#
# © 2026 Konstantin Gredeskoul
module SpecPlanBuild
  VERSION = "1.0.0"

  # The folder every project keeps its plans in.
  PLANS_DIR = ".plans"

  # Prefix for a pull request that deliberately implements no plan —
  # dependency bumps, CI work, hotfixes, developer tooling.
  NO_PLAN_PREFIX = "DEV.00"

  # @return [Dry::Inflector] shared inflector
  def self.inflector = @inflector ||= Dry::Inflector.new

  class Error < StandardError; end
end

# Each component is required only once it exists, so the suite loads — and
# stays a useful red/green signal — while the rest is being built. Drop the
# `File.exist?` guard once every file below is in place.
%w[
  ui
  ordinal
  lifecycle
  markdown
  pull_request
  description
  feature
  github
  tree
  creator
  resolver
  resync
  reporter
  cli
].each do |component|
  path = File.join(__dir__, "spec_plan_build", "#{component}.rb")
  require path if File.exist?(path)
end
