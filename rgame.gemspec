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
  spec.email = ['paul.suessenbach@googlemail.com']
  spec.license = 'MIT'
  spec.homepage = 'https://github.com/psuessenb/rgame'

  spec.summary = 'A 2D game engine in C on SDL2 and OpenGL, exposed to Ruby.'
  spec.description = <<~DESCRIPTION
    rgame is a 2D game engine written in C on top of SDL2 and OpenGL and exposed
    to Ruby as C extensions. It opens a window, runs a fixed-timestep main loop,
    reads keyboard and controllers, loads PNGs onto the GPU and draws shapes and
    sprites through a z-sorted batching renderer.

    Everything Ruby-visible lives under the RGame module, split in two by what it
    depends on. RGame::Core owns the window, the GPU and the OS handles;
    RGame::Util holds the shareable value types and links no graphics libraries
    at all, so `require "rgame"` gives you the pure half with no SDL or OpenGL in
    the process and pure-logic code stays testable with no display.
  DESCRIPTION

  # No 'homepage_uri' here: spec.homepage above already supplies it, and
  # RubyGems warns when two metadata keys carry the same URI because it shows
  # only the first.
  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'documentation_uri' => "#{spec.homepage}/blob/main/docs/api/README.md",
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
  packaged = %w[
    lib/**/*
    ext/**/*
    docs/api/**/*
    README.md
    LICENSE
  ]

  artifacts = %r{
    \.(so|bundle|dylib|o|a|log)\z    # compiled output, and mkmf.log
    | \Aext/[^/]+/Makefile\z         # written by extconf.rb, not by us
  }x

  # The engine layer, held back for now.
  #
  # It depends on no graphics library at all — `lib/engine/` names none — but
  # it still lives at the top level as `Engine::` rather than under
  # `RGame::Engine`, so shipping it would put a bare `Engine` constant into
  # every consumer's process. It comes *in* when it moves, which is what
  # docs/plans/engine-replacement/ is for; delete this and the matching
  # expectation in spec/packaging_spec.rb together at that point.
  not_shipped = %r{\Alib/(engine/|engine\.rb\z|boot\.rb\z)}

  # `base:` keeps this independent of the working directory — `gem build` runs
  # here, but `rake build` and spec/packaging_spec.rb do not — and returns paths
  # already relative to the gem root, which is the form spec.files wants.
  root = __dir__

  spec.files = Dir.glob(packaged, base: root)
                  .select { |path| File.file?(File.join(root, path)) }
                  .grep_v(artifacts)
                  .grep_v(not_shipped)
                  .sort
end
