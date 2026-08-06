# frozen_string_literal: true

# The property this whole suite rests on, made executable.
#
# `spec/` exists to cover the halves of the engine that need no window, and the
# only thing making that true is that `require "rgame"` pulls in no graphics
# library. Break it — a stray `require "rgame/core"` in `lib/rgame.rb`, or a
# transitive one through `RGame::Engine` — and this suite quietly starts needing
# a display, on a machine where one happens to be available. Then it fails in
# CI, or on someone else's laptop, for reasons that have nothing to do with the
# change that caused it.
#
# It has been checked by hand as a shell one-liner since the split was
# introduced. `spec_helper.rb` requires exactly what that line requires, so the
# check belongs here instead.
#
# **To check that this file still discriminates**, preload Core into one rspec
# process rather than editing an example:
#
#   rspec -Ilib -rrgame/core spec/rgame/no_graphics_spec.rb   # two of three fail
#
# Editing an example to require Core instead would load SDL for every other
# example in the run — RSpec loads one root into one process, which is the very
# property this file protects. So the obvious way to test it is the wrong one.
#
# See CLAUDE.md, "The Core / Util split".
RSpec.describe 'require "rgame"' do # rubocop:disable RSpec/DescribeClass -- the subject is what one require loads
  # The libraries the Core extension links. Matching `libGL.` with the dot on
  # purpose: `libGLdispatch` and `libGLX` get pulled in by unrelated things on
  # some systems, and a guard that cries wolf is a guard someone deletes.
  #
  # A method rather than a constant, which would leak onto Object for the whole
  # run.
  def graphics_libraries = /libSDL2|libGL\./

  # Linux only. macOS and Windows have equivalents (`vmmap`, `EnumProcessModules`)
  # and neither is worth a native call here — the property is the same
  # everywhere, and one platform checking it is enough to catch a regression.
  def mapped_libraries
    File.read('/proc/self/maps').scan(graphics_libraries).uniq
  end

  before { skip 'needs /proc/self/maps' unless File.exist?('/proc/self/maps') }

  it 'loads no SDL and no OpenGL into the process' do
    # spec_helper has already done the require; if anything in this suite pulled
    # graphics in, it is mapped by now.
    expect(mapped_libraries).to be_empty
  end

  it 'leaves RGame::Core undefined' do
    # The same guarantee seen from Ruby rather than from the OS, and the one
    # that makes the engine layer's rule enforce itself: a node reaching for
    # `RGame::Core` — or, now that the layer is nested, a bare `Core` — raises
    # NameError here rather than quietly working. `Game/NoCoreInEngineLayer`
    # covers the branches a run never reaches; this covers the rest.
    # The one place in spec/ that may name the constant, because asserting its
    # absence is the entire point — see the cop's own doc for why everything
    # else is forbidden from doing so.
    # rubocop:disable Game/NoCoreInEngineLayer -- naming it is what is being tested
    expect(defined?(RGame::Core)).to be_nil
    # rubocop:enable Game/NoCoreInEngineLayer
  end

  it 'does load the two halves that need no window' do
    # Stated positively so the file says what `require "rgame"` *is*, not only
    # what it is not.
    expect(defined?(RGame::Util)).to eq('constant')
    expect(defined?(RGame::Engine)).to eq('constant')
  end
end
