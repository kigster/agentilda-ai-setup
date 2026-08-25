# frozen_string_literal: true

module SpecPlanBuild
  # `spec-plan-build agents` — who the specialists are, what each is offered
  # work from, and what one of them actually says when you open it.
  #
  # {#list} and {#describe} return strings and print nothing, the same bargain
  # {Reporter} makes, so the caller decides where the text goes and the table
  # stays pipeable.
  #
  # Everything here is read from the definition files. Nothing about a
  # specialty is restated in Ruby, because a second copy of "who does what" is
  # a copy that drifts from the frontmatter the loop actually routes on.
  class Roster
    # Columns, so the header and the rows cannot drift apart.
    HEADINGS = ["Agent", "Handles", "Advances to", "Model"].freeze

    # What an agent with no `advances_to` is, in the one word that explains why
    # `run` never offers it work.
    READ_ONLY = "read-only"

    # @param agents [SpecPlanBuild::Agents]
    def initialize(agents: Agents.new)
      @agents = agents
    end

    # @return [SpecPlanBuild::Agents]
    attr_reader :agents

    # One line per agent, in name order.
    #
    # @return [String] newline-terminated
    def list
      all = agents.all
      return "No agent definitions in #{agents.dir}\n" if all.empty?

      [header(all), *all.map { |agent| row(agent, all) }].join("\n") + "\n"
    end

    # One agent in full, prompt included.
    #
    # @param name [String, nil] nil describes every agent
    # @return [String] newline-terminated
    # @raise [SpecPlanBuild::Error] when no agent goes by that name
    def describe(name = nil)
      return agents.all.map { |agent| detail(agent) }.join("\n") if name.nil?

      agent = agents.find(name) or
        raise Error, "No agent called #{name}. Known: #{agents.all.map(&:name).join(", ")}"

      detail(agent)
    end

    private

    # A state as the folder names write it, so what an agent handles reads the
    # same here as it does in `status` and on disk.
    #
    # @param key [Symbol]
    # @return [String]
    def state(key)
      status = STATUS_BY_KEY[key] or return key.to_s
      "#{status.emoji} #{status.label}"
    end

    # @param agent [SpecPlanBuild::Agent]
    # @return [String]
    def handles(agent) = agent.handles.map { |key| state(key) }.join(", ")

    # @param agent [SpecPlanBuild::Agent]
    # @return [String]
    def advances(agent) = agent.advances_to ? state(agent.advances_to) : READ_ONLY

    # @param all [Array<SpecPlanBuild::Agent>]
    # @return [Integer]
    def name_width(all) = @name_width ||= all.map { |a| UI.display_width(a.name) }.max.to_i + 2

    # @param all [Array<SpecPlanBuild::Agent>]
    # @return [Integer]
    def handles_width(all)
      @handles_width ||= (all.map { |a| UI.display_width(handles(a)) } + [UI.display_width(HEADINGS[1])]).max.to_i + 2
    end

    # @param all [Array<SpecPlanBuild::Agent>]
    # @return [Integer]
    def advances_width(all)
      @advances_width ||= (all.map { |a| UI.display_width(advances(a)) } + [UI.display_width(HEADINGS[2])]).max.to_i + 2
    end

    # Cells arrive fitted and then painted, in that order: escape codes count
    # toward a string's length, so padding a coloured string pads it to a width
    # of which several characters are invisible. See {Reporter#row}.
    #
    # @return [String]
    def line(name, handled, advances, model)
      format("  %s %s %s %s", name, handled, advances, model).rstrip
    end

    # @param all [Array<SpecPlanBuild::Agent>]
    # @return [String]
    def header(all)
      text = line(UI.fit(HEADINGS[0], name_width(all)),
        UI.fit(HEADINGS[1], handles_width(all)),
        UI.fit(HEADINGS[2], advances_width(all)),
        HEADINGS[3])

      rule = "  " + ("─" * (UI.display_width(text) - 2))

      [UI.paint(text, :bold), UI.paint(rule, :bright_yellow)].join("\n")
    end

    # @param agent [SpecPlanBuild::Agent]
    # @param all [Array<SpecPlanBuild::Agent>]
    # @return [String]
    def row(agent, all)
      line(UI.paint(UI.fit(agent.name, name_width(all)), :bright_cyan),
        UI.fit(handles(agent), handles_width(all)),
        UI.paint(UI.fit(advances(agent), advances_width(all)), agent.read_only? ? :bright_black : :green),
        UI.paint(agent.model.to_s, :bright_black))
    end

    # An agent in full: the frontmatter the loop routes on, then the prompt
    # itself, because the prompt is the definition and a summary of it would be
    # one more thing to keep true.
    #
    # @param agent [SpecPlanBuild::Agent]
    # @return [String]
    def detail(agent)
      [
        UI.paint(agent.name, :bold),
        agent.description,
        "",
        field("Handles", handles(agent)),
        field("Advances to", advances(agent)),
        field("Model", agent.model.to_s),
        field("Network", agent.network ? "yes" : "no"),
        field("Allowed tools", agent.allowed_tools.empty? ? "(inherits the default set)" : agent.allowed_tools.join(", ")),
        field("May", agent.may.empty? ? "(nothing lifted)" : agent.may.join(", ")),
        field("Defined in", agent.path),
        "",
        UI.paint("─" * 60, :bright_yellow),
        agent.prompt,
        ""
      ].join("\n")
    end

    # @param label [String]
    # @param value [String]
    # @return [String]
    def field(label, value) = "#{UI.paint(UI.fit("#{label}:", 16), :bright_black)} #{value}"
  end
end
