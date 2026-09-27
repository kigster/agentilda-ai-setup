#!/usr/bin/env ruby
# frozen_string_literal: true

# Applies the ruby-cli-tools conventions to a gem `bundle gem` has just
# generated. Run from the gem's root; create-gem does this for you.
#
#   scaffold.rb --test rspec --linter rubocop [--ui]
#
# Templates live in ../assets/templates/<set>/. A path segment __PATH__
# becomes the gem's require path (acme/tool), __EXE__ the gem name. A file
# ending in .nest.erb is wrapped in the modules its path implies, so each
# template carries only the code that differs.

require "erb"
require "fileutils"
require "optparse"

module Scaffold
  TEMPLATES = File.expand_path("../assets/templates", __dir__)

  # Everything a template can refer to, derived from the generated gemspec.
  class Gem
    attr_reader :exe, :path, :namespace

    def initialize(root)
      gemspec = Dir[File.join(root, "*.gemspec")].first or abort("error: no *.gemspec in #{root}")
      @exe = File.basename(gemspec, ".gemspec")
      @path = @exe.tr("-", "/")
      @namespace = File.read(gemspec)[/spec\.version\s*=\s*([\w:]+)::VERSION/, 1] or
        abort("error: cannot find the root module in #{gemspec}")
    end

    # Acme::Tool => ["Acme", "Tool"]
    def modules = namespace.split("::")

    # The modules above the gem's own, which Zeitwerk needs defined up front.
    def parents = modules[0..-2]

    def basename = File.basename(path)

    # Bundler camelizes my_cli as MyCli; the conventions want MyCLI.
    def rename_cli! = @namespace = namespace.gsub(/Cli(?=[A-Z:]|\z)/, "CLI")

    def title = modules.last

    # Zeitwerk's names for the gem's own file and the cli/ directory.
    def inflections = {basename => title, "cli" => "CLI"}.inspect[1..-2]
  end

  class Renderer
    def initialize(gem, sets, test_framework)
      @gem = gem
      @sets = sets
      @test_framework = test_framework
    end

    def call
      @sets.each do |set|
        dir = File.join(TEMPLATES, set)
        Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).sort.each do |relative|
          source = File.join(dir, relative)
          next if File.directory?(source)

          write(target_for(relative), render(source, relative))
        end
      end
    end

    private

    attr_reader :gem, :test_framework

    def simplecov = File.read(File.join(TEMPLATES, "..", "simplecov.rb"))

    def target_for(relative)
      relative.sub(/(\.nest)?\.erb\z/, "").gsub("__PATH__", gem.path).gsub("__EXE__", gem.exe)
    end

    def render(source, relative)
      body = ERB.new(File.read(source), trim_mode: "-").result(binding)
      relative.end_with?(".nest.erb") ? nest(body, relative) : body
    end

    # Wraps a body in the modules implied by its path: lib/__PATH__/cli/demo.rb
    # sits in `module Acme; module Tool; module CLI`.
    def nest(body, relative)
      inner = File.dirname(relative).delete_prefix("lib/__PATH__").split("/").reject(&:empty?)
      "# frozen_string_literal: true\n\n#{wrap(gem.modules + inner.map { |dir| constant(dir) }, body)}"
    end

    # Nests a body in modules, indenting two spaces per level.
    def wrap(names, body)
      code = body.lines.map { |line| line.strip.empty? ? "\n" : ("  " * names.size) + line }.join
      opening = names.each_with_index.map { |name, depth| "#{"  " * depth}module #{name}\n" }.join
      closing = names.each_index.reverse_each.map { |depth| "#{"  " * depth}end\n" }.join
      opening + code + closing
    end

    def constant(dir) = (dir == "cli") ? "CLI" : dir.split("_").map(&:capitalize).join

    def write(target, content)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, content)
      FileUtils.chmod(0o755, target) if target.start_with?("exe/")
      puts "  scaffold  #{target}"
    end
  end

  module_function

  # Renames every MyCli to MyCLI in what bundler generated.
  def rename_namespace(from, to)
    return if from == to

    Dir.glob(["lib/**/*.rb", "spec/**/*.rb", "sig/**/*.rbs", "*.gemspec", "exe/*", "bin/console", "README.md"]).each do |file|
      text = File.read(file)
      File.write(file, text.gsub(/\b#{from}\b/, to)) if text.match?(/\b#{from}\b/)
    end
  end

  # Minitest and test-unit keep bundler's helper; coverage goes on top of it.
  def start_coverage(helper)
    return unless File.exist?(helper)

    text = File.read(helper)
    return if text.include?("SimpleCov.start")

    snippet = File.read(File.join(TEMPLATES, "..", "simplecov.rb"))
    File.write(helper, text.sub(/\A(# frozen_string_literal: true\n\n)?/) { "#{$1}#{snippet}\n" })
  end

  # Appends the lines the conventions ignore that bundler's .gitignore lacks.
  def merge_gitignore
    wanted = File.readlines(File.join(TEMPLATES, "..", "gitignore"), chomp: true).reject(&:empty?)
    present = File.exist?(".gitignore") ? File.readlines(".gitignore", chomp: true) : []
    missing = wanted - present
    File.open(".gitignore", "a") { |f| f.puts(missing) } unless missing.empty?
  end

  # A CLI's runtime dependencies belong in the gemspec, not the Gemfile.
  def add_runtime_dependencies(gemspec, deps)
    text = File.read(gemspec)
    lines = deps.map { |name, version| %(  spec.add_dependency "#{name}", "#{version}"\n) }
    lines.reject! { |line| text.include?(line.strip) }
    text.sub!(/^\s*# spec\.add_dependency.*\n/) { |example| example + lines.join } or text.sub!(/^end\s*\z/, "#{lines.join}end\n")
    text.sub!(/^(\s*(?:\w+\.)?)required_ruby_version\s*=\s*.*$/, '\1required_ruby_version = ">= 4.0"')
    File.write(gemspec, text)
  end
end

options = {test: "rspec", linter: "rubocop", ui: false}
OptionParser.new do |o|
  o.on("--test NAME") { |v| options[:test] = v }
  o.on("--linter NAME") { |v| options[:linter] = v }
  o.on("--ui") { options[:ui] = true }
end.parse!

gem = Scaffold::Gem.new(Dir.pwd)
sets = ["base"]
sets << "rspec" if options[:test] == "rspec"
sets << "rubocop" if options[:linter] == "rubocop"

if options[:ui]
  bundler_modules = gem.modules
  gem.rename_cli!
  bundler_modules.zip(gem.modules).each { |from, to| Scaffold.rename_namespace(from, to) }
  Scaffold.add_runtime_dependencies("#{gem.exe}.gemspec",
    "dry-cli" => "~> 1.4", "dry-cli-help" => "~> 0.5", "dry-cli-autocomplete" => "~> 0.5",
    "dry-cli-ui" => "~> 0.5", "zeitwerk" => "~> 2.8")
  sets << "ui"
  sets << "ui-rspec" if options[:test] == "rspec"
end

Scaffold::Renderer.new(gem, sets, options[:test]).call
Scaffold.start_coverage("test/test_helper.rb") unless options[:test] == "rspec"
Scaffold.merge_gitignore
