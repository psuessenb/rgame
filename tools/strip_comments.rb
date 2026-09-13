#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'prism'

# Deletes the explanatory comments from Ruby source, keeping only the ones that
# carry meaning beyond the code itself:
#
#   - magic comments (`# frozen_string_literal: true`) and the shebang
#   - directives: `# rubocop:disable/enable/todo` (with every comment line that
#     continues its `-- reason`) and the engine's `# hot-path` tag
#   - the description directly above a `class`, a `module`, or a constant that
#     builds one (`Point = Data.define(:x, :y)`)
#   - the description directly above a public method: a `def`, an `attr_*`,
#     a `define_method`, an alias, or a declaration like `signal :on_hit` in a
#     class body, when it is public at that point
#   - the comment directly above a `class_eval`-style call; comments *inside* its
#     heredoc are string content and never touched
#
# "Directly above" means an unbroken run of comment lines ending on the line
# before; one blank line detaches it. Everything else goes, trailing comments
# included. Comments are found by Prism rather than by pattern, so a `#` inside
# a string, a heredoc or a regexp is never mistaken for one.
#
# Files under any `examples/`, `spec/` or `spec_core/` directory are left alone.
#
#   tools/strip_comments.rb FILE...      rewrite the given files in place
#   tools/strip_comments.rb --check ...  list the files that would change
#   tools/strip_comments.rb --staged     strip staged files; the pre-commit hook
class CommentStripper
  EXCLUDED_DIRECTORIES = %w[examples spec spec_core].freeze

  DIRECTIVE = /\A#\s*(?:rubocop:(?:disable|enable|todo)\b|hot-path\b)/
  DIRECTIVE_WITH_REASON = /\A#\s*rubocop:\w+\s.*\s--(?:\s|\z)/
  CLOSER = /\A(?:end\b|[}\])]|else\b|elsif\b|when\b|in\b|rescue\b|ensure\b)/
  KEYWORD_OPENER = /\A(?:else|rescue|ensure)\b/

  # Collects the lines a comment block may sit directly above and survive:
  # namespaces, public method definitions and dynamic-eval calls. It also
  # collects the lines that open a body, which the blank-line cleanup needs.
  class Anchors < Prism::Visitor
    VISIBILITIES = %i[public protected private].freeze
    METHOD_DEFINERS = %i[attr_reader attr_writer attr_accessor attr define_method alias_method].freeze
    EVALS = %i[class_eval module_eval instance_eval class_exec module_exec instance_exec].freeze
    CLASS_BUILDERS = %i[Class Module Struct Data].freeze
    NOT_DSL = %i[module_function private_constant public_constant undef_method remove_method].freeze

    Scope = Struct.new(:visibility, :namespace, :instance_lines, :singleton_lines)

    attr_reader :lines, :openers

    def initialize
      super
      @lines = Set.new
      @openers = Set.new
      @forced = {}.compare_by_identity
      @namespace_blocks = {}.compare_by_identity
      @scopes = [new_scope(:private)]
    end

    def visit_program_node(node)
      super
      settle(@scopes.first)
    end

    def visit_class_node(node)
      @lines << node.location.start_line
      @openers << (node.superclass || node.constant_path).location.end_line
      in_scope(namespace: true) { super }
    end

    def visit_module_node(node)
      @lines << node.location.start_line
      @openers << node.constant_path.location.end_line
      in_scope(namespace: true) { super }
    end

    def visit_singleton_class_node(node)
      @openers << node.expression.location.end_line
      in_scope(namespace: true) { super }
    end

    def visit_block_node(node)
      @openers << (node.parameters&.location || node.opening_loc).end_line
      in_scope(namespace: @namespace_blocks.key?(node)) { super }
    end

    def visit_lambda_node(node)
      @openers << (node.parameters&.location || node.opening_loc).end_line
      in_scope { super }
    end

    def visit_begin_node(node)
      @openers << node.begin_keyword_loc.start_line if node.begin_keyword_loc
      super
    end

    def visit_def_node(node)
      unless node.equal_loc
        header_end = node.rparen_loc || node.parameters&.location || node.name_loc
        @openers << header_end.end_line
      end
      register(node.name, node.location.start_line, singleton: !node.receiver.nil?, node:)
      in_scope { super }
    end

    def visit_alias_method_node(node)
      if node.new_name.is_a?(Prism::SymbolNode)
        register(node.new_name.unescaped.to_sym, node.location.start_line, node:)
      end
      super
    end

    def visit_constant_write_node(node)
      @lines << node.location.start_line if class_builder?(node.value)
      super
    end

    def visit_constant_path_write_node(node)
      @lines << node.location.start_line if class_builder?(node.value)
      super
    end

    def visit_call_node(node)
      @lines << node.location.start_line if EVALS.include?(node.name)
      @namespace_blocks[node.block] = true if node.block && class_builder?(node)
      handle_receiverless_call(node) if node.receiver.nil?
      super
    end

    private

    def new_scope(visibility, namespace: false)
      Scope.new(visibility, namespace, Hash.new { |h, k| h[k] = [] }, Hash.new { |h, k| h[k] = [] })
    end

    def in_scope(namespace: false)
      @scopes.push(new_scope(:public, namespace:))
      yield
      settle(@scopes.pop)
    end

    def settle(scope)
      scope.instance_lines.each_value { |lines| @lines.merge(lines) }
      scope.singleton_lines.each_value { |lines| @lines.merge(lines) }
    end

    def handle_receiverless_call(node)
      arguments = node.arguments&.arguments || []

      if VISIBILITIES.include?(node.name)
        change_visibility(node.name, arguments)
      elsif node.name == :module_function && arguments.empty?
        @scopes.last.visibility = :public
      elsif node.name == :private_class_method
        arguments.each { force_or_retract(it, :private, singleton: true) }
      elsif METHOD_DEFINERS.include?(node.name)
        defined_names(node.name, arguments).each { register(it, node.location.start_line, node:) }
      elsif dsl_declaration?(node, arguments)
        register(arguments.first.unescaped.to_sym, node.location.start_line, node:)
      end
    end

    def dsl_declaration?(node, arguments)
      @scopes.last.namespace && arguments.first.is_a?(Prism::SymbolNode) && !NOT_DSL.include?(node.name)
    end

    def change_visibility(visibility, arguments)
      return @scopes.last.visibility = visibility if arguments.empty?

      arguments.each { force_or_retract(it, visibility, singleton: false) }
    end

    def force_or_retract(argument, visibility, singleton:)
      case argument
      when Prism::DefNode, Prism::CallNode
        @forced[argument] = visibility
      when Prism::SymbolNode, Prism::StringNode
        name = argument.unescaped.to_sym
        scope = @scopes.last
        (singleton ? scope.singleton_lines : scope.instance_lines).delete(name) unless visibility == :public
      end
    end

    def defined_names(method_name, arguments)
      symbols = arguments.select { it.is_a?(Prism::SymbolNode) || it.is_a?(Prism::StringNode) }
      names = symbols.map { it.unescaped.to_sym }
      return names.take(1) if %i[define_method alias_method].include?(method_name)
      return names.flat_map { [it, :"#{it}="] } if method_name == :attr_accessor
      return names.map { :"#{it}=" } if method_name == :attr_writer

      names
    end

    def register(name, line, node:, singleton: false)
      scope = @scopes.last
      visibility = singleton ? :public : (@forced[node] || scope.visibility)
      return unless visibility == :public

      (singleton ? scope.singleton_lines : scope.instance_lines)[name] << line
    end

    def class_builder?(value)
      return false unless value.is_a?(Prism::CallNode)
      return true if value.name == :define

      receiver = value.receiver
      value.name == :new && receiver.is_a?(Prism::ConstantReadNode) && CLASS_BUILDERS.include?(receiver.name)
    end
  end

  class ParseError < StandardError; end

  # Returns +source+ with its explanatory comments removed.
  # Raises ParseError rather than guess at a file Prism cannot parse.
  def self.strip(source) = new(source).strip

  # True for a path whose comments are all kept.
  def self.excluded?(path) = path.split('/').intersect?(EXCLUDED_DIRECTORIES)

  def initialize(source)
    @source = source
    @lines = source.lines
    @result = Prism.parse(source)
  end

  def strip
    raise ParseError, @result.errors.map(&:message).join('; ') if @result.failure?

    @anchors = Anchors.new
    @result.value.accept(@anchors)
    @magic_offsets = @result.magic_comments.map { it.key_loc.start_offset }

    dropped = Set.new
    cuts = {}
    whole_line, trailing = @result.comments.partition { whole_line?(it) }

    blocks(whole_line).each { |block| drop_from_block(block, dropped) }
    trailing.each do |comment|
      cuts[comment.location.start_line - 1] = comment.location.start_column unless keep_alone?(comment)
    end

    assemble(dropped, cuts)
  end

  private

  def whole_line?(comment)
    return true if comment.is_a?(Prism::EmbDocComment)

    line = @lines[comment.location.start_line - 1]
    line.byteslice(0, comment.location.start_column).strip.empty?
  end

  def last_line(comment)
    return comment.location.end_line unless comment.is_a?(Prism::EmbDocComment)

    @source.byteslice(0, comment.location.end_offset - 1).count("\n") + 1
  end

  def blocks(comments)
    comments.sort_by { it.location.start_line }.slice_when { |a, b| b.location.start_line != last_line(a) + 1 }
  end

  def drop_from_block(block, dropped)
    attached = @anchors.lines.include?(last_line(block.last) + 1)
    continuing_reason = false

    block.each do |comment|
      text = comment.slice
      if text.match?(DIRECTIVE)
        continuing_reason = text.match?(DIRECTIVE_WITH_REASON)
        next
      end
      next if attached || continuing_reason || keep_alone?(comment)

      dropped.merge((comment.location.start_line - 1)..(last_line(comment) - 1))
    end
  end

  def keep_alone?(comment)
    location = comment.location
    return true if location.start_line == 1 && comment.slice.start_with?('#!')
    return true if comment.slice.match?(DIRECTIVE)

    @magic_offsets.any? { location.start_offset <= it && it < location.end_offset }
  end

  def assemble(dropped, cuts)
    output = []
    gaps = []

    @lines.each_with_index do |line, index|
      if dropped.include?(index)
        gaps << output.size unless gaps.last == output.size
        next
      end

      line = cut(line, cuts[index]) if cuts.key?(index)
      output << [index + 1, line]
    end

    gaps.reverse_each { |gap| tidy_blank_lines(output, gap) }
    output.map(&:last).join
  end

  def cut(line, column)
    newline = line.end_with?("\n") ? "\n" : ''
    "#{line.byteslice(0, column).rstrip}#{newline}"
  end

  def tidy_blank_lines(output, gap)
    before = gap.positive? ? output[gap - 1] : nil
    after = output[gap]

    if blank?(after) && (before.nil? || blank?(before) || opener?(before))
      output.delete_at(gap)
    elsif blank?(before) && (after.nil? || after.last.strip.match?(CLOSER))
      output.delete_at(gap - 1)
    end
  end

  def blank?(entry) = entry && entry.last.strip.empty?

  def opener?(entry)
    number, text = entry
    @anchors.openers.include?(number) || text.strip.match?(KEYWORD_OPENER) || text.rstrip.match?(/[(\[{|]\z/)
  end
end

# Runs the stripper over files named on the command line, or over the index.
module StripComments
  RUBY_NAMES = %w[Rakefile Gemfile].freeze
  RUBY_EXTENSIONS = %w[.rb .rake .gemspec].freeze

  module_function

  def run(argv)
    return staged if argv == ['--staged']

    check = argv.delete('--check')
    changed = argv.select { |path| ruby?(path, File.binread(path)) }.filter_map do |path|
      rewrite(path, check:)
    end
    check && changed.any? ? 1 : 0
  end

  # Returns the path when the file changed (or would, under --check), else nil.
  def rewrite(path, check:)
    original = read_utf8(File.binread(path))
    stripped = strip_or_warn(path, original)
    return if stripped.nil? || stripped == original

    puts path
    File.binwrite(path, stripped) unless check
    path
  end

  # Strips the staged version of each staged Ruby file and puts the result back
  # into the index. The working tree copy is rewritten too, but only when it
  # matches what was staged — otherwise it holds unstaged work that must survive.
  def staged
    staged_paths.each do |path|
      original = read_utf8(git('show', ":#{path}"))
      next unless ruby?(path, original)

      stripped = strip_or_warn(path, original)
      next if stripped.nil? || stripped == original

      update_index(path, stripped)
      if File.exist?(path) && read_utf8(File.binread(path)) == original
        File.binwrite(path, stripped)
      else
        warn "strip_comments: #{path} has unstaged changes; stripped only the staged copy"
      end
    end
    0
  end

  def staged_paths
    git('diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z').split("\0")
  end

  def update_index(path, content)
    mode = git('ls-files', '--stage', '--', path).split.first
    blob = git('hash-object', '-w', '--stdin', '--path', path, stdin: content).strip
    git('update-index', '--cacheinfo', "#{mode},#{blob},#{path}")
  end

  def ruby?(path, content)
    return false if CommentStripper.excluded?(path)
    return true if RUBY_NAMES.include?(File.basename(path)) || RUBY_EXTENSIONS.include?(File.extname(path))

    File.extname(path).empty? && content.start_with?('#!') && content.lines.first.include?('ruby')
  end

  def strip_or_warn(path, source)
    CommentStripper.strip(source)
  rescue CommentStripper::ParseError => e
    warn "strip_comments: skipped #{path}, it does not parse: #{e.message}"
    nil
  end

  def read_utf8(bytes) = bytes.dup.force_encoding(Encoding::UTF_8)

  def git(*args, stdin: nil)
    output, status = Open3.capture2('git', *args, stdin_data: stdin, binmode: true)
    raise "git #{args.first} failed" unless status.success?

    output
  end
end

exit StripComments.run(ARGV) if $PROGRAM_NAME == __FILE__
