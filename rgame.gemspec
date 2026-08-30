# frozen_string_literal: true

# rgame.gemspec — packages both halves of the project as one gem.
#
# The whole engine ships as a single gem containing two C extensions and the
# Ruby layer over them. That shape is why the C lives under `ext/` rather than a
# top-level `src/`: `gem install` unpacks the gem and runs each `extconf.rb`,
# and an extension can only build sources inside its own directory.
#
# `lib/rgame/version.rb` is required rather than `lib/rgame.rb`, because the
# latter loads the compiled `rgame/util_ext` — which does not exist yet at the
# moment a gemspec is evaluated.
require_relative 'lib/rgame/version'

Gem::Specification.new do |spec|
  spec.name = 'rgame'
  spec.version = RGame::VERSION
  spec.authors = ['Paul Süßenbach']
  spec.email = ['2452696+psuessenb@users.noreply.github.com']
  spec.license = 'MIT'
  spec.homepage = 'https://github.com/psuessenb/rgame'

  spec.summary = 'A 2D game engine in C on SDL2 and OpenGL, exposed to Ruby.'
  spec.description = <<~DESCRIPTION
    RGame is a small 2D game engine for Ruby, written in Ruby and C. It's build
    on top of SDL2, OpenGL and miniaudio. It's built with testability and
    performance in mind, and aims to be an engine where you can write your whole
    game code in Ruby, test it as usual with RSpec (or Minitest, or another test
    framework) and still have acceptable performance.

    While still a work in progress, RGame aims to be more than a SDL/OpenGL
    binding - it ships with high level features like a scene graph, sprites,
    collision systems, debugging tools and an UI toolkit.
  DESCRIPTION

  # No 'homepage_uri' here: spec.homepage above already supplies it, and
  # RubyGems warns when two metadata keys carry the same URI because it shows
  # only the first.
  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'documentation_uri' => "#{spec.homepage}/blob/main/docs/api/README.md",
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  # Only ever built and tested against the version in `.ruby-version`. Loosening
  # this is a matter of testing older rubies, not of changing code.
  spec.required_ruby_version = '>= 4.0'

  # Both extensions, in the order `make ext` builds them. RubyGems compiles each
  # one in place inside the unpacked gem, so they stay siblings under `ext/` —
  # which is what lets ext/rgame_core/extconf.rb reach `../rgame_util/color.h`
  # for the RGBA byte order. That header therefore has to be packaged even
  # though it belongs to the *other* extension; see PACKAGED below.
  spec.extensions = [
    'ext/rgame_util/extconf.rb',
    'ext/rgame_core/extconf.rb'
  ]

  spec.require_paths = ['lib']

  # The `rgame` command — `rgame new tictactoe` scaffolds a project. RubyGems
  # generates a wrapper on PATH for each name here, so this is what makes the
  # command exist after `gem install rgame`. Its project templates need no entry
  # of their own: they live under lib/ and the glob below takes them.
  spec.bindir = 'exe'
  spec.executables = ['rgame']

  # What ships, derived rather than listed.
  #
  # Two properties matter, and they pull in opposite directions.
  #
  # Everything the installed gem reads at runtime or compiles from must be in
  # here *without anyone remembering to add it*. A `.c` left out of the list is
  # an undefined symbol at `require` time; a data file left out — the default
  # font, once there is one — is a crash on the first call that needs it. Both
  # land on someone else's machine, long after the omission. So the rule is a
  # glob over whole directories, not an enumeration.
  #
  # And no build artifact may ship. `lib/rgame/*.so` is this machine's binary;
  # packaging it would shadow the one `gem install` compiles for the target.
  # That is what ARTIFACTS subtracts back out.
  #
  # A glob is used rather than `git ls-files` because a file that exists but is
  # not committed yet should still be caught by the guard below rather than
  # silently vanish from the gem, and because `git ls-files` cannot run when the
  # gem is rebuilt from an unpacked tarball.
  #
  # spec/packaging_spec.rb asserts both directions against the list this
  # produces. It is the guard; this comment is only the reasoning.
  # Note what `Dir.glob` does *not* match: a name beginning with a dot. That is
  # invisible here and harmless for everything above — but the CLI's project
  # templates live under lib/, and a template named `.gitignore` would silently
  # never ship. So none of them are dotfiles; they are stored under plain names
  # and renamed on the way out (RGame::CLI::NewProject::DOTFILES), and
  # spec/packaging_spec.rb fails if one ever appears.
  #
  # `examples/**/*` carries the single-concept examples *and their art*. They
  # ship because an example is documentation that runs, and one that lands
  # somewhere the reader cannot run it is just a listing. Shipping the art is
  # also what makes examples/assets/README.md's rule load-bearing rather than
  # tidy: the gem redistributes those files to everyone who installs it, so
  # nothing may go in there that is not CC0 or drawn in this repo.
  #
  # `test_projects/` and `tools/` deliberately stay out. They read from `media/`,
  # which cannot be redistributed at all — shipping them would put files in the
  # gem that only work on a machine which has assembled that directory by hand.
  packaged = %w[
    lib/**/*
    ext/**/*
    exe/**/*
    examples/**/*
    docs/api/**/*
    README.md
    CHANGELOG.md
    LICENSE
  ]

  artifacts = %r{
    \.(so|bundle|dylib|o|a|log)\z    # compiled output, and mkmf.log
    | \Aext/[^/]+/Makefile\z         # written by extconf.rb, not by us
    | \.dSYM/                        # macOS debug symbols — see below
  }x

  # Why .dSYM needs its own clause: on macOS a build leaves a *directory* named
  # `core_ext.bundle.dSYM` beside the extension, and the suffix rule above only
  # matches paths *ending* in `.bundle`. That catches the debug copy of the
  # binary inside it and misses its `Info.plist` and `.yml` relocation maps, so
  # without this clause a Mac-built checkout ships four debug-symbol files. The
  # rule has to match a path *component*, not a suffix, which is what the
  # trailing slash does.

  # `base:` keeps this independent of the working directory — `gem build` runs
  # here, but `rake build` and spec/packaging_spec.rb do not — and returns paths
  # already relative to the gem root, which is the form spec.files wants.
  root = __dir__

  spec.files = Dir.glob(packaged, base: root)
                  .select { |path| File.file?(File.join(root, path)) }
                  .grep_v(artifacts)
                  .sort
end
