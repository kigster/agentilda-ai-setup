# frozen_string_literal: true

module SpecPlanBuild
  # A git worktree per plan, so agents working on different plans cannot
  # collide at all.
  #
  # A lock coordinates a shared tree; a worktree removes the sharing. That
  # matters more than it sounds for an agent loop: two agents editing one
  # checkout produce no git conflict — same branch, same files — so the last
  # writer simply wins and the loser's work vanishes with nothing anywhere to
  # say it happened.
  #
  # The branch carries the plan number (`<user>/NNN.MM-slug`), which is not
  # decoration: it is the first thing `resync prs` reads when deciding which
  # plan a pull request implements. Naming branches this way means the number
  # carries itself from worktree creation through to a merged pull request with
  # nobody having to remember it.
  class Worktree
    # One plan's isolated checkout.
    #
    # @!attribute [r] ordinal
    #   @return [SpecPlanBuild::Ordinal]
    # @!attribute [r] branch
    #   @return [String]
    # @!attribute [r] path
    #   @return [String] absolute
    # @!attribute [r] created
    #   @return [Boolean] false when an existing worktree was reused
    Checkout = Data.define(:ordinal, :branch, :path, :created) do
      # @return [Boolean] whether the agent left anything behind
      def dirty? = !`git -C #{path.shellescape} status --porcelain 2>/dev/null`.strip.empty?

      # @return [String] the plans directory inside this checkout
      def plans_dir = File.join(path, SpecPlanBuild::PLANS_DIR)

      # @return [Boolean] whether this round made it, rather than reusing one
      def created? = created
    end

    # @param root [String] the main repository
    # @param dir [String, nil] where worktrees go; defaults to a sibling
    # @param user [String] branch namespace
    def initialize(root:, dir: nil, user: ENV["USER"] || "agent")
      @root = File.expand_path(root)
      @user = user
      @dir = File.expand_path(dir || default_dir)
    end

    # @return [String] the main repository
    attr_reader :root

    # @return [String] where worktrees are kept
    attr_reader :dir

    # @return [Boolean] whether root is a git repository at all
    def repository? = system("git", "-C", root, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)

    # Get, or create, the isolated checkout for one plan.
    #
    # @param feature [SpecPlanBuild::Feature]
    # @return [SpecPlanBuild::Worktree::Checkout]
    # @raise [SpecPlanBuild::Error] when git refuses
    def checkout_for(feature)
      branch = branch_for(feature)
      path = File.join(dir, "#{feature.ordinal}-#{feature.slug}")

      return Checkout.new(ordinal: feature.ordinal, branch:, path:, created: false) if File.directory?(path)

      # git keeps a registration for a worktree whose directory was deleted by
      # hand, marks it `prunable`, and then refuses to create a new one at that
      # path. Anybody who has ever `rm -rf`d a worktree meets this, and the
      # error says only "already exists" about a directory that does not.
      forget_stale

      FileUtils.mkdir_p(dir)
      add(branch, path)
      Checkout.new(ordinal: feature.ordinal, branch:, path:, created: true)
    end

    # @param feature [SpecPlanBuild::Feature]
    # @return [String] e.g. "kig/002.00-tenancy-households"
    def branch_for(feature) = "#{@user}/#{feature.ordinal}-#{feature.slug}"

    # Every worktree this class manages, as git sees them.
    #
    # @return [Array<String>] absolute paths
    def list
      # Compare canonical paths. git reports resolved ones, and on macOS the
      # temp and home trees run through symlinks (/var -> /private/var), so a
      # raw string compare matches nothing and prune silently does nothing.
      mine = canonical(dir)

      `git -C #{root.shellescape} worktree list --porcelain 2>/dev/null`
        .lines(chomp: true)
        .filter_map { |l| l.delete_prefix("worktree ") if l.start_with?("worktree ") }
        .select { |p| canonical(p).start_with?(mine) }
    end

    # @param path [String]
    # @return [String] the symlink-resolved path, or the input when it is gone
    def canonical(path)
      File.realpath(path)
    rescue Errno::ENOENT
      path
    end

    # Remove worktrees the agents left untouched.
    #
    # An agent that ran and changed nothing has produced a checkout that is
    # pure cost: it looks like work in progress and is not. Dirty ones are
    # always kept — that is the output.
    #
    # @return [Array<String>] paths removed
    def prune
      list.select { |path| clean?(path) }.each { |path| remove(path) }
    end

    # @param path [String]
    # @return [void]
    def remove(path)
      system("git", "-C", root, "worktree", "remove", "--force", path, out: File::NULL, err: File::NULL)
    end

    private

    # Sibling of the repository, not inside it: a worktree under the repo shows
    # up in its own `git status` and in every glob anybody writes.
    #
    # @return [String]
    def default_dir = "#{@root}.worktrees"

    # Drop registrations whose directory is gone.
    #
    # @return [void]
    def forget_stale
      system("git", "-C", root, "worktree", "prune", out: File::NULL, err: File::NULL)
    end

    # @param path [String]
    # @return [Boolean]
    def clean?(path) = `git -C #{path.shellescape} status --porcelain 2>/dev/null`.strip.empty?

    # @param branch [String]
    # @param path [String]
    # @return [void]
    def add(branch, path)
      exists = system("git", "-C", root, "show-ref", "--verify", "--quiet", "refs/heads/#{branch}")
      args = exists ? ["worktree", "add", path, branch] : ["worktree", "add", "-b", branch, path]

      return if system("git", "-C", root, *args, out: File::NULL, err: File::NULL)

      raise Error, "could not create a worktree for #{branch} at #{path}"
    end
  end
end
