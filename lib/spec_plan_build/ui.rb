# frozen_string_literal: true

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
        return yield unless animate?

        spinner = TTY::Spinner.new("[:spinner] #{message}", format: :dots, output: $stderr,
          success_mark: paint("✓", :green), error_mark: paint("✖", :red))
        spinner.auto_spin
        begin
          result = yield
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
      # @param items [Array]
      # @param message [String] the header line
      # @param jobs [Integer] how many run at once
      # @param label [Proc] item -> the text on its line
      # @yieldparam item [Object]
      # @return [Array] one result per item, in input order
      def concurrently(items, message, jobs:, label: :to_s.to_proc, &block)
        list = items.to_a
        return list.map(&block) if jobs <= 1 || list.size <= 1

        return threaded(list, jobs, &block) unless animate?

        results = Concurrent::Hash.new
        spinners = TTY::Spinner::Multi.new(
          ":spinner #{paint(message, :bold)}",
          format: :dots, output: $stderr,
          success_mark: paint("✓", :green), error_mark: paint("✖", :red)
        )

        list.each_with_index do |item, index|
          spinners.register("[:spinner] #{label.call(item)}") do |spinner|
            results[index] = block.call(item)
            spinner.success("")
          rescue => e
            results[index] = e
            spinner.error(paint(e.message.lines.first.to_s.strip, :red))
          end
        end

        spinners.auto_spin
        list.each_index.map { |i| results[i] }
      end

      # Parallelism with no UI at all — a pipe, a CI log, or --quiet.
      #
      # @param list [Array]
      # @param jobs [Integer]
      # @return [Array]
      def threaded(list, jobs)
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
              begin
                results[index] = yield(item)
              rescue => e
                results[index] = e
              end
            end
          end
        }.each(&:join)

        list.each_index.map { |i| results[i] }
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

      # @param kind [Symbol] :info, :warn, :error or :success
      # @param message [String]
      # @return [void]
      def box(kind, message)
        Kernel.warn TTY::Box.public_send(kind, message.to_s, enable_color: color?, width:)
      end

      # A single unadorned line, for per-item progress that does not deserve
      # a box of its own.
      #
      # @param message [String]
      # @param bullet [String]
      # @return [void]
      def line(message, bullet: "·") = Kernel.warn("  #{paint(bullet, :bright_black)} #{message}")
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
