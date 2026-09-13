# frozen_string_literal: true

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
      # It is handed this app's asset manager, so `audio.play_sound('hurt.ogg')`
      # resolves a path the same way `renderer.sprite('hero.json', …)` does.
      # Building the manager does not touch audio — its loaders are lambdas,
      # called at load time — so there is no cycle here despite the manager
      # reaching back through `app.audio` to make a sound.
      def audio = @audio ||= Audio.new(assets: assets)

      # Where #assets resolves relative paths from. Set once, as a keyword to
      # the constructor; there is deliberately no writer, because changing it
      # after an asset has loaded would leave a cache keyed against two roots.
      attr_reader :media_root
    end
  end
end
