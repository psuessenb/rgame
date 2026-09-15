# frozen_string_literal: true

require_relative '../lib/rgame/game'
require_relative '../lib/rgame/cli'
require_relative '../spec/support/api_docs'

# Lists every public class and method docs/api never names, as
# spec_core/api_docs/coverage_spec.rb asserts, and exits 1 if there are any.
# Run it to see the whole list rather than a failing example.
#
# Run it as `bundle exec rake docs:coverage`, never as `ruby tools/doc_coverage.rb`.
# Without the bundle, `require 'rgame/core_ext'` can resolve to an installed rgame
# gem's extension instead of this checkout's, and the report then describes that
# gem.
module DocCoverage
  module_function

  def report(out = $stdout)
    index = ApiDocs.constant_index(RGame)
    gaps = ApiDocs.undocumented(index)
    gaps.sort_by { it[:path] }.each do |gap|
      out.puts("#{gap[:path]}#{' (class never named)' unless gap[:class_named]}")
      gap[:methods].each { out.puts("  #{it}") }
    end
    modules = index.count { |_, value| value.is_a?(Module) }
    out.puts("\n#{gaps.size} of #{modules} modules and classes have undocumented names.")
    gaps
  end
end

exit(DocCoverage.report.empty?) if $PROGRAM_NAME == __FILE__
