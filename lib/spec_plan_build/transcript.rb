# frozen_string_literal: true

require "json"

module SpecPlanBuild
  # What an agent is doing, while it is still doing it.
  #
  # `claude -p` prints nothing until it exits, so a fifteen-minute agent used to
  # sit behind a spinner that said only its name. Asked for `--output-format
  # stream-json` it emits one JSON object per line as it works, and this turns
  # that stream into the short phrase a spinner line has room for: "editing
  # spec.md", "reading plan.md", whatever the agent last said about itself.
  #
  # Three things make this less trivial than parsing JSON.
  #
  # Chunks arrive from `readpartial`, so a line is split across two of them as
  # often as not. {#push} buffers and only ever parses whole lines.
  #
  # Not every line is JSON. `claude` reports its own failures as prose on
  # stdout, and the 401 that cost a whole run three minutes an agent was one of
  # those. Those lines are kept in {#plain} so a failure can still be explained
  # by what was actually printed.
  #
  # The reader runs on its own thread, so {#activity} is written from one
  # thread and read from another. It is a single assignment of an immutable
  # string, which is why there is no lock here.
  class Transcript
    # Longest phrase a spinner line can carry without wrapping into the next.
    LIMIT = 56

    # How each tool reads as something being done, rather than as a tool name.
    # A spinner says what is happening; "Edit" is a noun and says nothing.
    VERBS = {
      "Read" => "reading", "Write" => "writing", "Edit" => "editing",
      "MultiEdit" => "editing", "NotebookEdit" => "editing",
      "Bash" => "running", "Grep" => "searching for", "Glob" => "looking for",
      "Task" => "delegating", "TodoWrite" => "planning",
      "WebFetch" => "fetching", "WebSearch" => "searching the web for"
    }.freeze

    # The input key worth naming, per tool, in the order we would rather say it.
    # `description` outranks `command` deliberately: Claude's Bash tool carries
    # a written summary of why it is running something, and "Read NOTES.md" is
    # a better spinner line than sixty characters of absolute path.
    SUBJECTS = %w[file_path pattern description command query url].freeze

    # @yieldparam phrase [String] each time the agent moves on to something new
    def initialize(&on_activity)
      @on_activity = on_activity
      @buffer = +""
      @plain = []
      @activity = nil
      @result = nil
      @error = nil
    end

    # @return [String, nil] the last thing the agent was seen doing
    attr_reader :activity

    # @return [String, nil] the final text, from the `result` event
    attr_reader :result

    # @return [Array<String>] lines that were not JSON, in order
    attr_reader :plain

    # @return [Boolean] whether the stream reported its own failure
    def failed? = !@error.nil?

    # @return [String, nil] what the agent said went wrong
    attr_reader :error

    # Feed one chunk of stdout. Safe to call with a partial line, which is the
    # normal case.
    #
    # @param chunk [String, nil]
    # @return [void]
    def push(chunk)
      return if chunk.nil?

      @buffer << chunk
      while (index = @buffer.index("\n"))
        line = @buffer.slice!(0..index).chomp
        consume(line)
      end
    end

    # Whatever is left when the process exits, which may be a last line with no
    # newline after it.
    #
    # @return [void]
    def finish
      consume(@buffer.slice!(0..-1).to_s)
    end

    private

    # @param line [String]
    # @return [void]
    def consume(line)
      text = line.strip
      return if text.empty?

      unless text.start_with?("{")
        @plain << text
        return
      end

      event = begin
        JSON.parse(text)
      rescue JSON::ParserError
        @plain << text
        return
      end

      handle(event)
    end

    # @param event [Hash]
    # @return [void]
    def handle(event)
      case event["type"]
      when "assistant" then announce(phrase_for(event))
      when "result" then record_result(event)
      end
    end

    # @param event [Hash]
    # @return [void]
    def record_result(event)
      @result = event["result"].to_s
      @error = @result if event["is_error"]
    end

    # The most recent block wins: an agent that says "now I'll edit the spec"
    # and then edits it is more usefully reported as editing it.
    #
    # @param event [Hash]
    # @return [String, nil]
    def phrase_for(event)
      blocks = event.dig("message", "content")
      return nil unless blocks.is_a?(Array)

      blocks.reverse.filter_map { |block| block_phrase(block) }.first
    end

    # @param block [Hash]
    # @return [String, nil]
    def block_phrase(block)
      case block["type"]
      when "tool_use" then tool_phrase(block)
      when "text" then sentence(block["text"])
      end
    end

    # @param block [Hash]
    # @return [String]
    def tool_phrase(block)
      verb = VERBS.fetch(block["name"].to_s, "using #{block["name"]}")
      input = block["input"]
      return verb unless input.is_a?(Hash)

      key = SUBJECTS.find { |k| input[k].to_s.strip != "" }
      return verb unless key
      # A description is already a phrase. Prefixing it with a verb gives
      # "running Read NOTES.md", which reads worse than either half alone.
      return clip(noun(key, input[key])) if key == "description"

      clip("#{verb} #{noun(key, input[key])}")
    end

    # A path is only ever interesting by its last segment on a line this short.
    #
    # @param key [String]
    # @param value [Object]
    # @return [String]
    def noun(key, value)
      text = value.to_s.strip.tr("\n", " ").squeeze(" ")
      (key == "file_path") ? File.basename(text) : text
    end

    # The agent's own narration, first sentence only. Everything after it is
    # detail the spinner has no room for.
    #
    # @param text [String, nil]
    # @return [String, nil]
    def sentence(text)
      line = text.to_s.split("\n").map(&:strip).find { |l| !l.empty? } or return nil
      line = line.sub(/\A[#>*\-\s]+/, "").split(/(?<=[.!?])\s/).first.to_s.strip
      line.empty? ? nil : clip(line)
    end

    # @param text [String]
    # @return [String]
    def clip(text) = (text.length > LIMIT) ? "#{text[0, LIMIT - 1]}…" : text

    # @param phrase [String, nil]
    # @return [void]
    def announce(phrase)
      return if phrase.nil? || phrase == @activity

      @activity = phrase
      @on_activity&.call(phrase)
    end
  end
end
