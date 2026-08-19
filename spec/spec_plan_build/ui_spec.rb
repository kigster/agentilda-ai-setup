# frozen_string_literal: true

RSpec.describe SpecPlanBuild::UI do
  # The suite never runs against a terminal, so `animate?` is false by default
  # and the examples that want animation say so explicitly.
  before { described_class.quiet = false }

  after { described_class.quiet = false }

  describe ".animate?" do
    it "is false when STDERR is not a terminal, whatever else is true" do
      allow($stderr).to receive(:tty?).and_return(false)

      expect(described_class).not_to be_animate
    end

    it "is false on a terminal when the caller asked for quiet" do
      allow($stderr).to receive(:tty?).and_return(true)
      described_class.quiet = true

      expect(described_class).not_to be_animate
    end

    it "is true only on a terminal that has not asked for quiet" do
      allow($stderr).to receive(:tty?).and_return(true)

      expect(described_class).to be_animate
    end
  end

  describe ".spinning" do
    context "when nothing is animated — a pipe, a CI log, or --quiet" do
      before { allow($stderr).to receive(:tty?).and_return(false) }

      it "returns the block's value untouched" do
        expect(described_class.spinning("working") { :the_result }).to eq(:the_result)
      end

      # The property that keeps CI logs readable: spinner frames written to a
      # file are line noise, and a CI log is a file.
      it "writes nothing at all" do
        expect { described_class.spinning("working") { :x } }.not_to output.to_stderr
      end

      it "lets an exception through rather than swallowing it" do
        expect { described_class.spinning("working") { raise ArgumentError, "boom" } }
          .to raise_error(ArgumentError, "boom")
      end
    end

    context "on a terminal" do
      let(:spinner) { instance_double(TTY::Spinner, auto_spin: nil, success: nil, error: nil) }

      before do
        allow($stderr).to receive(:tty?).and_return(true)
        allow(TTY::Spinner).to receive(:new).and_return(spinner)
      end

      it "spins while the work runs and marks it done" do
        expect(described_class.spinning("working") { :done }).to eq(:done)

        aggregate_failures do
          expect(spinner).to have_received(:auto_spin)
          expect(spinner).to have_received(:success)
        end
      end

      # Without this the spinner keeps spinning over the backtrace, and the
      # terminal is left with a half-drawn frame.
      it "marks the spinner failed and re-raises when the work blows up" do
        expect { described_class.spinning("working") { raise "boom" } }.to raise_error("boom")

        expect(spinner).to have_received(:error)
      end
    end
  end

  describe ".stepping" do
    let(:items) { [1, 2, 3, 4, 5] }

    context "when nothing is animated" do
      before { allow($stderr).to receive(:tty?).and_return(false) }

      it "still yields every item, in order" do
        seen = []
        described_class.stepping(items, "working") { |i| seen << i }

        expect(seen).to eq(items)
      end

      it "writes nothing at all" do
        expect { described_class.stepping(items, "w") { |_| nil } }.not_to output.to_stderr
      end
    end

    context "on a terminal" do
      let(:bar) { instance_double(TTY::ProgressBar, advance: nil, finish: nil) }

      before do
        allow($stderr).to receive(:tty?).and_return(true)
        allow(TTY::ProgressBar).to receive(:new).and_return(bar)
      end

      it "advances once per item and finishes" do
        described_class.stepping(items, "working") { |_| nil }

        aggregate_failures do
          expect(bar).to have_received(:advance).exactly(items.size).times
          expect(bar).to have_received(:finish)
        end
      end

      # A bar for two items appears and vanishes before the eye resolves it,
      # and the line it prints is longer than the work it describes.
      it "draws no bar below the threshold, but still does the work" do
        seen = []
        described_class.stepping([1, 2], "working") { |i| seen << i }

        aggregate_failures do
          expect(TTY::ProgressBar).not_to have_received(:new)
          expect(seen).to eq([1, 2])
        end
      end
    end
  end

  # Column alignment in a terminal is measured in cells, and a character is
  # not a cell. Every example here is a case where counting characters — what
  # `format("%-4s")` does — gets the width wrong.
  describe ".fit" do
    it "pads a plain string to the asked-for width" do
      expect(described_class.fit("ab", 5)).to eq("ab   ")
    end

    it "truncates a string wider than the column" do
      expect(described_class.fit("abcdef", 3)).to eq("abc")
    end

    # "✅" is a single character that occupies two cells, so `%-2s` would leave
    # it unpadded at two cells wide — right by luck — while `%-3s` would pad it
    # to four.
    it "counts a one-character wide emoji as the two cells it draws" do
      expect(described_class.fit("✅", 2)).to eq("✅")
    end

    # "⚪️" is a base character plus a variation selector: two characters, still
    # two cells.
    it "counts a two-character emoji as the two cells it draws" do
      expect(described_class.fit("⚪️", 2)).to eq("⚪️")
    end

    # And the case that motivated all of this: two characters, but only one
    # cell, so it needs a space to sit in the same column as its neighbours.
    it "pads an emoji that draws narrower than it is written" do
      expect(described_class.fit("🅱️", 2)).to eq("🅱️ ")
    end

    it "never returns something wider than the column it was given" do
      widths = SpecPlanBuild::STATUSES.map { |s| described_class.display_width(described_class.fit(s.emoji, 2)) }

      expect(widths.uniq).to eq([2])
    end
  end

  describe ".display_width" do
    it "measures cells rather than characters" do
      aggregate_failures do
        expect(described_class.display_width("abc")).to eq(3)
        expect(described_class.display_width("✅")).to eq(2)
        expect(described_class.display_width("")).to eq(0)
      end
    end
  end
end
