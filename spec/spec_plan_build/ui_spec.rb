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
end
