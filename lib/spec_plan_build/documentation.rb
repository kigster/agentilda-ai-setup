# frozen_string_literal: true

module SpecPlanBuild
  # Generates the conventions document from the state machine itself.
  #
  # The tables and the diagram are DERIVED — from {STATUSES}, {Lifecycle::INBOUND}
  # and {Ordinal} — so they cannot drift from the tool the way three
  # hand-maintained copies of the status table already did.
  #
  # The prose is not derived, because a machine cannot invent the reasoning: why
  # the tool refuses rather than guesses, why a retroactive plan gets its own
  # number shape, what happens to this scheme if a real issue tracker arrives.
  # That lives in the heredocs below, in one place, and is emitted alongside the
  # generated parts.
  class Documentation
    # @return [String] the whole document
    def render
      [
        header,
        numbering,
        status_table,
        transitions,
        diagram,
        files_section,
        pull_requests,
        footer
      ].join("\n")
    end

    private

    # @return [String]
    def header
      <<~MARKDOWN
        # Spec → Plan → Build

        > [!IMPORTANT]
        > **This file is generated.** Run `spec-plan-build docs -o context/feature-building/spec-plan-build.md`
        > after changing the state machine. Editing it by hand puts it back into the
        > condition it was written to end: three copies of the same table, quietly
        > disagreeing.

        Every project keeps its plans in a `#{SpecPlanBuild::PLANS_DIR}/` directory at its root.
        Each medium-to-large feature gets one folder, and the folder's **name is its
        state**: the number identifies it forever, the emoji says what phase it is in,
        and the slug says what it is.

        There are three phases, and each one has a file that proves it happened:

        | Phase | State | The file that proves it |
        | :---- | :---- | :---------------------- |
        | **spec** | #{status(:new).emoji} #{status(:new).label} | `spec.md` |
        | **plan** | #{status(:ready).emoji} #{status(:ready).label} | `plan.md` |
        | **build** | #{status(:wip).emoji} → #{status(:done).emoji} | `pull-requests.md` |

        Those files are not paperwork. They are what the tool checks: a folder may not
        claim a phase whose file is missing, and `spec-plan-build resync dirs` renames
        any folder whose emoji its contents do not support.

      MARKDOWN
    end

    # @return [String]
    def numbering
      <<~MARKDOWN
        ## The number

        A plan's number is its identity. It is set once, when the folder is created,
        and never changes: branch names, pull request titles and every
        `pull-requests.md` join on it, and renumbering breaks all of them silently.

        The shape is always `NNN.MM`:

        ```
        #{SpecPlanBuild::PLANS_DIR}/000.00-#{status(:new).emoji}-initial-spec
        #{SpecPlanBuild::PLANS_DIR}/001.00-#{status(:done).emoji}-dev-foundation
        #{SpecPlanBuild::PLANS_DIR}/001.01-#{status(:done).emoji}-schedule-k1-backfill   <- shipped between 001 and 002,
        #{SpecPlanBuild::PLANS_DIR}/002.00-#{status(:ready).emoji}-tenancy-households        specified afterwards
        ```

        - **`NNN` counts from `000`.** The first plan of a project is `000.00`; after
          that it is the highest major plus one, zero-padded to three digits.
        - **`MM` is `00` for an ordinary plan** — one specified before it was built.
        - **`MM` from `01` to `99` marks a retroactive plan**: work that shipped with no
          specification, documented after the fact. `spec-plan-build create --after 001`
          takes the next free slot in the gap after 001.

        `001.01` is a **sibling of 001 that arrived later, not a part of 001**. The dot
        reads as containment in almost every other numbering scheme, and here it does
        not — which is worth saying wherever the scheme is described, because the
        containment reading is the one a new reader brings.

        Two digits, always. One would sort into the middle of the two-digit range —
        `001.09` < `001.1` < `001.10` — so a single mixed-width folder silently
        reorders the index. Two digits also retire the question of running out: 99
        slots per gap, against a gap that closes the moment the next plan is created.

        > [!NOTE]
        > Padding every plan to `NNN.MM` is a deliberate choice, and it costs something.
        > A bare `018` next to `018.01` would have told you at a glance which plan was
        > specified in advance and which was written afterwards. With uniform padding
        > that distinction is no longer readable from the number alone — it is carried
        > by `MM > 0`, which you have to know to look for. What padding buys is
        > alignment and one shape to parse everywhere.

        **A retroactive `spec.md` must open with a dated line saying so**, naming the
        pull requests it describes. It documents what exists; it does not pretend to
        have decided anything in advance. Anchor by *when the work merged*, not by what
        it is about — compare merge dates against folder creation dates
        (`git log --diff-filter=A`). Anchoring by topic invites an argument nobody can
        settle, and the number is a slot, not a claim about subject matter.

      MARKDOWN
    end

    # @return [String]
    def status_table
      rows = SpecPlanBuild::STATUSES.map do |s|
        required = s.requires.empty? ? "—" : s.requires.map { |f| "`#{f}`" }.join(", ")
        "| #{s.emoji} | **#{s.label}** | `#{s.key}` | #{required} | #{s.note} |"
      end

      <<~MARKDOWN
        ## The states

        | Symbol | Meaning | Key | Files required | Description |
        | :----: | :------ | :-- | :------------- | :---------- |
        #{rows.join("\n")}

        "Files required" is a **minimum**, not an exact match: a #{status(:new).emoji} folder that
        has grown a `plan.md` still satisfies #{status(:new).emoji}, and is #{status(:ready).emoji} anyway. That is
        why `resync dirs` moves a folder to the furthest state its contents justify
        rather than only fixing outright lies.

        Two states share their requirements on purpose. #{status(:blocked).emoji} #{status(:blocked).label} and
        #{status(:product_blocked).emoji} #{status(:product_blocked).label} both mean "a human must decide before this can
        move"; *which* human is recorded nowhere but the emoji. So nothing re-derives
        one from a folder's contents — otherwise every #{status(:blocked).emoji} would silently become
        #{status(:product_blocked).emoji} the first time anything resynced.

        #{merged_note}

      MARKDOWN
    end

    # @return [String]
    def merged_note
      "🟣 Merged is deliberately **not** a folder state. It describes a pull request, " \
        "and a folder that claimed it would be claiming a pull request's condition as its own."
    end

    # @return [String]
    def transitions
      rows = SpecPlanBuild::STATUSES.map do |s|
        out = Lifecycle::OUTBOUND.fetch(s.key, [])
        targets = out.empty? ? "_terminal_" : out.map { |k| status(k).emoji }.join(" ")
        spine = Lifecycle::SPINE[s.key]
        "| #{s.emoji} #{s.label} | #{targets} | #{spine ? "#{status(spine).emoji} #{status(spine).label}" : "—"} |"
      end

      <<~MARKDOWN
        ## Transitions

        | From | May become | `promote` goes to |
        | :--- | :--------- | :---------------- |
        #{rows.join("\n")}

        A bare promote walks the **spine** — spec → plan → build. Everything off it
        (blocking, deferring, rejecting) has to be named explicitly. That is the whole
        reason there is a machine here rather than a rename: a transition is refused
        when the destination's requirements are not already met, and that refusal is
        information — it means the phase has not actually happened yet.

      MARKDOWN
    end

    # @return [String]
    def diagram
      edges = Lifecycle::INBOUND.flat_map { |to, froms|
        froms.map { |from| "    #{from} --> #{to}" }
      }

      <<~MARKDOWN
        ```mermaid
        stateDiagram-v2
            direction LR
        #{SpecPlanBuild::STATUSES.map { |s| "    #{s.key} : #{s.emoji} #{s.label}" }.join("\n")}

        #{edges.join("\n")}
        ```

      MARKDOWN
    end

    # @return [String]
    def files_section
      known = SpecPlanBuild::STATUSES
        .flat_map(&:requires)
        .uniq
        .map { |f| "| `#{f}` | #{holders_of(f)} |" }

      <<~MARKDOWN
        ## Files allowed in a plan folder

        | File | Required by |
        | :--- | :---------- |
        | `spec.md` | the specification; written first |
        | `plan.md` | the execution plan; written from the spec |
        #{known.reject { |r| r.start_with?("| `spec.md`", "| `plan.md`") }.join("\n")}

        Nothing else belongs there. A folder holding notes, diagrams or scratch files
        is a folder nobody can audit at a glance.

      MARKDOWN
    end

    # @param file [String]
    # @return [String]
    def holders_of(file)
      SpecPlanBuild::STATUSES
        .select { |s| s.requires.include?(file) }
        .map { |s| "#{s.emoji} #{s.label}" }
        .join(", ")
    end

    # @return [String]
    def pull_requests
      <<~MARKDOWN
        ## Pull requests carry the number

        A pull request that implements a plan says so in its title:

        ```
        [003.00] Make the core deterministic and require as_of
        ```

        `pull-requests.md` is generated from these titles, so the prefix is the join key
        between a pull request and a plan, not decoration. Name branches
        `<user>/NNN.MM-slug` and the number carries itself from branch creation through
        to a merged, squashed pull request with nobody having to remember it.

        `spec-plan-build resync prs` fills in missing prefixes. It reads the branch name
        first and falls back to the diff only when that touches exactly one plan folder.
        **It refuses rather than guessing.** A wrong number does not announce itself: it
        files the work under a plan that did not do it, and leaves the plan that did
        looking untouched.

        ### `[#{SpecPlanBuild::NO_PLAN_PREFIX}]` when there is no plan

        Not every pull request implements a feature. Dependency bumps, CI configuration,
        hotfixes and developer tooling implement no plan, and forcing a number onto them
        produces a number chosen to satisfy the rule. Those are titled:

        ```
        [#{SpecPlanBuild::NO_PLAN_PREFIX}] Bump json from 2.21.1 to 2.21.2
        ```

        `#{SpecPlanBuild::NO_PLAN_PREFIX}` means **"this deliberately belongs to no specification"**, and it
        exists so that "no plan" is *asserted* rather than merely absent. A title with no
        prefix is ambiguous between "no plan applies" and "nobody looked".

        `resync prs` will propose it, but marks every such title as **assumed** and never
        applies one without you seeing it. Emitting it silently on a failed lookup would
        launder "I could not tell" into "there is definitely none", which is the same
        lie as guessing a number, told in the other direction.

        ### What does not deserve a retroactive plan

        Most unmatched pull requests. The test is whether **somebody would need to read
        it** — a capability with behaviour, an interface, or invariants that are not
        obvious from the code. "Fix a typo", "remove dead code" and "bump a dependency"
        are `[#{SpecPlanBuild::NO_PLAN_PREFIX}]` and always were. Backfilling those produces an index that is
        longer without being more informative, which makes the real plans harder to find.

      MARKDOWN
    end

    # @return [String]
    def footer
      <<~MARKDOWN
        ## If a real issue tracker arrives, this scheme retires

        This numbering is homegrown because there is nothing else to join on. If the
        work moves to Linear or Jira, **the issue key replaces it**: `[EQL-142] <title>`
        in pull request titles, `EQL-142-<status>-<slug>` for the folder, and the issue
        becomes the thing `pull-requests.md` is generated against.

        Recording that matters more than it looks. A numbering scheme with no stated
        exit becomes permanent by default: it accretes tooling, the tooling accretes
        rules, and by the time a real tracker shows up, migrating is a project rather
        than a decision. The exit is cheap only while it is written down and unbuilt.

        Two things to hold to when that day comes:

        - **Existing numbers are not rewritten.** A plan's number is its identity and
          merged pull request titles are immutable history. `000` stays `000` forever and
          new plans start taking issue keys. A mixed index is ugly for a while and honest
          permanently, which beats a renumbering that breaks every link that ever pointed
          at a plan.
        - **Do not teach the tooling to accept issue keys before the tracker exists.** A
          validator that accepts `[EQL-142]` with nothing to check it against is a guard
          that passes anything shaped like an answer, which is worse than one that fails
          loudly on first use.

        ______________________________________________________________________

        Generated by `spec-plan-build docs` — version #{SpecPlanBuild::VERSION}.
      MARKDOWN
    end

    # @param key [Symbol]
    # @return [SpecPlanBuild::Status]
    def status(key) = SpecPlanBuild::STATUS_BY_KEY.fetch(key)
  end
end
