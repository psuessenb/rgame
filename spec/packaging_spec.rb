# frozen_string_literal: true

# What the gem ships, checked rather than remembered.
#
# The failure this exists to prevent is the one nobody sees locally: a file that
# is missing from the packaged gem works perfectly in the checkout, because the
# checkout has it. It fails at `require` time, or at the first call that reads
# it, on someone else's machine — a new `.c` becomes an undefined symbol, a data
# file becomes a crash. So every rule about what must ship is asserted here
# instead of living in a checklist somebody has to consult.
#
# The expectations below re-derive what must ship from the directory tree. That
# is the point: rgame.gemspec derives its file list too, and if the two
# derivations disagree, one of them is wrong.

# RubyGems loads this lazily, and `rake spec` runs rspec in a bare ruby process
# where nothing else has pulled it in — Gem::SilentUI below would be an
# uninitialized constant without it.
require 'rubygems/user_interaction'

RSpec.describe 'rgame.gemspec' do # rubocop:disable RSpec/DescribeClass -- the subject is the packaged gem, not a class
  subject(:gemspec) { Gem::Specification.load(File.join(root, 'rgame.gemspec')) }

  let(:root) { File.expand_path('..', __dir__) }
  let(:files) { gemspec.files }

  # Build artifacts and generated files: present in a built checkout, never part
  # of the gem. Mirrors the pattern in rgame.gemspec, stated independently.
  let(:artifacts) { %r{\.(so|bundle|dylib|o|a|log)\z | \Aext/[^/]+/Makefile\z}x }

  # Files under the given globs, relative to the gem root, artifacts removed.
  def sources(*globs)
    Dir.glob(globs, base: root)
       .select { |path| File.file?(File.join(root, path)) }
       .grep_v(artifacts)
  end

  it 'is a valid gem specification' do
    # `validate` is what `gem build` runs: it catches a missing summary, a
    # malformed version, a homepage that is not a URI, and files listed but
    # absent. It reports through Gem.ui, which would otherwise scribble over the
    # spec output.
    expect { silence_gem_ui { gemspec.validate } }.not_to raise_error
  end

  it 'lists only files that exist' do
    missing = files.reject { |path| File.file?(File.join(root, path)) }

    expect(missing).to be_empty
  end

  describe 'the C extensions' do
    it 'declares every extconf.rb in the project' do
      # A third extension must be built by `gem install` the day it is added,
      # and nothing else in the tree would notice if it were not.
      expect(gemspec.extensions).to match_array(sources('ext/*/extconf.rb'))
    end

    it 'packages the extconf.rb files it declares' do
      expect(files).to include(*gemspec.extensions)
    end

    it 'packages every C source and header' do
      # mkmf compiles every .c in the extension directory, so a source missing
      # from the gem is not a build error — it is an undefined symbol raised the
      # first time the extension is required.
      expect(sources('ext/**/*.{c,h}') - files).to be_empty
    end

    it 'packages the vendored third-party sources and their licences' do
      expect(sources('ext/*/vendor/**/*') - files).to be_empty
    end

    it "packages rgame_util's colour header, which the core extension compiles against" do
      # ext/rgame_core/extconf.rb adds -I$(srcdir)/../rgame_util for this file.
      # Both extensions are unpacked as siblings, so the relative path holds —
      # but only if the header of the *other* extension is in the gem.
      expect(files).to include('ext/rgame_util/color.h')
    end
  end

  describe 'the Ruby layer' do
    it 'packages every .rb file under lib/, except the ones deliberately held back' do
      expect(sources('lib/**/*.rb').grep_v(%r{\Alib/platform/}) - files).to be_empty
    end

    it 'packages non-Ruby files under lib/ as well' do
      # This is the guard for runtime data, which is what lib/ holds besides
      # code: the default font, for one, is read at the first Font.new rather
      # than at load, so leaving it out of the gem fails late and remotely.
      # Anything dropped under lib/ is shipped by default — that is the design.
      #
      # There is no such file yet, so this passes vacuously today. It is written
      # now precisely because the moment one appears is the moment nobody is
      # thinking about packaging.
      data = sources('lib/**/*').grep_v(/\.rb\z/).grep_v(%r{\Alib/platform/})

      expect(data - files).to be_empty
    end

    it 'declares lib/ as the load path' do
      # Not `eq(['lib'])`: for a spec with extensions, RubyGems prepends the
      # directory the compiled objects are installed into, so the list has an
      # absolute path in front of 'lib'.
      expect(gemspec.require_paths).to include('lib')
    end

    it 'ships a version matching lib/rgame/version.rb' do
      expect(gemspec.version.to_s).to eq(RGame::VERSION)
    end
  end

  describe 'what must never ship' do
    it 'excludes compiled extensions and object files' do
      # lib/rgame/*.so is this machine's binary. Shipping it would shadow the
      # one `gem install` compiles for the machine the gem lands on.
      expect(files.grep(artifacts)).to be_empty
    end

    it 'excludes the test suites and the standalone binary sources' do
      expect(files.grep(%r{\A(spec|spec_core|test|src|rubocop)/})).to be_empty
    end

    it 'excludes the Gosu-backed platform layer' do
      # Kept in the checkout while the game still uses it, but it defines a
      # top-level `Platform` constant and subclasses Gosu::Window, and gosu is
      # not a dependency of this gem. When lib/platform/ goes, this expectation
      # and the exclusion in rgame.gemspec go with it.
      expect(files.grep(%r{\Alib/platform/})).to be_empty
    end

    it 'excludes plans, which describe work rather than the shipped code' do
      expect(files.grep(%r{\Adocs/plans/})).to be_empty
    end
  end

  describe 'the documentation it ships' do
    it 'packages the README and the licence' do
      expect(files).to include('README.md', 'LICENSE')
    end

    it 'packages the API reference' do
      expect(sources('docs/api/**/*') - files).to be_empty
    end
  end

  # `validate` reports through Gem.ui rather than raising for warnings, and the
  # default UI writes straight to stdout.
  def silence_gem_ui
    previous = Gem::DefaultUserInteraction.ui
    Gem::DefaultUserInteraction.ui = Gem::SilentUI.new
    yield
  ensure
    Gem::DefaultUserInteraction.ui = previous
  end
end
