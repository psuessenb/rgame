# frozen_string_literal: true

require 'json'
require 'open3'
require_relative '../../spec/support/api_docs'

# Every public class and method is named somewhere in docs/api/, or tagged
# `@api private` in the comment above it.
#
# A public method nobody documented is either something a game author has to
# find by reading the source, or machinery that should not have been public. This
# fails on both, which is what makes someone decide which. `rake docs:coverage`
# prints the whole list.
#
# Like the references spec beside it, this needs all three layers loaded, so it
# runs in a child process that requires `rgame/game` and `rgame/cli`.
RSpec.describe 'docs/api coverage' do # rubocop:disable RSpec/DescribeClass -- the subject is the documentation, not a class
  let(:check) do
    <<~RUBY
      require 'rgame/game'
      require 'rgame/cli'
      require #{File.join(ApiDocs::ROOT, 'spec', 'support', 'api_docs').inspect}

      gaps = ApiDocs.undocumented(ApiDocs.constant_index(RGame))
      puts JSON.generate(gaps.flat_map { |gap| (gap[:class_named] ? [] : [gap[:path]]) + gap[:methods].map { "\#{gap[:path]}#\#{it}" } })
    RUBY
  end

  it 'leaves no public name undocumented and untagged' do
    output, errors, status = Open3.capture3('ruby', '-I', File.join(ApiDocs::ROOT, 'lib'), '-e', check,
                                            chdir: ApiDocs::ROOT)

    expect(status).to be_success, errors
    expect(JSON.parse(output.lines.last)).to be_empty
  end
end
