# frozen_string_literal: true

require_relative '../lib/rgame/game'
require_relative '../lib/rgame/cli'
require_relative '../spec/support/api_docs'

module DocCoverage
  IGNORED_METHODS = %w[initialize inspect to_s hash == eql? <=> === to_h members keyword_init?].freeze

  module_function

  def docs_text = ApiDocs.pages.map { File.read(it) }.join("\n")

  # A setter counts as mentioned when the docs assign it (`x = 1` or `x=`).
  def mentioned?(text, name)
    return text.match?(/(?<![\w@])#{Regexp.escape(name.delete_suffix('='))}\s*=(?!=)/) if name.end_with?('=')

    text.match?(/(?<![\w@])#{Regexp.escape(name)}(?![\w?!=])/)
  end

  def public_methods_of(mod)
    instance = mod.is_a?(Class) ? mod.public_instance_methods(false) : []
    singleton = mod.singleton_methods(false)
    (instance + singleton).map(&:to_s).uniq.reject { IGNORED_METHODS.include?(it) || it.start_with?('_') }
  end

  def report(out = $stdout)
    text = docs_text
    modules = ApiDocs.constant_index(RGame).select { |_, value| value.is_a?(Module) }
    gaps = modules.filter_map do |path, mod|
      unmentioned_class = !mentioned?(text, path.split('::').last)
      methods = public_methods_of(mod).reject { mentioned?(text, it) }.sort
      [path, unmentioned_class, methods] if unmentioned_class || methods.any?
    end

    gaps.sort_by(&:first).each do |path, unmentioned_class, methods|
      out.puts("#{path}#{' (class never named)' if unmentioned_class}")
      methods.each { out.puts("  #{it}") }
    end
    out.puts("\n#{gaps.size} of #{modules.size} modules and classes have undocumented names.")
  end
end

DocCoverage.report if $PROGRAM_NAME == __FILE__
