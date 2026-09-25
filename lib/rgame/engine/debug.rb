# frozen_string_literal: true

module RGame
  module Engine
    # The development layer, as a switch per channel.
    #
    #   debug = node.system(Engine::Debug)
    #   debug.shows?(:shapes)
    #   debug.show(:shapes); debug.hide(:shapes); debug.toggle(:stats)
    #   debug.define(:routes) { |renderer, view| ... }
    #
    # RGame::Game mounts one on the root, beside `Players`, `Viewports` and
    # `Facts`, so anything in the tree reaches it. It holds a flag per channel
    # and draws in the `:debug` band, over every other thing in the frame.
    #
    # ## Two channels ship, and a game adds its own
    #
    # **`:stats`** is the RGame::Engine::DebugOverlay: frames per second, the
    # objects allocated in all and over the last second, and the longest the
    # collector ran in one tick of that second.
    # **`:shapes`** is drawn by the things that have shapes — a collider draws
    # its own box or circle, and a WorldView draws the solid cells of the
    # scene's tile map. Nothing here knows about either; they ask `shows?`.
    #
    # `define` adds a channel of a game's own, drawn by the block it is given
    # once per frame while the channel is on. `:stats` and `:shapes` are the
    # engine's and cannot be redefined.
    #
    # A channel is off until something switches it on, and an unknown name
    # raises `KeyError` rather than staying quietly dark — a misspelt channel
    # that never draws looks exactly like one that is off, and that is a long
    # afternoon.
    #
    # ## Who switches them
    #
    # `RGame::Game` binds F1 to `:stats` and F3 to `:shapes`, and
    # `game.debug_keys = false` turns those keys off — F2's quit included — for
    # a build a player runs. Anything else switches a channel by calling it,
    # which is what a game does to reach one from a scripted run: the input
    # backend a harness drives answers polled input and never reaches
    # `Game#button_down`, so a project that wants its shapes driven binds an
    # action of its own and toggles from a node.
    class Debug < Component
      ENGINE_CHANNELS = %i[stats shapes].freeze

      def initialize
        super
        @rgame_flags = { stats: false, shapes: false }
        @rgame_blocks = {}
        @rgame_shown = []
        @rgame_overlay = DebugOverlay.new
        @rgame_fps = 0
      end

      # The frame rate the `:stats` channel reports, measured by the shell that
      # owns the loop and handed down — nothing here reads a clock. RGame::Game
      # sets it once per frame.
      #
      # @api private
      sealed_writer :fps

      # Is this channel drawing? Raises `KeyError` for a channel nobody
      # declared. This runs once per drawable per frame, so it allocates
      # nothing.
      # hot-path
      def shows?(name) = @rgame_flags.fetch(name) { unknown(name) }

      def show(name) = switch(name, true)
      def hide(name) = switch(name, false)
      def toggle(name) = switch(name, !shows?(name))

      # A channel of the game's own, drawn by `block` once per frame while it is
      # on. The block is handed the renderer and the view the root is drawn
      # into, and draws in the `:debug` band without asking for it.
      #
      #   debug.define(:routes) { |renderer, _view| navigator.path.each { ... } }
      #
      # The channel starts off, like every other. Defining one twice replaces
      # the block and leaves the flag as it was, so a scene entered again may
      # define its channels again.
      def define(name, &block)
        if ENGINE_CHANNELS.include?(name)
          raise ArgumentError, "#{name.inspect} is drawn by the engine and cannot be redefined"
        end
        raise ArgumentError, "a channel is drawn by a block, and #{name.inspect} was given none" if block.nil?

        @rgame_flags[name] = false unless @rgame_flags.key?(name)
        @rgame_blocks[name] = block
        refresh_shown
        name
      end

      # Every channel's name, the two the engine draws first and the game's own
      # in the order they were defined.
      def channels = @rgame_flags.keys

      def _update(dt)
        @rgame_overlay.update(dt) if @rgame_flags[:stats]
      end

      def _draw(renderer, view)
        @rgame_overlay.draw(renderer, view, @rgame_fps) if @rgame_flags[:stats]
        @rgame_shown.each { |block| renderer.layered(:debug) { block.call(renderer, view) } }
      end

      private

      def switch(name, on)
        was = shows?(name)
        @rgame_flags[name] = on
        @rgame_overlay.restart if name == :stats && on && !was
        refresh_shown
        on
      end

      def refresh_shown
        @rgame_shown = @rgame_blocks.filter_map { |name, block| block if @rgame_flags[name] }
      end

      def unknown(name)
        raise KeyError.new("no debug channel #{name.inspect}; the channels are " \
                           "#{channels.map(&:inspect).join(', ')}. Add one with define",
                           receiver: self, key: name)
      end
    end
  end
end
