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
require 'tempfile'

RSpec.describe 'rgame.gemspec' do # rubocop:disable RSpec/DescribeClass -- the subject is the packaged gem, not a class
  subject(:gemspec) { Gem::Specification.load(File.join(root, 'rgame.gemspec')) }

  let(:root) { File.expand_path('..', __dir__) }
  let(:files) { gemspec.files }

  # Build artifacts and generated files: present in a built checkout, never part
  # of the gem. Mirrors the pattern in rgame.gemspec, stated independently.
  let(:artifacts) do
    %r{\.(so|bundle|dylib|o|a|log)\z | \Aext/[^/]+/Makefile\z | \.dSYM/}x
  end

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
      expect(sources('lib/**/*.rb') - files).to be_empty
    end

    it 'packages non-Ruby files under lib/ as well' do
      # This is the guard for runtime data, which is what lib/ holds besides
      # code: the default font, for one, is read at the first Font.new rather
      # than at load, so leaving it out of the gem fails late and remotely.
      # Anything dropped under lib/ is shipped by default — that is the design.
      #
      # It stopped passing vacuously when the default font arrived: the two
      # files under lib/rgame/fonts/ are what it holds up today.
      data = sources('lib/**/*').grep_v(/\.rb\z/)

      expect(data - files).to be_empty
    end

    it 'packages the engine layer' do
      # It was held out of the gem for as long as it was a bare top-level
      # `Engine` constant. Now that it is `RGame::Engine` under
      # `lib/rgame/engine/`, nothing about it is special: it is Ruby under
      # `lib/`, so the glob takes it. Stated anyway, because it is what the
      # exclusion used to say and its absence would otherwise be silent.
      expect(files).to include('lib/rgame/engine.rb', 'lib/rgame/engine/node2d.rb')
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

  describe 'the rgame command' do
    it 'ships the executable and declares it' do
      # RubyGems puts a wrapper on PATH for each name in `executables`, looked
      # up under `bindir`. Shipping the file without declaring it means no
      # command; declaring it without shipping it fails `validate` above.
      expect(gemspec.bindir).to eq('exe')
      expect(gemspec.executables).to eq(['rgame'])
      expect(files).to include('exe/rgame')
    end

    it 'ships the executable with its executable bit set' do
      # RubyGems records the mode of the file as packaged. A wrapper that shells
      # out to a non-executable script is a permission error at the user's first
      # `rgame new`, on their machine and not ours.
      skip 'this filesystem does not record a POSIX executable bit' unless executable_bit_recorded?

      expect(File).to be_executable(File.join(root, 'exe/rgame'))
    end

    it 'packages every project template' do
      # A template missing from the gem is not a load error — it is `rgame new`
      # writing an incomplete project, and only on a machine that installed the
      # gem rather than checking it out.
      expect(sources('lib/rgame/cli/templates/**/*') - files).to be_empty
    end

    # Stated without going through `sources`, for the reason the .dSYM example
    # below gives: both the gemspec and this file derive their lists with
    # `Dir.glob`, and `Dir.glob` does not match a leading dot. A template named
    # `.gitignore` would therefore be absent from the gem *and* invisible to the
    # example above, which is the exact shape of hole that let macOS debug
    # symbols ship. Templates are stored under plain names and renamed on the
    # way out — see RGame::CLI::NewProject::DOTFILES.
    it 'has no dotfile among the templates, which the packaging glob would skip' do
      dotfiles = Dir.glob('lib/rgame/cli/templates/**/*', File::FNM_DOTMATCH, base: root)
                    .grep(%r{(\A|/)\.[^/.]})

      expect(dotfiles).to be_empty
    end
  end

  describe 'the examples' do
    it 'packages every example, including its assets' do
      # An example is documentation that runs, so it ships — and a missing asset
      # is not a load error but an example that crashes at its first draw, on a
      # machine that installed the gem rather than checking it out. Same shape as
      # the project templates above, same reason.
      expect(sources('examples/**/*') - files).to be_empty
    end

    # Stated without going through `sources`, exactly as the template dotfile
    # example is, and for the same reason: both the gemspec and `sources` derive
    # their lists with `Dir.glob`, which does not match a leading dot, so a check
    # that shares the blind spot it is guarding is not a guard. `examples/` is a
    # shipped directory now, so it inherits the rule.
    it 'has no dotfile among the examples, which the packaging glob would skip' do
      dotfiles = Dir.glob('examples/**/*', File::FNM_DOTMATCH, base: root)
                    .grep(%r{(\A|/)\.[^/.]})

      expect(dotfiles).to be_empty
    end

    it 'ships the asset provenance record' do
      # examples/assets/ ships, so the gem redistributes third-party art to
      # everyone who installs it. The README is where each file's source and
      # licence is recorded; shipping the art without it would distribute the
      # files and leave the provenance behind.
      expect(files).to include('examples/assets/README.md')
    end
  end

  describe 'what must never ship' do
    it 'excludes compiled extensions and object files' do
      # lib/rgame/*.so is this machine's binary. Shipping it would shadow the
      # one `gem install` compiles for the machine the gem lands on.
      expect(files.grep(artifacts)).to be_empty
    end

    # Stated without reference to `artifacts` on purpose. Both this spec and the
    # gemspec filter with their own copy of that pattern, so the "two
    # derivations agree" check above is blind to anything *both* copies miss —
    # and that is exactly how macOS debug symbols went unnoticed. A .dSYM is a
    # directory named `core_ext.bundle.dSYM`, so a rule matching paths that
    # *end* in `.bundle` skips the `Info.plist` and relocation `.yml` inside it.
    # Naming the directory directly is what makes the guard independent of the
    # pattern that had the hole.
    it 'excludes macOS debug symbol bundles' do
      expect(files.grep(/dSYM/)).to be_empty
    end

    it 'excludes the test suites and the standalone binary sources' do
      expect(files.grep(%r{\A(spec|spec_core|test|src|rubocop)/})).to be_empty
    end

    it 'excludes plans, which describe work rather than the shipped code' do
      expect(files.grep(%r{\Adocs/plans/})).to be_empty
    end

    it 'excludes the test projects and the drive harness' do
      # Unlike examples/, these read from media/, whose contents cannot be
      # redistributed — so shipping them would put files in the gem that work
      # only on a machine which has assembled that directory by hand. This is
      # the guard against reading the two project trees as interchangeable and
      # widening the examples glob to cover both.
      expect(files.grep(%r{\A(test_projects|tools)/})).to be_empty
    end
  end

  describe 'the documentation it ships' do
    it 'packages the README, the changelog and the licence' do
      expect(files).to include('README.md', 'CHANGELOG.md', 'LICENSE')
    end

    it 'packages the API reference' do
      expect(sources('docs/api/**/*') - files).to be_empty
    end
  end

  # Whether this filesystem records a POSIX executable bit at all.
  #
  # Probed by chmod-ing a real file rather than asked of the platform, which is
  # the same rule the Core suite follows for Xvfb and virtual gamepads: a probe
  # keeps the example running on every machine that can manage it, instead of
  # switching it off for a whole platform.
  #
  # It comes back false on Windows, where there are no mode bits to carry and
  # `File.executable?` answers from PATHEXT — an extensionless script is never
  # "executable" there, and a git checkout has nothing to carry the bit in
  # either. Nothing is lost by skipping: RubyGems installs a `.bat` wrapper on
  # Windows rather than running the file directly, and the gems that reach
  # RubyGems are built on a POSIX machine, where this example does run.
  def executable_bit_recorded?
    Tempfile.create('rgame-exec-probe') do |file|
      file.close
      File.chmod(0o755, file.path)
      File.executable?(file.path)
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
