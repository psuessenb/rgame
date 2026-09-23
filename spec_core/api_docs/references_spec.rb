# frozen_string_literal: true

require 'json'
require_relative '../../spec/support/api_docs'

# Every class, constant and method that docs/api/ names in prose exists.
#
# A page that names `Button#on_clicked` after the signal became `on_activated`
# reads perfectly well, and nothing else in either suite notices. So every
# backticked token shaped like a Ruby name (`UI::Menu#open`, `Controls.gamepad`,
# `KEY_A`) is resolved against the loaded engine.
#
# The documentation names all three layers, so the check needs all of them loaded,
# and neither suite may load them all: spec/ must never load Core and this suite
# must never load Engine. It therefore runs in a child process that requires
# `rgame/game` and `rgame/cli`, the entry points a game and the `rgame` command
# use. It lives here because that child needs the compiled Core extension.
#
# A name resolves when the engine, Ruby's core library, the documentation's own
# code blocks, examples/ or spec/support/ defines it, or when it is in `allowed`.
RSpec.describe 'docs/api references' do # rubocop:disable RSpec/DescribeClass -- the subject is the documentation, not a class
  # Backticked words shaped like constants that are not Ruby constants. Each says why.
  let(:allowed) do
    [
      'NAME',                       # the `rgame new NAME` argument
      'Gemfile',                    # a file name
      'TicTacToeGame',              # the class name `rgame new tic_tac_toe` generates
      'F1', 'F2', 'F3', 'Esc', 'WASD', # keys, named as a player sees them
      'RGAME_BUTTON_GAMEPAD_FIRST', # a C macro in ext/rgame_core/include/rgame/core.h
      'LANG', 'LANGUAGE', 'LC_ALL'  # environment variables SDL reads for the locale
    ]
  end

  let(:check) do
    <<~RUBY
      require 'rgame/game'
      require 'rgame/cli'
      require #{File.join(ApiDocs::ROOT, 'spec', 'support', 'api_docs').inspect}

      references = ApiDocs.pages.sort.flat_map { ApiDocs.references(it) }
      allowed = ApiDocs.example_constants + JSON.parse(ARGV.first)
      missing = ApiDocs.unresolved(references, ApiDocs.constant_index(RGame), allowed)
      puts JSON.generate(missing.map { "\#{it.location} \#{it.text}" })
    RUBY
  end

  it 'names nothing that does not exist' do
    output, errors, status = ChildRuby.capture(check, JSON.generate(allowed), chdir: ApiDocs::ROOT)

    expect(status).to be_success, errors
    expect(JSON.parse(output.lines.last)).to be_empty
  end
end
