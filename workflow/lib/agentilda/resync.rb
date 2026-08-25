# frozen_string_literal: true

module Agentilda
  # Reconciling what is recorded with what is true.
  #
  # Both resyncs are dry-run by default and both refuse to act where they are
  # not certain, because both write to things other people join on: folder
  # names, and pull request titles.
  module Resync
    # `resync dirs` — makes every folder's name say what the folder is.
    #
    # Two things can be wrong with a name, and both are repaired here:
    #
    # - **The emoji is wrong** — the contents justify a different state. A
    #   folder whose status already holds is left alone, which is what stops
    #   ⭕️ Blocked and 🅱️ Product Blocked — deliberately identical invariants,
    #   distinguished only by the name — from collapsing into one.
    # - **The number is not in `NNN.MM` form** — a folder written `018-⚪️-foo`
    #   before the padding rule, or `18.1-⚪️-foo` by hand. These read fine and
    #   sort wrong, which is the whole reason the rule exists: `018.09` <
    #   `018.1` < `018.10` puts a single mixed-width folder in the middle of
    #   the range. Both are renamed to `018.00-⚪️-foo` and `018.01-⚪️-foo`.
    #
    # The two cases collapse into one rule — **rename any folder that is not
    # already named what it should be named** — which is why the emoji fix and
    # the renumber cannot disagree about the target.
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

      # @param tree [Agentilda::Tree]
      def initialize(tree:)
        @tree = tree
      end

      # @return [Agentilda::Tree]
      attr_reader :tree

      # What would change, without changing anything.
      #
      # @return [Array<Agentilda::Resync::Dirs::Change>]
      def plan = tree.subjects.filter_map { |subject| change_for(subject) }

      # @param commit [Boolean] actually rename
      # @return [Array<Agentilda::Resync::Dirs::Change>] what was proposed
      def call(commit: false)
        changes = plan
        return changes unless commit

        UI.stepping(changes, "Renaming") { |change| rename(change) }
        tree.reload
        changes
      end

      private

      # A folder moves when the name it has is not the name it should have.
      #
      # `best_fit` answers "which state do these contents justify", and falls
      # back to the state already claimed when nothing fits — so a folder with
      # an unreadable set of contents still gets its number padded rather than
      # being skipped for a reason that has nothing to do with its number.
      #
      # Invariants are minimum requirements, so a ⚪️ folder that has grown a
      # `plan.md` still satisfies ⚪️ and is ⭐️ anyway.
      #
      # @param subject [Agentilda::Subject]
      # @return [Agentilda::Resync::Dirs::Change, nil]
      def change_for(subject)
        feature = subject.feature
        fit = subject.best_fit || subject.status
        dirname = feature.dirname_as(fit)
        return nil if dirname == feature.dirname

        Change.new(
          dirname: feature.dirname,
          from: subject.status.key,
          to: fit.key,
          source: feature.path,
          target: File.join(File.dirname(feature.path), dirname),
          reason: reason_for(subject, fit)
        )
      end

      # @param subject [Agentilda::Subject]
      # @param fit [Agentilda::Status] the state the folder is moving to
      # @return [String] why the current name is wrong
      def reason_for(subject, fit)
        feature = subject.feature
        return subject.violation || "contents now justify #{fit.label}" unless fit.key == subject.status.key
        return "#{feature.dirname_ordinal} is not padded to #{feature.ordinal}" unless feature.padded?

        "name is not in canonical NNN.MM-<emoji>-<slug> form"
      end

      # A rename that finds its target occupied has not happened, and saying
      # nothing about it would leave the folder misnamed with a report
      # claiming otherwise. Two folders can want the same canonical name —
      # `018-⚪️-foo` and `018.00-⚪️-foo` are the same plan written twice.
      #
      # @param change [Agentilda::Resync::Dirs::Change]
      # @return [void]
      # @raise [Agentilda::Error] when the target name is already taken
      def rename(change)
        return if Agentilda.move_directory(change.source, change.target)

        raise Error, "cannot rename #{change.dirname} — #{File.basename(change.target)} already exists"
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
      # The marker this tool used to write, now replaced. A title wearing it is
      # rewritten in place: the assertion it makes — "this belongs to no
      # specification" — is still true and still somebody's deliberate call,
      # so it is restamped rather than re-resolved.
      STALE = /\A\[#{Regexp.escape(Agentilda::STALE_NO_PLAN_PREFIX)}\]\s*/

      # Titles that already carry a prefix — a plan number, the no-plan marker,
      # or the legacy `[XXX]`.
      PREFIXED = /\A\[(?:\d{3}(?:\.\d{2})?|#{Agentilda::NO_PLAN_PREFIX}|XXX)\](?:\([A-Z]\))?\s/

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
      #   @return [Agentilda::Ordinal, nil]
      # @!attribute [r] reason
      #   @return [String] how it was resolved, or why it was not
      # @!attribute [r] ambiguous
      #   @return [Boolean] a human must decide; never edited
      # @!attribute [r] assumed
      #   @return [Boolean] "no plan" was inferred, not asserted by the author
      Change = Data.define(:number, :title, :new_title, :ordinal, :reason, :ambiguous, :assumed, :adopted) do
        # @return [Boolean]
        def ambiguous? = ambiguous

        # @return [Boolean]
        def assumed? = assumed

        # @return [Boolean] whether a plan folder was minted for this one
        def adopted? = adopted

        # @return [Boolean] safe to apply without a human looking
        def applicable? = !ambiguous && !new_title.nil?
      end

      # @param tree [Agentilda::Tree]
      # @param github [Agentilda::GitHub]
      # @param adopt [Boolean] give a plan folder to every pull request that
      #   resolves to none, rather than flagging it and moving on
      # @param root [String, nil] repository root, for reading branches
      def initialize(tree:, github: GitHub.new, adopt: true, root: nil)
        @tree = tree
        @github = github
        @adopt = adopt
        @root = root
      end

      # @return [Boolean]
      def adopt? = @adopt

      # @return [Agentilda::Tree]
      attr_reader :tree

      # @return [Agentilda::GitHub]
      attr_reader :github

      # What would change, without changing anything.
      #
      # @return [Array<Agentilda::Resync::Prs::Change>]
      def plan
        restamps + resolve(candidates).then { |changes| adopt? ? with_adoptions(changes) : changes }
      end

      # @return [Array<Agentilda::Resync::Prs::Change>]
      def restamps = stale.map { |pull| restamped(pull) }

      # @param commit [Boolean] actually retitle, and mint the folders
      # @return [Array<Agentilda::Resync::Prs::Change>] what was proposed
      def call(commit: false)
        changes = resolve(candidates)
        return restamps + (adopt? ? with_adoptions(changes) : changes) unless commit

        changes = with_adoptions(changes, create: true) if adopt?
        changes = restamps + changes
        applicable = changes.select(&:applicable?)
        UI.stepping(applicable, "Retitling") { |c| github.retitle(number: c.number, title: c.new_title) }
        changes
      end

      # @return [Array<Agentilda::Adoption>] the adopter, memoized
      def adoption = @adoption ||= Adoption.new(tree:, github:, root: @root)

      private

      # @return [Array<Hash>] pull requests with no prefix yet
      def candidates
        github.pulls.reject { |pr| pr[:title].to_s.match?(PREFIXED) || pr[:title].to_s.match?(STALE) }
      end

      # @return [Array<Hash>] pull requests still wearing the old marker
      def stale = github.pulls.select { |pr| pr[:title].to_s.match?(STALE) }

      # @param pull [Hash]
      # @return [Agentilda::Resync::Prs::Change]
      def restamped(pull)
        Change.new(number: pull[:number], title: pull[:title], ordinal: nil, ambiguous: false,
          new_title: pull[:title].sub(STALE, "[#{Agentilda::NO_PLAN_PREFIX}] "),
          reason: "the no-plan marker is now [#{Agentilda::NO_PLAN_PREFIX}]",
          assumed: false, adopted: false)
      end

      # @param pulls [Array<Hash>]
      # @return [Array<Agentilda::Resync::Prs::Change>]
      def resolve(pulls) = pulls.map { |pr| change_for(pr) }

      # Replace every flagged change with one that points at a plan folder the
      # pull request now owns. The unresolvable ones were unresolvable because
      # no plan described them — so the answer is a plan, not a shrug.
      #
      # @param changes [Array<Agentilda::Resync::Prs::Change>]
      # @param create [Boolean] mint the folders, rather than only saying so
      # @return [Array<Agentilda::Resync::Prs::Change>]
      def with_adoptions(changes, create: false)
        orphans = changes.select(&:ambiguous?)
        return changes if orphans.empty?

        pulls = orphans.map { |c| pull_by_number.fetch(c.number) }
        adoptees = create ? adoption.call(pulls) : adoption.plan(pulls)
        by_number = adoptees.to_h { |a| [a.pull[:number], a] }

        changes.map { |c| (c.ambiguous? && by_number[c.number]) ? adopted(c, by_number[c.number]) : c }
      end

      # @return [Hash{Integer => Hash}]
      def pull_by_number = @pull_by_number ||= candidates.to_h { |pr| [pr[:number], pr] }

      # @param change [Agentilda::Resync::Prs::Change]
      # @param adoptee [Agentilda::Adoption::Adoptee]
      # @return [Agentilda::Resync::Prs::Change]
      def adopted(change, adoptee)
        change.with(
          ordinal: adoptee.ordinal,
          new_title: "#{adoptee.ordinal.to_prefix} #{change.title}",
          reason: "#{change.reason} — adopted into #{adoptee.dirname}",
          ambiguous: false,
          adopted: true
        )
      end

      # @param pull [Hash]
      # @return [Agentilda::Resync::Prs::Change]
      def change_for(pull)
        from_branch(pull) || from_files(pull) || no_plan(pull)
      end

      # 1. The branch name — the one moment the author certainly knew.
      #
      # @param pull [Hash]
      # @return [Agentilda::Resync::Prs::Change, nil]
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
      # @return [Agentilda::Resync::Prs::Change, nil]
      def from_files(pull)
        touched = Array(pull[:files]).filter_map { |path| ordinal_for_path(path) }.uniq
        case touched.size
        when 1 then resolved(pull, touched.first, "diff touches only #{touched.first}")
        when 0 then nil
        else flag(pull, "diff touches #{touched.join(", ")} and none is obviously primary")
        end
      end

      # @param path [String] a path from the diff
      # @return [Agentilda::Ordinal, nil]
      def ordinal_for_path(path)
        parts = path.to_s.split("/")
        index = parts.index(Agentilda::PLANS_DIR) or return nil
        folder = parts[index + 1] or return nil
        return nil if parts.length <= index + 2 # a file directly under .plans belongs to no plan

        ordinal = Ordinal.from_dirname(folder)
        ordinal if ordinal && tree.include?(ordinal)
      end

      # @param pull [Hash]
      # @param ordinal [Agentilda::Ordinal]
      # @param why [String]
      # @return [Agentilda::Resync::Prs::Change]
      def resolved(pull, ordinal, why)
        Change.new(number: pull[:number], title: pull[:title], ordinal:, reason: why,
          new_title: "#{ordinal.to_prefix} #{pull[:title]}", ambiguous: false, assumed: false, adopted: false)
      end

      # Nothing resolved, so this is developer work — but that is an assertion
      # about intent, so it is marked as assumed rather than stated as fact.
      #
      # @param pull [Hash]
      # @return [Agentilda::Resync::Prs::Change]
      def no_plan(pull)
        Change.new(number: pull[:number], title: pull[:title], ordinal: nil,
          new_title: "[#{Agentilda::NO_PLAN_PREFIX}] #{pull[:title]}",
          reason: "no plan resolved from the branch or the diff", ambiguous: false, assumed: true, adopted: false)
      end

      # @param pull [Hash]
      # @param why [String]
      # @return [Agentilda::Resync::Prs::Change]
      def flag(pull, why)
        Change.new(number: pull[:number], title: pull[:title], new_title: nil, ordinal: nil,
          reason: why, ambiguous: true, assumed: false, adopted: false)
      end
    end
  end
end
