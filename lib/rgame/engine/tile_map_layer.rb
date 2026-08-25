# frozen_string_literal: true

module RGame
  module Engine
    # One layer of the scene's tile map, drawn in world space, once per viewport.
    #
    #   world  = scene.add_node(WorldView.new)
    #   actors = TileMapLayer.mount(world)
    #   actors.add_node(player)
    #
    # A node per layer, and the layers Tiled lists are the layers you get. The
    # scene tree is then what says what covers what: everything mounted before
    # the actors draws under them, everything after draws over them, and the
    # gap `mount` leaves is where the actors go.
    #
    # It belongs **inside a WorldView**, which is the whole point of it existing
    # separately from Components::TileWorld. The map is world content: it
    # scrolls under a camera and every player sees their own part of it, so it
    # has to be drawn where the rest of the world is drawn rather than once for
    # the frame.
    #
    # It carries no state. The map id and the animation clock come from the
    # scene's TileWorld system, and the region worth drawing comes from the view.
    #
    # ## Why a node per layer, rather than two passes
    #
    # There used to be one of these, drawing a "below" band and an "above" band
    # in one go and relying on a global z to slot the actors between them. Draw
    # order is tree order now (see RGame::Util::Z), so a node's drawing is
    # contiguous and "between them" has to mean "between two nodes".
    #
    # That turned out to be the better shape anyway. A designer already orders
    # layers in Tiled and can see the result there; content can go between *any*
    # two of them rather than at one flagged boundary; and the `above` property
    # stops being something to remember on every layer — it is read once, by
    # `mount`, to decide where the gap goes.
    class TileMapLayer < Node2D
      # Mounts one node per layer of the scene's map under `parent`, and returns
      # an empty node sitting in the gap between them — what the scene hangs its
      # actors on. Nothing here picks a z by hand, and neither does the caller.
      #
      # `under` names the first layer that should cover the actors, as a layer
      # index. It defaults to the first layer the map flags `above` in Tiled, so
      # a map that already marks its canopies needs nothing said; a map that
      # marks none puts the actors on top of everything.
      #
      # `parent` must be inside a WorldView, like the nodes themselves.
      def self.mount(parent, under: nil)
        world = parent.system(Components::TileWorld)
        gap = under || world.first_above_layer

        world.layer_count.times do |index|
          # A layer at or past the gap sits above the actors; z is only ever
          # compared to a sibling's, so the +1 is a gap, not a magnitude.
          parent.add_node(new(layer: index, z: index < gap ? index : index + 1))
        end
        parent.add_node(Node2D.new(z: gap))
      end

      def initialize(layer:, **)
        super(**)
        @layer = layer
      end

      def on_add = @world = system(Components::TileWorld)

      # The view supplies the cull rect: which part of the world this viewport
      # can see. The map draws in world coordinates and the WorldView's
      # translate puts it on screen, so nothing here does camera arithmetic —
      # which is exactly what lets the same map serve every viewport.
      #
      # A screen-space view has no camera and nothing to cull against, so
      # there is nothing sensible to draw; that is a misplaced layer rather than
      # a state to handle, and it says so.
      def on_draw(renderer, view)
        camera = view.camera
        raise 'TileMapLayer must be inside a WorldView — this view has no camera' if camera.nil?

        renderer.tilemap(@world.tilemap_id, @layer, camera.x, camera.y,
                         view.width, view.height, elapsed: @world.elapsed)
      end
    end
  end
end
