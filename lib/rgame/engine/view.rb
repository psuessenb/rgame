# frozen_string_literal: true

module RGame
  module Engine
    # One viewport being drawn: a rectangle of the screen, and (for a world
    # view) the camera to look through it with.
    #
    #   view.x, view.y, view.width, view.height   # the screen rect
    #   view.camera                               # nil in a screen-space band
    #   view.player                               # whose view this is, or nil
    #   view.visible?(x, y, w, h)                 # is this worth drawing
    #
    # ## What a view is for
    #
    # `draw(renderer, view)` hands every node the view it is being drawn into,
    # which answers two questions nothing else can. **Where the edges are**: a
    # HUD laying itself out against the whole window is wrong the moment the
    # window is a player's half of one, and until this existed there was nothing
    # else to ask. And **what is worth drawing**: with the world drawn once per
    # player, culling stops being an optimisation and starts being the
    # difference between one frame's work and four.
    #
    # ## It is reused, not rebuilt
    #
    # Viewports owns one of these per viewport and mutates it in place each
    # frame, the way ActionMapper reuses its Actions. Building fresh ones would
    # allocate a handful of objects every frame — invisible by every measure
    # except the frame that stutters. **Hold the player or the viewports, never
    # this**: the object a node was handed last frame is the same one, with
    # different numbers in it.
    class View
      attr_reader :x, :y, :width, :height, :camera, :player

      def initialize(x: 0, y: 0, width: 0, height: 0, camera: nil, player: nil)
        set(x, y, width, height, camera: camera, player: player)
      end

      # Mutated in place by Viewports once per frame. Not for game code.
      def set(x, y, width, height, camera: nil, player: nil)
        @x = x
        @y = y
        @width = width
        @height = height
        @camera = camera
        @player = player
        self
      end

      # Where this view's contents start, in the space its nodes draw in: the
      # camera's offset for a world view, and the origin for a screen-space one,
      # whose nodes draw relative to the view's own corner.
      # hot-path
      def origin_x = @camera ? @camera.x : 0
      # hot-path
      def origin_y = @camera ? @camera.y : 0

      # Does a rectangle overlap what this view shows? Coordinates are in the
      # space the caller draws in — world coordinates under a camera, view-local
      # ones in a screen band — which is the same space `origin_x` is in.
      # hot-path
      def visible?(x, y, width, height)
        left = origin_x
        top = origin_y
        x + width > left && x < left + @width &&
          y + height > top && y < top + @height
      end

      # The offset to translate by so that content at `origin` lands at this
      # view's corner on screen. The whole of split-screen, in two numbers.
      # hot-path
      def offset_x = @x - origin_x
      # hot-path
      def offset_y = @y - origin_y
    end
  end
end
