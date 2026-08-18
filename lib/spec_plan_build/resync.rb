# frozen_string_literal: true

module SpecPlanBuild
  # Reconciling what is recorded with what is true.
  #
  # Both resyncs are dry-run by default and both refuse to act where they are
  # not certain, because both write to things other people join on: folder
  # names, and pull request titles.
  module Resync
    # `resync dirs` — makes every folder's emoji match what the folder holds.
    #
    # It only ever touches folders whose name is *not* justified by their
    # contents. A folder whose status already holds is left alone, which is
    # what stops ⭕️ Blocked and 🅱️ Product Blocked — deliberately identical
    # invariants, distinguished only by the name — from collapsing into one.
    class Dirs
      # A proposed rename.
      #
      # @!attribute [r] dirname
      #   @return [String] the folder as it stands
      # @!attribute [r] from
      #   @return [Symbol] the state it claims
      # @!attribute [r] to
      #   @return [Symbol] the state its contents justify
      # @!attribute [r] source
      #   @return [String] absolute path now
      # @!attribute [r] target
      #   @return [String] absolute path after
      # @!attribute [r] reason
      #   @return [String] why the current name is wrong
      Change = Data.define(:dirname, :from, :to, :source, :target, :reason) do
        # @return [String] a single auditable line
        def to_s = "#{dirname} → #{File.basename(target)}  (#{reason})"
      end

      # @param tree [SpecPlanBuild::Tree]
      def initialize(tree:)
        @tree = tree
      end

      # @return [SpecPlanBuild::Tree]
      attr_reader :tree

      # What would change, without changing anything.
      #
      # @return [Array<SpecPlanBuild::Resync::Dirs::Change>]
      def plan = tree.subjects.filter_map { |subject| change_for(subject) }

      # @param commit [Boolean] actually rename
      # @return [Array<SpecPlanBuild::Resync::Dirs::Change>] what was proposed
      def call(commit: false)
        changes = plan
        return changes unless commit

        UI.stepping(changes, "Renaming") { |change| rename(change) }
        tree.reload
        changes
      end

      private

      # A folder moves for either of two reasons: its name is a lie, or its
      # name is merely behind. Invariants are minimum requirements, so a ⚪️
      # folder that has grown a `plan.md` still satisfies ⚪️ and is ⭐️ anyway.
      #
      # @param subject [SpecPlanBuild::Subject]
      # @return [SpecPlanBuild::Resync::Dirs::Change, nil]
      def change_for(subject)
        fit = Lifecycle.best_fit(subject)
        return nil if fit.nil? || fit.key == subject.status.key

        feature = subject.feature
        Change.new(
          dirname: feature.dirname,
          from: subject.status.key,
          to: fit.key,
          source: feature.path,
          target: File.join(File.dirname(feature.path), feature.dirname_as(fit)),
          reason: subject.violation || "contents now justify #{fit.label}"
        )
      end

      # Prefer `git mv` so the folder's history follows it.
      #
      # @param change [SpecPlanBuild::Resync::Dirs::Change]
      # @return [void]
      def rename(change)
        return if File.exist?(change.target)

        parent = File.dirname(change.source)
        tracked = system("git", "-C", parent, "ls-files", "--error-unmatch", change.source,
          out: File::NULL, err: File::NULL)
        moved = tracked && system("git", "-C", parent, "mv", change.source, change.target,
          out: File::NULL, err: File::NULL)
        FileUtils.mv(change.source, change.target) unless moved
      end
    end

    # `resync prs` — puts an `[NNN.MM]` prefix on every pull request title that
    # lacks one, and `[DEV.00]` on the ones that implement no plan.
    #
    # The resolution order is the branch name first, then the diff, and only
    # when the diff touches exactly one plan. Anything else is reported for a
    # human and never edited: `pull-requests.md` is generated from these
    # titles, and a wrong number files work under a plan that did not do it,
    # leaving the plan that did looking untouched.
    class Prs
      # Titles that already carry a prefix — a plan number, the no-plan marker,
      # or the legacy `[XXX]`.
      PREFIXED = /\A\[(?:\d{3}(?:\.\d{2})?|DEV\.00|XXX)\](?:\([A-Z]\))?\s/

      # Finds a plan number in a branch name: `kig/018.01-verify`, `002-slug`.
      BRANCH_PATTERN = %r{(?:\A|[/\-_])(\d{3}(?:\.\d{2})?)(?:\z|[-_])}

      # A proposed retitle.
      #
      # @!attribute [r] number
      #   @return [Integer] the pull request
      # @!attribute [r] title
      #   @return [String] as it stands
      # @!attribute [r] new_title
      #   @return [String, nil] nil when nothing may safely be done
      # @!attribute [r] ordinal
      #   @return [SpecPlanBuild::Ordinal, nil]
      # @!attribute [r] reason
      #   @return [String] how it was resolved, or why it was not
      # @!attribute [r] ambiguous
      #   @return [Boolean] a human must decide; never edited
      # @!attribute [r] assumed
      #   @return [Boolean] "no plan" was inferred, not asserted by the author
      Change = Data.define(:number, :title, :new_title, :ordinal, :reason, :ambiguous, :assumed) do
        # @return [Boolean]
        def ambiguous? = ambiguous

        # @return [Boolean]
        def assumed? = assumed

        # @return [Boolean] safe to apply without a human looking
        def applicable? = !ambiguous && !new_title.nil?
      end

      # @param tree [SpecPlanBuild::Tree]
      # @param github [SpecPlanBuild::GitHub]
      def initialize(tree:, github: GitHub.new)
        @tree = tree
        @github = github
      end

      # @return [SpecPlanBuild::Tree]
      attr_reader :tree

      # @return [SpecPlanBuild::GitHub]
      attr_reader :github

      # What would change, without changing anything.
      #
      # @return [Array<SpecPlanBuild::Resync::Prs::Change>]
      def plan
        github.pulls.reject { |pr| pr[:title].to_s.match?(PREFIXED) }.map { |pr| change_for(pr) }
      end

      # @param commit [Boolean] actually retitle
      # @return [Array<SpecPlanBuild::Resync::Prs::Change>] what was proposed
      def call(commit: false)
        changes = plan
        return changes unless commit

        applicable = changes.select(&:applicable?)
        UI.stepping(applicable, "Retitling") { |c| github.retitle(number: c.number, title: c.new_title) }
        changes
      end

      private

      # @param pull [Hash]
      # @return [SpecPlanBuild::Resync::Prs::Change]
      def change_for(pull)
        from_branch(pull) || from_files(pull) || no_plan(pull)
      end

      # 1. The branch name — the one moment the author certainly knew.
      #
      # @param pull [Hash]
      # @return [SpecPlanBuild::Resync::Prs::Change, nil]
      def from_branch(pull)
        match = BRANCH_PATTERN.match(pull[:branch].to_s) or return nil
        ordinal = Ordinal.parse(match[1])

        unless tree.include?(ordinal)
          return flag(pull, "branch names #{ordinal}, which has no folder in #{File.basename(tree.dir)}")
        end

        resolved(pull, ordinal, "branch #{pull[:branch]}")
      end

      # 2. The diff, and only when it touches exactly one plan.
      #
      # @param pull [Hash]
      # @return [SpecPlanBuild::Resync::Prs::Change, nil]
      def from_files(pull)
        touched = Array(pull[:files]).filter_map { |path| ordinal_for_path(path) }.uniq
        case touched.size
        when 1 then resolved(pull, touched.first, "diff touches only #{touched.first}")
        when 0 then nil
        else flag(pull, "diff touches #{touched.join(", ")} and none is obviously primary")
        end
      end

      # @param path [String] a path from the diff
      # @return [SpecPlanBuild::Ordinal, nil]
      def ordinal_for_path(path)
        parts = path.to_s.split("/")
        index = parts.index(SpecPlanBuild::PLANS_DIR) or return nil
        folder = parts[index + 1] or return nil
        return nil if parts.length <= index + 2 # a file directly under .plans belongs to no plan

        ordinal = Ordinal.from_dirname(folder)
        ordinal if ordinal && tree.include?(ordinal)
      end

      # @param pull [Hash]
      # @param ordinal [SpecPlanBuild::Ordinal]
      # @param why [String]
      # @return [SpecPlanBuild::Resync::Prs::Change]
      def resolved(pull, ordinal, why)
        Change.new(number: pull[:number], title: pull[:title], ordinal:, reason: why,
          new_title: "#{ordinal.to_prefix} #{pull[:title]}", ambiguous: false, assumed: false)
      end

      # Nothing resolved, so this is developer work — but that is an assertion
      # about intent, so it is marked as assumed rather than stated as fact.
      #
      # @param pull [Hash]
      # @return [SpecPlanBuild::Resync::Prs::Change]
      def no_plan(pull)
        Change.new(number: pull[:number], title: pull[:title], ordinal: nil,
          new_title: "[#{SpecPlanBuild::NO_PLAN_PREFIX}] #{pull[:title]}",
          reason: "no plan resolved from the branch or the diff", ambiguous: false, assumed: true)
      end

      # @param pull [Hash]
      # @param why [String]
      # @return [SpecPlanBuild::Resync::Prs::Change]
      def flag(pull, why)
        Change.new(number: pull[:number], title: pull[:title], new_title: nil, ordinal: nil,
          reason: why, ambiguous: true, assumed: false)
      end
    end
  end
end
