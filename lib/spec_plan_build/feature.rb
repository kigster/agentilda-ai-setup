# frozen_string_literal: true

module SpecPlanBuild
  # Lowercase in the middle of a title, capitalised at the front.
  SMALL_WORDS = %w[a an and as at but by for from in into nor of on or per the to via vs with].freeze

  # Slug words that are really acronyms and should shout.
  ACRONYMS = %w[
    abac ai api aws cdn ci cd cli cms cors cpu crm css csv db dns dsl e2e ec2 etl gcp gdpr gpu gui
    html http https iam id ide jwt json k8s llm ml mcp mvp npm oauth orm otp pdf pii poc pr prs qa
    rbac rds rest rls rpc rss s3 saas sdk seo sns spa sql sqs sre ssh sso ssl ssr tls tui ts tsx ui
    ux uuid vpc vpn xml yaml
  ].freeze

  # Words with a house spelling that neither capitalize nor upcase gets right.
  SPECIAL_CASE = {
    "github" => "GitHub", "gitlab" => "GitLab", "graphql" => "GraphQL", "ios" => "iOS",
    "javascript" => "JavaScript", "macos" => "macOS", "nodejs" => "Node.js", "oauth" => "OAuth",
    "openai" => "OpenAI", "postgres" => "PostgreSQL", "postgresql" => "PostgreSQL",
    "typescript" => "TypeScript", "uuidv7" => "UUIDv7", "websocket" => "WebSocket"
  }.freeze

  # Turn a kebab slug into a proper name: `law-as-data` → "Law as Data".
  #
  # @param slug [String]
  # @return [String]
  def self.titleize(slug)
    words = slug.to_s.split(/[-_\s.]+/).reject(&:empty?)
    return "" if words.empty?

    words.each_with_index.map { |word, i|
      lower = word.downcase
      if SPECIAL_CASE.key?(lower) then SPECIAL_CASE[lower]
      elsif ACRONYMS.include?(lower) then lower.upcase
      elsif i.positive? && SMALL_WORDS.include?(lower) then lower
      elsif lower.match?(/\A\d+\z/) then lower
      else lower.sub(/\A./, &:upcase)
      end
    }.join(" ")
  end

  # One `NNN.MM-<emoji>-<slug>` folder, decoded.
  #
  # @!attribute [r] ordinal
  #   @return [SpecPlanBuild::Ordinal]
  # @!attribute [r] status
  #   @return [SpecPlanBuild::Status]
  # @!attribute [r] slug
  #   @return [String]
  # @!attribute [r] dirname
  #   @return [String] exactly as it is on disk
  # @!attribute [r] path
  #   @return [String] absolute
  Feature = Data.define(:ordinal, :status, :slug, :dirname, :path) do
    include Comparable

    # Decode a folder name, or return nil when it is not a plan folder.
    #
    # @param path [String] absolute path to a candidate directory
    # @return [SpecPlanBuild::Feature, nil]
    def self.parse(path)
      dirname = File.basename(path)
      ordinal = Ordinal.from_dirname(dirname) or return nil

      rest = dirname.sub(/\A[\d.]+[-_]/, "")
      head, tail = rest.split(/[-_]/, 2)

      # A leading segment with no ASCII word character is the status emoji.
      status = (SpecPlanBuild.status_for_emoji(head) if tail && !head.to_s.empty? && !head.match?(/[A-Za-z0-9]/))
      slug = status ? tail : rest

      new(ordinal:, status: status || STATUS_BY_KEY.fetch(:new), slug:, dirname:, path:)
    end

    # @return [String] proper name, e.g. "Law as Data"
    def title = SpecPlanBuild.titleize(slug)

    # The folder name this feature would carry in a given state — the slug
    # never moves, and the number is always rendered canonically, so this is
    # also what repairs a folder written `018-⚪️-foo` before the `NNN.MM` rule.
    #
    # @param status [SpecPlanBuild::Status]
    # @return [String]
    def dirname_as(status) = "#{ordinal}-#{status.emoji}-#{slug}"

    # The number exactly as the folder writes it, which is not always the
    # canonical rendering: `018-⚪️-foo` yields "018" where {#ordinal} renders
    # "018.00".
    #
    # @return [String]
    def dirname_ordinal = dirname.to_s[/\A[\d.]+/].to_s

    # @return [Boolean] whether the number is written in full `NNN.MM` form
    def padded? = dirname_ordinal == ordinal.to_s

    # Whether the folder is already named the way this tool would name it —
    # number padded, emoji matching the state it claims, slug unchanged.
    #
    # @return [Boolean]
    def canonical? = dirname == dirname_as(status)

    # @param other [Object]
    # @return [Integer, nil]
    def <=>(other) = other.is_a?(self.class) ? [ordinal, dirname] <=> [other.ordinal, other.dirname] : nil
  end

  # A plan folder as the state machine sees it: which files exist, what they
  # say, and which pull requests they record.
  #
  # It exists because the invariants ask the same questions repeatedly and
  # {Feature} is a frozen `Data` with nowhere to memoize the answers.
  class Subject
    # @param feature [SpecPlanBuild::Feature]
    def initialize(feature)
      @feature = feature
      @reads = {}
    end

    # @return [SpecPlanBuild::Feature]
    attr_reader :feature

    # @return [SpecPlanBuild::Status] the status the folder name claims
    def status = feature.status

    # @param name [String] a bare filename
    # @return [Boolean]
    def file?(name) = File.file?(File.join(feature.path, name))

    # @param name [String]
    # @return [String, nil] contents, or nil when absent
    def read(name)
      @reads.fetch(name) do
        @reads[name] = file?(name) ? File.read(File.join(feature.path, name), encoding: "UTF-8") : nil
      end
    end

    # @return [Array<SpecPlanBuild::PullRequest>]
    def pull_requests = @pull_requests ||= PullRequests.new(dir: feature.path).all

    # The specification's own Goal section, verbatim and at most two
    # paragraphs. Anything that paraphrases the spec is a second copy that
    # drifts; quoting it is not — which is why the pull request body and the
    # index both read it from here rather than each writing their own.
    #
    # @return [Array<String>] paragraphs, empty when there is no Goal to read
    def goal
      body = read("spec.md").to_s
      section = body[/^\#{"#"}{2,3}\s*Goals?\b[^\n]*\n+(.*?)(?=\n\#{"#"}{1,3}\s|\z)/mi, 1]

      paragraphs(section) || paragraphs(body.sub(/\A\s*\#{"#"}[^\n]*\n/, "")) || []
    end

    # Specifications written before the template existed have no Goal section,
    # and they are exactly the ones an index most needs to describe. So the
    # opening prose stands in — skipping headings, quotes, lists and tables,
    # which describe the document rather than the work.
    #
    # @param text [String, nil]
    # @return [Array<String>, nil] nil when there is no prose to be had
    def paragraphs(text)
      found = text.to_s.strip.split(/\n{2,}/)
        .map(&:strip)
        .reject { |p| p.empty? || p.match?(/\A[\#>|\-*\d`_=]/) }
        .first(2)

      found.empty? ? nil : found
    end

    # The questions `blocked.md` still names, by number.
    #
    # Empty means one of two very different things, and a caller that treats
    # them alike is how a folder with thirty kilobytes of open questions gets
    # reported as "nothing left open": either there is no `blocked.md` at all,
    # or there is one whose questions are not written as `## B<n>` and are
    # therefore invisible to every part of this tool. Ask {#file?} which.
    #
    # @return [Array<Integer>]
    def open_blocks = SpecPlanBuild.block_numbers(read("blocked.md"), OPEN_BLOCK)

    # The answers waiting in `blocked.md`, by number. `## A1` settles `## B1`.
    #
    # Waiting, not folded: `lando-broker` decides whether one is really an
    # answer, and this only counts the headings.
    #
    # @return [Array<Integer>]
    def block_answers = SpecPlanBuild.block_numbers(read("blocked.md"), ANSWER_BLOCK)

    # A `blocked.md` this tool cannot read: the file is there, and not one
    # question in it is written as `## B<n>`. Nothing can drain it and nothing
    # currently says so, which is the whole reason this exists.
    #
    # @return [Boolean]
    def unreadable_block? = file?("blocked.md") && open_blocks.empty?

    # @return [String, nil] why the folder's name is not justified
    def violation = status.violation(self)

    # @return [Boolean] whether the name matches the contents
    def consistent? = violation.nil?

    # @return [SpecPlanBuild::StateMachine] positioned at the current state
    def machine = StateMachine.new(self)

    # @return [Array<Symbol>] states reachable right now, guards applied
    def allowed = machine.allowed

    # @return [SpecPlanBuild::Status, nil] the state these contents justify
    def best_fit = machine.best_fit

    # Move the folder into +status+ — the side effect a transition *is*.
    #
    # The {Feature} is a frozen `Data` holding the old name, so it is replaced
    # rather than mutated, and the memoized reads go with it.
    #
    # @param status [SpecPlanBuild::Status]
    # @return [SpecPlanBuild::Feature] the feature under its new name
    # @raise [SpecPlanBuild::Error] when the target name is already taken
    def rename_to(status)
      return @feature if status.key == @feature.status.key

      target = File.join(File.dirname(@feature.path), @feature.dirname_as(status))
      unless SpecPlanBuild.move_directory(@feature.path, target)
        raise Error, "cannot rename #{@feature.dirname} — #{File.basename(target)} already exists"
      end

      @reads = {}
      @pull_requests = nil
      @feature = Feature.parse(target) or raise Error, "#{File.basename(target)} is not a plan folder"
    end
  end
end
