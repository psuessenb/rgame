# frozen_string_literal: true

# RGame::Core::App is implemented in C — see ext/rgame_core/. It wraps the
# engine's public API (ext/rgame_core/include/rgame/core.h): an SDL window plus
# OpenGL context, and a fixed-timestep main loop that drives callbacks.
#
# App is meant to be subclassed. The engine calls back into methods on the
# object itself, so a game overrides the hooks it needs and inherits no-ops for
# the rest:
#
#   class MyGame < RGame::Core::App
#     def initialize = super(width: 800, height: 600, caption: 'my game')
#
#     def frame_begin; end     # once per frame, before that frame's ticks
#     def update(dt); end      # one fixed simulation tick; dt is always the
#                              # fixed step, never wall-clock frame time
#     def needs_redraw?; end   # false skips the draw (simulation still runs)
#     def draw; end            # render one frame
#     def button_down(id); end # discrete key press (no repeats)
#     def button_up(id); end
#     def resize(w, h); end
#   end
#
#   MyGame.new.run
#
# Also inherited: #close (stops the loop; safe from inside a callback), #width,
# #height, #caption, #caption=, #ticks_ms (monotonic ms since startup) and #fps.
#
# The loop owns the fixed-timestep accumulator, so #update is called once per
# whole tick and may run zero or several times per rendered frame. #frame_begin
# is the place to sample input once and reuse it across every tick of that
# frame.
#
# If a callback raises, the exception is carried out of #run with its original
# class, message and backtrace, and the loop shuts down cleanly first. A
# non-local exit (throw/break/return) out of a callback cannot be carried
# across the C loop and is reported as a RuntimeError instead — use #close to
# stop the loop.
#
# Loading this .so pulls SDL2 and OpenGL into the process — see
# lib/rgame/core.rb for why that's kept off the default `require "rgame"`.
# It loads from lib/rgame/core_ext.so, which the build (`make ext-core`)
# copies out of ext/rgame_core/.
require 'rgame/core_ext'

module RGame
  module Core
    # The two things a game needs one of, owned by the app that needs them and
    # built on first use.
    #
    # Lazily, and that is the point on both counts: an app that draws only
    # primitives builds no asset manager, and one that never plays a sound never
    # opens a device — which is also the right moment to open it, since asking
    # for a sound is the first thing that needs one.
    class App
      # This app's asset manager, rooted at the `media_root:` it was made with.
      #
      #   class MyGame < RGame::Core::App
      #     def initialize = super(width: 640, height: 480, caption: 'demo', media_root: MEDIA)
      #   end
      #
      #   app.assets.image('space.png')
      #
      # A game never constructs one. An `Image` belongs to one GL context and
      # has to be told which, so *something* has to hold the app — and since the
      # asset manager is the only thing in the engine that loads from a path,
      # that something is here, once, rather than threaded through every
      # constructor that ends up owning an image.
      def assets = @assets ||= AssetManager.new(root: @media_root, app: self)

      # This app's sound device. Not tied to the window in any way — audio has
      # no GL context and survives one being recreated — it lives here because
      # a game wants exactly one, the same way it wants one asset manager.
      def audio = @audio ||= Audio.new

      # Where #assets resolves relative paths from. Set once, as a keyword to
      # the constructor; there is deliberately no writer, because changing it
      # after an asset has loaded would leave a cache keyed against two roots.
      attr_reader :media_root
    end
  end
end
