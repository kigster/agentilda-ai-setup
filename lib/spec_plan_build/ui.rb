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

    class << self
      # @return [Pastel] colour engine, disabled when STDERR is not a terminal
      def pastel = @pastel ||= Pastel.new(enabled: color?)

      # @return [Boolean] whether STDERR is an interactive terminal
      def tty? = $stderr.tty?

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
