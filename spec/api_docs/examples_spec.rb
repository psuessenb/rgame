# frozen_string_literal: true

require 'open3'
require 'prism'

# The code examples in docs/api/ run against the current code.
#
# An example that stopped matching the code is invisible to every other spec: the
# code is fine, and a reader copies the example and gets a NameError or a wrong
# number. So the blocks are classified by their first line and checked here:
#
# - A block starting with `require 'rgame'` is a complete headless example. It runs
#   in its own process from the repository root, and each `expression # => value`
#   line is checked against what the expression returns.
# - A block that requires `rgame/core` or `rgame/game` opens a window or a game
#   loop, so it is parsed rather than run. A syntax error still fails.
# - Every other block is a fragment and is not checked here; the names its page
#   mentions are resolved by spec_core/api_docs/references_spec.rb.
#
# A complete example that cannot run as it stands, such as an RSpec file, opts out
# with `<!-- doc-example: skip — reason -->` on the line before its fence.
RSpec.describe 'docs/api code examples' do # rubocop:disable RSpec/DescribeClass -- the subject is the documentation, not a class
  blocks = ApiDocs.pages.sort.flat_map { ApiDocs.blocks(it) }

  describe 'headless examples' do
    blocks.select(&:headless?).each do |block|
      it "#{block.location} runs and returns what its comments say" do
        output, status = Open3.capture2e('ruby', '-I', File.join(ApiDocs::ROOT, 'lib'), '-e',
                                         ApiDocs.instrument(block), chdir: ApiDocs::ROOT)

        expect(status).to be_success, "#{block.location} failed:\n#{output}"
      end
    end
  end

  describe 'windowed examples' do
    blocks.select(&:windowed?).each do |block|
      it "#{block.location} parses" do
        errors = Prism.parse(block.source).errors.map do |error|
          "line #{block.line + error.location.start_line - 1}: #{error.message}"
        end

        expect(errors).to be_empty
      end
    end
  end

  it 'finds headless examples to run' do
    expect(ApiDocs.pages.flat_map { ApiDocs.blocks(it) }.count(&:headless?)).to be_positive
  end
end
