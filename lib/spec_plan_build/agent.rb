# frozen_string_literal: true

require "yaml"

module SpecPlanBuild
  # One specialist, loaded from `~/.agents/agents/<name>.md`.
  #
  # The definition files are the single source of truth for who does what: the
  # frontmatter says which plan states this agent handles and what it may write,
  # and the body is the prompt. Nothing about a specialty is duplicated in Ruby.
  #
  # @!attribute [r] name
  #   @return [String]
  # @!attribute [r] description
  #   @return [String]
  # @!attribute [r] handles
  #   @return [Array<Symbol>] plan states this agent is offered work from
  # @!attribute [r] advances_to
  #   @return [Symbol, nil] the state it is expected to reach; nil = read-only
  # @!attribute [r] model
  #   @return [String, nil]
  # @!attribute [r] allowed_tools
  #   @return [Array<String>]
  # @!attribute [r] may
  #   @return [Array<String>] commands lifted from {Executor::FORBIDDEN_COMMANDS}
  #     for this agent alone. Nothing in {Executor::UNGRANTABLE} can be lifted.
  # @!attribute [r] timeout
  #   @return [Integer, nil] seconds this agent gets before it is abandoned;
  #     nil takes {Executor}'s default. Specialists differ by more than an
  #     order of magnitude. A reviewer reads one diff, while `leah-researcher`
  #     fans out subagents and says in its own prompt that research "may take
  #     an hour or more". One number for both kills the slow one every time,
  #     and reports it as a failing plan rather than as a cap set too low.
  Agent = Data.define(:name, :description, :handles, :advances_to, :model,
    :allowed_tools, :may, :network, :timeout, :prompt, :path) do
    # @return [Boolean] whether this agent changes anything on disk
    def read_only? = advances_to.nil?

    # @param status [SpecPlanBuild::Status]
    # @return [Boolean]
    def handles?(status) = handles.include?(status.key)
  end

  # Loads and indexes the agent definitions.
  class Agents
    # Where definitions live, unless told otherwise.
    DEFAULT_DIR = File.expand_path("../../agents", __dir__)

    # Frontmatter, then body.
    FRONTMATTER = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

    # @param dir [String]
    def initialize(dir: DEFAULT_DIR)
      @dir = File.expand_path(dir)
    end

    # @return [String]
    attr_reader :dir

    # @return [Array<SpecPlanBuild::Agent>] in name order
    def all
      @all ||= Dir.glob(File.join(dir, "*.md")).sort.filter_map { |path| parse(path) }
    end

    # @param name [String]
    # @return [SpecPlanBuild::Agent, nil]
    def find(name) = all.find { |a| a.name == name.to_s }

    # Every agent that will act on a plan in this state, in definition order.
    # A read-only agent is never offered work by the loop — it has nothing to
    # advance, so including it would make every round look productive.
    #
    # @param status [SpecPlanBuild::Status]
    # @return [Array<SpecPlanBuild::Agent>]
    def for_status(status) = all.select { |a| a.handles?(status) && !a.read_only? }

    private

    # @param path [String]
    # @return [SpecPlanBuild::Agent, nil]
    def parse(path)
      match = FRONTMATTER.match(File.read(path, encoding: "UTF-8")) or return nil
      meta = YAML.safe_load(match[1]) || {}
      return nil if meta["name"].to_s.empty?

      Agent.new(
        name: meta["name"].to_s,
        description: meta["description"].to_s,
        handles: Array(meta["handles"]).map { |s| s.to_s.to_sym },
        advances_to: meta["advances_to"]&.to_s&.then { |s| s.empty? ? nil : s.to_sym },
        model: meta["model"],
        allowed_tools: Array(meta["allowed_tools"]).map(&:to_s),
        may: Array(meta["may"]).map { |c| c.to_s.strip.squeeze(" ") },
        network: meta["network"] == true,
        # A present-but-unparseable value reads as 0 through to_i, which would
        # abandon the agent instantly. Only a positive integer counts; anything
        # else falls back to the default.
        timeout: meta["timeout"]&.to_i&.then { |n| (n > 0) ? n : nil },
        prompt: match[2].strip,
        path: path
      )
    end
  end
end
