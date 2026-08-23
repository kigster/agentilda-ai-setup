# frozen_string_literal: true

require "tty/spinner/multi"

module SpecPlanBuild
  # Everything the user sees that is not the deliverable itself.
  #
  # Include it and you get `info`, `warn`, `error` and `success` as instance
  # methods, each drawing a TTY::Box on **STDERR**. STDERR is deliberate: the
  # documents and tables these commands produce own STDOUT, so every command
  # composes in a pipe.
  #
  # @example
  #   class Thing
  #     include SpecPlanBuild::UI
  #     def run = success("Linked 4 skills")
  #   end
  module UI
    # Widest a box may be drawn, regardless of how wide the terminal is.
    MAX_WIDTH = 100

    # Narrowest, so a small terminal still produces readable boxes.
    MIN_WIDTH = 60

    # Below this many items a progress bar is noise: it appears and vanishes
    # before the eye resolves it, and the line it prints is longer than the work.
    PROGRESS_THRESHOLD = 3

    class << self
      # Set by the CLI's --quiet. Silences spinners and bars along with
      # everything else, so a quiet run really is quiet.
      #
      # @return [Boolean]
      attr_accessor :quiet

      # @return [Pastel] colour engine, disabled when STDERR is not a terminal
      def pastel = @pastel ||= Pastel.new(enabled: color?)

      # Forget everything memoized here.
      #
      # Pastel captures `enabled:` once, at construction. Anything that changes
      # the answer afterwards — a test stubbing `tty?`, a caller setting
      # NO_COLOR late — would otherwise be ignored for the rest of the process,
      # and the first answer would leak into every later call.
      #
      # @return [void]
      def reset!
        remove_instance_variable(:@pastel) if instance_variable_defined?(:@pastel)
        self.quiet = false
        self.log_path = nil
      end

      # Where {.log} appends to, if anywhere. nil (the default) means nowhere;
      # `spec-plan-build run` sets this before the loop starts, so a round
      # started under a tool that discards STDERR — an agent's own Bash call,
      # for instance — still leaves something to `tail -f`.
      #
      # @return [String, nil]
      attr_accessor :log_path

      # Append one timestamped line to {.log_path}. A no-op with nothing set.
      # Safe to call from several threads at once.
      #
      # @param message [String]
      # @return [void]
      def log(message)
        path = log_path or return

        (@log_mutex ||= Mutex.new).synchronize do
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") { |f| f.puts("[#{Time.now.strftime("%H:%M:%S")}] #{message}") }
        end
      end

      # @return [Boolean] whether STDERR is an interactive terminal
      def tty? = $stderr.tty?

      # Whether animated output is worth drawing at all. A pipe, a CI log or a
      # --quiet run gets none: spinner frames written to a file are line noise.
      #
      # @return [Boolean]
      def animate? = tty? && !quiet

      # Indeterminate work — one call whose duration cannot be predicted, such
      # as a network round trip. The spinner runs until the block returns.
      #
      # @param message [String] what is being waited on
      # @yieldreturn [Object] whatever the work produces
      # @return [Object] the block's value, untouched
      def spinning(message)
        return yield(logging_activity(message)) unless animate?

        spinner = TTY::Spinner.new("[:spinner] #{message}:activity", format: :dots, output: $stderr,
          success_mark: paint("✓", :green), error_mark: paint("✖", :red))
        spinner.update(activity: "")
        spinner.auto_spin
        begin
          result = yield(activity_for(spinner))
          spinner.success(paint("done", :bright_black))
          result
        rescue
          spinner.error(paint("failed", :red))
          raise
        end
      end

      # Determinate work — N items of roughly equal cost. Yields each item and
      # advances the bar; returns the collection so it can be chained.
      #
      # @param items [Array]
      # @param message [String]
      # @yieldparam item [Object]
      # @return [Array] +items+
      def stepping(items, message)
        list = items.to_a
        return list.each { |item| yield item } unless animate? && list.size >= PROGRESS_THRESHOLD

        bar = TTY::ProgressBar.new(
          "#{message} [:bar] :current/:total :percent",
          total: list.size, output: $stderr, width: 24,
          complete: "█", incomplete: "░", head: "█"
        )
        list.each do |item|
          yield item
          bar.advance
        end
        bar.finish
        list
      end

      # Run a block over many items at once, one spinner each.
      #
      # This is the shape for work that is independent and slow: each item gets
      # its own line, its own thread and its own success or failure mark, so a
      # long round reads as progress rather than as a hang.
      #
      # Results come back in the order the items were given, not the order they
      # finished — a caller that had to re-sort them would be a caller that
      # eventually forgets to.
      #
      # Every path here — one item, several without a terminal, several with
      # one — reports something. `jobs <= 1 || list.size <= 1` used to bypass
      # all of it and run silently, which is exactly the shape a `--plan
      # NNN.MM` round takes: one plan, one agent, nothing printed until the
      # whole thing finished and it was too late to tell "working" from "hung."
      #
      # @param items [Array]
      # @param message [String] the header line
      # @param jobs [Integer] how many run at once
      # @param label [Proc] item -> the text on its line
      # @yieldparam item [Object]
      # @return [Array] one result per item, in input order
      def concurrently(items, message, jobs:, label: :to_s.to_proc, &block)
        list = items.to_a
        return [] if list.empty?

        log(message)

        if jobs <= 1 || list.size <= 1
          report_line(message) unless animate?
          return list.map { |item| once(item, label, &block) }
        end

        return threaded(list, jobs, message, label:, &block) unless animate?

        results = Concurrent::Hash.new
        spinners = TTY::Spinner::Multi.new(
          ":spinner #{paint(message, :bold)}",
          format: :dots, output: $stderr,
          success_mark: paint("✓", :green), error_mark: paint("✖", :red)
        )

        list.each_with_index do |item, index|
          text = label.call(item)
          child = spinners.register("[:spinner] #{text}:activity") do |spinner|
            log("started  #{text}")
            results[index] = block.call(item, activity_for(spinner))
            log("finished #{text}")
            spinner.success("")
          rescue => e
            log("failed   #{text}: #{e.message.lines.first.to_s.strip}")
            results[index] = e
            spinner.error(paint(e.message.lines.first.to_s.strip, :red))
          end
          # An unset token renders as the literal `:activity`, so every line
          # says so until its agent gets far enough to have news.
          child.update(activity: "")
        end

        spinners.auto_spin
        list.each_index.map { |i| results[i] }
      end

      # The same news, with no spinner to put it on. A piped or CI run still
      # wants it, in the log where the rest of that run's progress goes.
      #
      # @param text [String] the item's label
      # @return [Proc] phrase -> void
      def logging_activity(text) = ->(phrase) { log("#{text}: #{phrase}") }

      # A callable that writes what an agent is doing onto its own spinner line.
      #
      # The `:activity` token is empty until something calls this, so a line
      # reads as it always did until there is news. It is written from the
      # reader thread the command's output arrives on, which is why the token
      # is replaced whole rather than appended to.
      #
      # @param spinner [TTY::Spinner]
      # @return [Proc] phrase -> void
      def activity_for(spinner)
        lambda { |phrase|
          spinner.update(activity: phrase.to_s.empty? ? "" : paint(": #{phrase}", :bright_blue))
        }
      end

      # One item, no concurrency to speak of: a serial round (`--isolation
      # shared`), or the last plan left in a parallel one. A live spinner on a
      # terminal; a start line and a finish line with an elapsed time otherwise.
      #
      # @param item [Object]
      # @param label [Proc]
      # @yieldparam item [Object]
      # @return [Object]
      def once(item, label, &block)
        text = label.call(item)
        return spinning(text) { |activity| block.call(item, activity) } if animate?

        log("started  #{text}")
        started = monotonic
        result = block.call(item, logging_activity(text))
        report_line("#{text} (#{elapsed(started)})", bullet: "✓")
        log("finished #{text} (#{elapsed(started)})")
        result
      rescue => e
        report_line("#{text}: #{e.message.lines.first.to_s.strip}", bullet: "✗")
        log("failed   #{text}: #{e.message.lines.first.to_s.strip}")
        raise
      end

      # Parallelism with no spinner to draw: a pipe, a CI log, or a headless
      # agent's own tool call. Still reports a start and a finish line per
      # item, because "no terminal" is not the same question as "no one is
      # reading this."
      #
      # @param list [Array]
      # @param jobs [Integer]
      # @param message [String]
      # @param label [Proc]
      # @return [Array]
      def threaded(list, jobs, message, label: :to_s.to_proc, &block)
        report_line(message)
        results = Concurrent::Hash.new
        queue = Queue.new
        list.each_with_index { |item, index| queue << [item, index] }

        [jobs, list.size].min.times.map {
          Thread.new do
            while (pair = begin
              queue.pop(true)
            rescue ThreadError
              nil
            end)
              item, index = pair
              results[index] = begin
                once(item, label, &block)
              rescue => e
                e
              end
            end
          end
        }.each(&:join)

        list.each_index.map { |i| results[i] }
      end

      # @return [Float] a monotonic clock reading, immune to wall-clock changes
      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # @param started [Float] a {#monotonic} reading taken before the work began
      # @return [String] e.g. "42s"
      def elapsed(started) = "#{(monotonic - started).round}s"

      # A progress line, thread-safe and quiet-aware — the one thing every
      # non-spinner path above needs and would otherwise have to reimplement.
      #
      # @param text [String]
      # @param bullet [String]
      # @return [void]
      def report_line(text, bullet: "·")
        return if quiet

        (@print_mutex ||= Mutex.new).synchronize { line(text, bullet:) }
      end

      # A sensible worker count: agents are mostly waiting on a model rather
      # than burning CPU, so this is deliberately close to the core count. Two
      # are left for the machine, and the cap keeps a very large tree from
      # opening fifty subprocesses at once.
      #
      # @return [Integer]
      def default_jobs = (Etc.nprocessors - 2).clamp(1, 12)

      # Honours NO_COLOR — https://no-color.org
      #
      # @return [Boolean]
      def color? = tty? && !ENV.key?("NO_COLOR")

      # @return [Integer] a box width that fits the terminal but stays readable
      def width = (TTY::Screen.width - 4).clamp(MIN_WIDTH, MAX_WIDTH)

      # @param text [String]
      # @param styles [Array<Symbol>] pastel style names
      # @return [String] decorated when colour is on, bare otherwise
      def paint(text, *styles) = color? ? pastel.decorate(text.to_s, *styles) : text.to_s

      # @param text [String]
      # @return [Integer] how many terminal cells the text occupies
      def display_width(text) = Unicode::DisplayWidth.of(text.to_s)

      # Pad or truncate to an exact number of terminal *cells*.
      #
      # `format`'s "%-20.20s" counts characters, and a character is not a cell.
      # "✅" is one character two cells wide; "🅱️" is two characters one cell
      # wide. Any column laid out with %s therefore drifts by one for every
      # emoji whose two counts disagree — which is every emoji, in one
      # direction or the other.
      #
      # @param text [String] unpainted; escape codes count as characters and
      #   would be padded like any other
      # @param width [Integer] terminal cells
      # @return [String]
      def fit(text, width)
        text = text.to_s
        text = text[0..-2] while display_width(text) > width
        text + " " * (width - display_width(text))
      end

      # Everything the user sees goes through here, so it writes to `$stderr`
      # directly rather than through `Kernel.warn`.
      #
      # That is not a style preference. `Kernel.warn` is a **no-op** when
      # `$VERBOSE` is nil, which is what `-W0` sets — and `RUBYOPT=-W0` is
      # common in CI images and agent harnesses. Routed through `Kernel.warn`,
      # every box this tool draws silently disappears in exactly the
      # environments where a failure most needs explaining.
      #
      # @param kind [Symbol] :info, :warn, :error or :success
      # @param message [String]
      # @return [void]
      # standard:disable Style/StderrPuts -- the cop's own rationale, "to allow
      # such output to be disabled", is the behaviour being removed here.
      def box(kind, message)
        text = message.to_s
        $stderr.puts TTY::Box.public_send(kind, text, enable_color: color?, width:, height: box_height(text))
      end
      # standard:enable Style/StderrPuts

      # TTY::Box sizes itself from the number of lines you hand it, not from
      # the number those lines occupy once wrapped to the box's width. So it
      # draws any message containing a line longer than the box a row or two
      # short, and what falls off is the bottom, which is where the instruction
      # lives. The run that found this reported four of its ten failures and
      # cut the fifth mid-sentence.
      #
      # This wraps with the same library TTY::Box wraps with rather than
      # dividing by the width, because TTY::Box wraps on words. A rough
      # estimate is wrong in exactly the cases this exists for.
      #
      # @param text [String]
      # @return [Integer] rows the box needs: its content, two borders, one pad
      def box_height(text) = Strings.wrap(text.to_s, width - 4).lines.size + 3

      # A single unadorned line, for per-item progress that does not deserve
      # a box of its own.
      #
      # @param message [String]
      # @param bullet [String]
      # @return [void]
      # standard:disable Style/StderrPuts -- see {.box}: `warn` is a no-op under -W0.
      def line(message, bullet: "·") = $stderr.puts("  #{paint(bullet, :bright_black)} #{message}")
      # standard:enable Style/StderrPuts
    end

    # @param message [String]
    # @return [void]
    def info(message) = UI.box(:info, message)

    # @param message [String]
    # @return [void]
    def warn(message) = UI.box(:warn, message)

    # @param message [String]
    # @return [void]
    def error(message) = UI.box(:error, message)

    # @param message [String]
    # @return [void]
    def success(message) = UI.box(:success, message)

    # @param message [String]
    # @param bullet [String]
    # @return [void]
    def say(message, bullet: "·") = UI.line(message, bullet:)

    # @param text [String]
    # @param styles [Array<Symbol>]
    # @return [String]
    def paint(text, *styles) = UI.paint(text, *styles)
  end
end
