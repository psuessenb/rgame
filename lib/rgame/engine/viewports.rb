# frozen_string_literal: true

module RGame
  module Engine
    # How the screen is divided, as a root-scoped system.
    #
    #   node.system(Viewports).views       # one View per active player
    #   node.system(Viewports).screen      # the whole window, no camera
    #   node.system(Viewports).solo!(cam)  # collapse to one view — cutscene
    #
    # It holds the mutable half of the question — which mode is current, who is
    # playing, how big the window is — while Layout holds the arithmetic. That
    # split is deliberate: the rect maths is pure and gets specced with no tree
    # and no window, and only the state that genuinely changes lives in a
    # component.
    #
    # It is a Component on the root, so any node reaches it by walking the tree
    # rather than having it threaded through a constructor — the same shape
    # CollisionWorld and Players use.
    #
    # ## Mode changes are deferred
    #
    # `solo!` and `split!` record a request; it is applied in `update`, which
    # runs in the root's component phase. That matters because this is reachable
    # from anywhere, including from a `draw` — and a `draw` now runs once per
    # view, so a mode change made there would fire several times and tear the
    # frame it was made in. Deferring is the same shape `queue_free` uses, and it
    # means a change takes effect on the next tick.
    class Viewports < Component
      # `views` is the list drawn through this frame — one per active player
      # while split, exactly one while solo. Reused, like the Views in it.
      attr_reader :screen, :width, :height, :views

      def initialize(players, width: 0, height: 0)
        super()
        @players = players
        @width = width
        @height = height
        @solo_camera = nil
        @pending = nil
        # One View per possible player for the world, one more each for their own
        # screen space, and one for the whole window. Built once and mutated in
        # place. See View: these are reused, never rebuilt.
        @pool = []
        @screen_pool = []
        @views = []
        @screen = View.new
        refresh
      end

      # The window changed size. Rects are recomputed from it on the next
      # refresh, and every camera reclamps against its new rect — which is why
      # a camera does not carry one.
      def resize(width, height)
        @width = width
        @height = height
        refresh
      end

      def solo? = !@solo_camera.nil?

      # The screen-space region belonging to `player`: the same rectangle their
      # world view is drawn into, with **no camera**, so its contents are laid
      # out against their own corner rather than the window's. Their HUD and
      # their menus live here.
      #
      # `nil` when they have no region to draw into, which is two cases and one
      # answer. An **empty seat** has no viewport at all. And while the split is
      # **collapsed**, nobody has a half of the screen to own: a cutscene is
      # everyone looking at one thing, so per-player UI has no place to be, and
      # a game wanting something on screen through it draws in the global
      # overlay band instead.
      #
      # Returning nil rather than an empty rectangle is deliberate: one check at
      # the one caller that needs it beats every caller relying on a zero-sized
      # clip happening to draw nothing.
      def screen_for(player)
        return nil if player.nil? || @solo_camera

        world = @views.find { |view| view.player.equal?(player) }
        return nil if world.nil?

        pooled_screen(@players.list.index(player))
          .set(world.x, world.y, world.width, world.height, player: player)
      end

      # Collapse to a single screen-wide view through `camera`.
      #
      # The camera is **required**: promoting one player's would silently give
      # everyone else their view, and deciding what is on screen is what a
      # cutscene is for. A game points an ordinary Camera wherever it likes —
      # with a CameraFollow on a cutscene actor, or its own component framing
      # every player at once — and hands it here.
      def solo!(camera)
        raise ArgumentError, 'solo! needs a camera to look through' if camera.nil?

        @pending = camera
        self
      end

      # Back to one view per player.
      def split! = @pending = :split

      # Applies a pending mode change, then rebuilds the rects. Runs in the
      # root's component phase, so a change requested during a tick lands on the
      # next one.
      def update(_dt)
        apply_pending
        refresh
      end

      # Recompute every rect from the current mode and window, and reclamp each
      # camera against the rect it is about to be drawn into.
      #
      # Allocation-free once the pool has grown: Layout yields its rects rather
      # than building them, and the Views are mutated in place.
      def refresh
        @screen.set(0, 0, @width, @height)
        @solo_camera ? refresh_solo : refresh_split
        @views.each { |view| view.camera&.resolve(view.width, view.height) }
        self
      end

      private

      def apply_pending
        return if @pending.nil?

        @solo_camera = @pending == :split ? nil : @pending
        @pending = nil
      end

      def refresh_solo
        @views.clear
        @views << pooled(0).set(0, 0, @width, @height, camera: @solo_camera)
      end

      def refresh_split
        @views.clear
        count = @players.active_count
        return if count.zero?

        index = 0
        Layout.each_rect(count, @width, @height) do |i, x, y, w, h|
          player = active_at(i)
          @views << pooled(index).set(x, y, w, h, camera: player.camera, player: player)
          index += 1
        end
      end

      # `each_active` is a filter, so it cannot be indexed without building an
      # Array. Walking it costs nothing and this runs once per frame.
      def active_at(index)
        found = nil
        i = 0
        @players.each do |player|
          next unless player.active?

          found = player if i == index
          i += 1
        end
        found
      end

      def pooled(index)
        @pool[index] ||= View.new
      end

      def pooled_screen(index)
        @screen_pool[index] ||= View.new
      end
    end
  end
end
