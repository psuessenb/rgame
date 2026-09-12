# frozen_string_literal: true

require 'open3'

# The engine and its documentation describe themselves without naming a game.
#
# The games under `test_projects/` are acceptance tests for wiring, not part of
# what the engine is. A class whose header says what it is *for* in one game's
# terms tells a reader less than the class does; a doc page that cites a test
# project as its worked example depends on something the gem does not ship. The
# examples under `examples/` exist to be cited, so that is where a reference
# goes instead.
#
# Nothing else would keep it that way. The obvious sentence to write while
# building something is "`test_projects/<game>` does exactly this", and it is
# written by someone who has that game open. So the rule is checked here, beside
# `packaging_spec.rb`, for the same reason that spec exists.
#
# **What is scanned is derived, not listed.** Every file git would track —
# committed or not yet, ignored files excepted — minus the exemptions below. A
# list of directories to scan is a list somebody forgets to extend. The game
# names are derived too, from `test_projects/` itself, so a new test project is
# covered the day it is added.
#
# What this deliberately does not attempt is vocabulary that only makes sense
# inside one game — a snake's fruit, a tower's range. Telling that apart from
# ordinary illustration ("a bullet", "a crate") takes reading, not a regex.
RSpec.describe 'references to games' do # rubocop:disable RSpec/DescribeClass -- the subject is the source tree, not a class
  let(:root) { File.expand_path('..', __dir__) }

  # Each exemption is a decision, and says why.
  let(:exempt) do
    Regexp.union(
      # Plans are working documents; any reference is fair game in one.
      %r{\Adocs/plans/},
      # The games themselves.
      %r{\Atest_projects/},
      # Their drive scripts, which belong to them by the path-mirror rule.
      %r{\Atools/drive/test_projects/},
      # History: a release's notes say what shipped in it, under the names it had.
      /\ACHANGELOG\.md\z/,
      # This file, which has to spell the names out to look for them.
      %r{\Aspec/game_references_spec\.rb\z}
    )
  end

  # `test_projects/` as a *directory* is the acceptance tier and may be named;
  # `test_projects/<game>` and the game's own name may not. `tower defense` is
  # the one game the engine was described in terms of that never had a directory.
  let(:game_names) do
    Dir.children(File.join(root, 'test_projects'))
       .select { |name| File.directory?(File.join(root, 'test_projects', name)) }
  end

  # A name only counts as a whole word: letters or digits on either side make it
  # part of something else. `snake_case` is the one ordinary word that starts with
  # a game's name followed by an underscore, and is stripped before matching.
  let(:pattern) do
    names = game_names.map { |name| "(?<![a-z0-9])#{Regexp.escape(name)}(?![a-z0-9])" }
    Regexp.new((names + ['tower[- ]defen[cs]e']).join('|'), Regexp::IGNORECASE)
  end

  let(:not_a_game) { /snake_cas\w*/i }

  def scanned_files
    listing, status = Open3.capture2('git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', chdir: root)
    raise 'this spec needs a git checkout to know which files are sources' unless status.success?

    listing.split("\0")
           .grep_v(exempt)
           .select { |path| File.file?(File.join(root, path)) }
  end

  def text(path)
    bytes = File.binread(File.join(root, path))
    bytes.include?("\0") ? nil : bytes.force_encoding(Encoding::UTF_8).scrub
  end

  it 'derives at least one game from test_projects/' do
    # Without this, an empty or renamed directory would make the scan below pass
    # by looking for nothing.
    expect(game_names).not_to be_empty
  end

  it 'finds no game named outside the exemptions' do
    offences = scanned_files.flat_map do |path|
      text(path).to_s.each_line.with_index(1).filter_map do |line, number|
        "#{path}:#{number}: #{line.strip}" if line.gsub(not_a_game, '').match?(pattern)
      end
    end

    expect(offences).to be_empty, "name an example or state the fact instead:\n#{offences.join("\n")}"
  end

  it 'recognises a game named in prose, in a path and as a phrase' do
    # The pattern is the whole guard, so it is checked against what it must catch
    # and what it must not, rather than trusted because the scan came back empty.
    game = game_names.first
    expect(["see #{game} for this", "test_projects/#{game}/main.rb", "#{game}_2p.rb", 'a tower-defense level'])
      .to all(match(pattern))
    expect(["un#{game}ed", 'use snake_case here'.gsub(not_a_game, '')]).not_to include(match(pattern))
  end
end
