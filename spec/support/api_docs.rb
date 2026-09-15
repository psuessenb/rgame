# frozen_string_literal: true

# Reads the reference documentation under docs/api/ as data: its code blocks, the
# names its prose puts in backticks, its links, and the public names it never
# mentions.
#
# It names no RGame class. The specs in spec/api_docs/ use it in the headless
# process, spec_core/api_docs/ hands it a fully loaded `RGame` in a child process,
# and tools/doc_coverage.rb prints its coverage gaps. See the write-docs skill for the
# conventions it checks.
module ApiDocs
  ROOT = File.expand_path('../..', __dir__)
  DIR = File.join(ROOT, 'docs', 'api')

  WINDOWED = %r{^\s*require 'rgame/(?:core|game)'}

  # A fenced block: its language, source, the page line its first source line is
  # on, and whether a `<!-- doc-example: skip -->` comment precedes it.
  Block = Struct.new(:page, :lang, :source, :line, :skip, keyword_init: true) do
    def first_code_line = source.lines.map(&:strip).find { |l| !l.empty? && !l.start_with?('#') }

    # A complete example that needs a window or the wired game: parsed, not run.
    def windowed? = !skip && lang == 'ruby' && first_code_line&.start_with?("require 'rgame") && source.match?(WINDOWED)

    # A complete headless example: runs as it stands with only `require 'rgame'`.
    def headless? = !skip && lang == 'ruby' && first_code_line == "require 'rgame'" && !source.match?(WINDOWED)

    def location = "#{File.basename(page)}:#{line}"
  end

  # A backticked token in prose, and where it is.
  Reference = Struct.new(:page, :line, :text) do
    def location = "#{File.basename(page)}:#{line}"
  end

  SKIP_MARKER = /<!--\s*doc-example:\s*skip\b/
  FENCE = /\A```(\w*)\s*\z/

  module_function

  def pages = Dir[File.join(DIR, '*.md')]

  def blocks(page)
    result = []
    lines = File.readlines(page, chomp: true)
    index = 0
    while index < lines.size
      match = FENCE.match(lines[index])
      if match && !match[1].empty?
        start = index
        index += 1
        index += 1 until index >= lines.size || lines[index].start_with?('```')
        skip = start.positive? && lines[start - 1].match?(SKIP_MARKER)
        result << Block.new(page: page, lang: match[1], source: "#{lines[(start + 1)...index].join("\n")}\n",
                            line: start + 2, skip: skip)
      elsif match
        index += 1
        index += 1 until index >= lines.size || lines[index].start_with?('```')
      end
      index += 1
    end
    result
  end

  def prose_lines(page)
    inside = false
    File.readlines(page, chomp: true).each_with_index.filter_map do |text, index|
      if text.start_with?('```')
        inside = !inside
        next
      end
      [text, index + 1] unless inside
    end
  end

  def references(page)
    prose_lines(page).flat_map do |text, line|
      text.scan(/`([^`]+)`/).flatten.map { Reference.new(page, line, it) }
    end
  end

  # `[text](target)` links that point at a file, relative to docs/api.
  def links(page)
    prose_lines(page).flat_map do |text, line|
      text.scan(/\]\(([^)\s]+)\)/).flatten.grep_v(%r{\A[a-z]+://}).map { [line, it] }
    end
  end

  # GitHub's heading anchors: lowercased, punctuation dropped, spaces to dashes.
  def anchors(page)
    prose_lines(page).filter_map { |text, _| text[/\A#+\s+(.*)/, 1] }
                     .map { it.strip.downcase.gsub(/[^\p{Alnum} _-]/u, '').tr(' ', '-') }
  end

  CONSTANT_DEFINITION = /^\s*(?:class|module)\s+([A-Z]\w*)|^\s*([A-Z]\w*)\s*=[^=]/

  # Constants that prose may name without the engine defining them: those the
  # documentation's own code blocks define (`class Hero`), and those defined by
  # the programs under examples/ and the stand-ins under spec/support/.
  def example_constants
    sources = pages.flat_map { blocks(it) }.map(&:source)
    sources += Dir[File.join(ROOT, '{examples,spec/support}', '**', '*.rb')].map { File.read(it) }
    sources.flat_map { it.scan(CONSTANT_DEFINITION).flatten.compact }.uniq
  end

  # Rewrites every `expression # => value` line of a headless example into a check
  # that reports a mismatch on stderr and exits non-zero at the end. The value is
  # the text up to ` — `; a value starting with `#<` is compared with `inspect`,
  # and a value naming a class passes for an instance of it.
  def instrument(block)
    body = block.source.lines.each_with_index.map do |text, offset|
      match = text.match(/\A(\s*)(\S.*?)\s+# => (.+?)\s*\z/)
      next text unless match && !match[2].start_with?('#')

      expected = match[3].split(' — ').first.strip
      "#{match[1]}__doc_expect(#{block.line + offset}, (#{match[2]}), #{expected.inspect})\n"
    end.join
    "#{EXPECT_HELPER}\n#{body}\nexit(1) if $doc_example_failed\n"
  end

  EXPECT_HELPER = <<~'RUBY'
    def __doc_expect(line, actual, expected_source)
      if expected_source.start_with?('#<')
        ok = actual.inspect == expected_source
      else
        expected = TOPLEVEL_BINDING.eval(expected_source)
        ok = expected.is_a?(Module) && !actual.is_a?(Module) ? actual.is_a?(expected) : actual == expected
      end
    rescue Exception => e # rubocop:disable Lint/RescueException
      ok = false
      expected_source = "#{expected_source} (does not evaluate: #{e.class})"
    ensure
      unless ok
        warn "line #{line}: expected #{expected_source}, got #{actual.inspect}"
        $doc_example_failed = true
      end
    end
  RUBY

  # Every module and constant reachable under `root` (an already loaded `RGame`),
  # as `{ 'RGame::Engine::Node2D' => object }`.
  def constant_index(root)
    index = {}
    seen = {}.compare_by_identity
    walk = lambda do |mod, path|
      return if seen[mod]

      seen[mod] = true
      index[path] = mod
      mod.constants(false).each do |name|
        next if mod.autoload?(name)

        value = mod.const_get(name, false)
        child = "#{path}::#{name}"
        value.is_a?(Module) && value.name&.start_with?(root.name) ? walk.call(value, child) : index[child] ||= value
      end
    end
    walk.call(root, root.name)
    index
  end

  # A backticked token that looks like a Ruby name: `Node2D`, `UI::Menu#open`,
  # `Controls.gamepad(slot)`, `KEY_A`. Everything else (code, prose, paths) is nil.
  def name_token(text)
    token = text.sub(/\(.*\z/m, '').strip
    token[/\A((?:[A-Z]\w*::)*[A-Z]\w*)(?:([#.])([a-z_]\w*[?!=]?))?\z/] ? token : nil
  end

  # The name tokens in `references` that resolve against no constant in
  # `index`, no Ruby core constant, no constant an example defines and none in
  # `allowed`, or whose method part is not defined on any constant that matches.
  def unresolved(references, index, allowed)
    references.filter_map do |ref|
      token = name_token(ref.text)
      next unless token

      constant, separator, method = token.match(/\A([^#.]+)(?:([#.])(.+))?\z/).captures
      next if allowed.include?(constant.split('::').first)

      candidates = index.select { |path, _| path == constant || path.end_with?("::#{constant}") }.values
      core = constant.split('::').inject(Object) { |mod, name| mod.const_get(name, false) } rescue nil # rubocop:disable Style/RescueModifier
      candidates << core if core
      next ref if candidates.empty?
      next if separator.nil?

      ok = candidates.any? do |candidate|
        if separator == '.'
          candidate.respond_to?(method, true) || (method == 'new' && candidate.is_a?(Class))
        else
          candidate.is_a?(Module) && (candidate.method_defined?(method) || candidate.private_method_defined?(method))
        end
      end
      ok ? nil : ref
    end
  end

  IGNORED_METHODS = %w[initialize inspect to_s hash == eql? <=> === to_h members keyword_init?].freeze
  INTERNAL_TAG = /\A\s*#\s*@api private\b/

  # A public class or method no page names, and why: `{ path:, class_named:, methods: }`
  # for each module in `index` with a gap.
  #
  # Public is not always meant for a game. A method one engine class calls on
  # another has to be public in Ruby, so a class or method whose comment carries
  # `@api private` is left out, and so is everything inside such a class.
  def undocumented(index)
    text = pages.map { File.read(it) }.join("\n")
    index.values.grep(Module).uniq.filter_map do |mod|
      path = mod.name
      next if internal_constant?(index, path)

      methods = public_methods_of(mod).reject { mentioned?(text, it) || internal_method?(mod, it) }.sort
      class_named = mentioned?(text, path.split('::').last)
      { path: path, class_named: class_named, methods: methods } unless class_named && methods.empty?
    end
  end

  # A setter counts as mentioned when its reader is: a page says "`vx` and `spin`
  # are read/write" far more often than it shows an assignment.
  def mentioned?(text, name)
    name = name.delete_suffix('=') if name.match?(/\A(?:\w+|\[\])=\z/)
    text.match?(/(?<![\w@])#{Regexp.escape(name)}(?![\w?!])/)
  end

  def public_methods_of(mod)
    instance = mod.is_a?(Class) ? mod.public_instance_methods(false) : []
    names = (instance + mod.singleton_methods(false)).map(&:to_s).uniq
    names.reject { IGNORED_METHODS.include?(it) || it.start_with?('_') }
  end

  # The constant, or any module it is nested in, is tagged internal.
  def internal_constant?(index, path)
    segments = path.split('::')
    (2..segments.size).any? do |length|
      parent = index[segments.first(length - 1).join('::')]
      parent.is_a?(Module) && tagged?(parent.const_source_location(segments[length - 1], false))
    end
  end

  def internal_method?(mod, name)
    method = mod.singleton_methods(false).include?(name.to_sym) ? mod.method(name) : mod.instance_method(name)
    tagged?(method.source_location)
  end

  # Whether the comment block directly above `file:line` has an `@api private` line.
  def tagged?(location)
    file, line = location
    return false unless file && line&.positive? && File.file?(file)

    lines = File.readlines(file, chomp: true)
    lines.first(line - 1).reverse.take_while { it.match?(/\A\s*#/) }.any? { it.match?(INTERNAL_TAG) }
  end
end
