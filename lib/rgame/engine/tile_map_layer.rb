# frozen_string_literal: true

module RGame
  module Engine
    # Draws the scene's tile map, in world space, once per viewport.
    #
    #   world = scene.add_node(WorldView.new)
    #   world.add_node(TileMapLayer.new)
    #
    # It belongs **inside a WorldView**, and that is the whole point of it
    # existing separately from TileWorld. The map is world content: it scrolls
    # under a camera and every player sees their own part of it, so it has to be
    # drawn where the rest of the world is drawn rather than once for the frame.
    #
    # It carries no state. The map id and the animation clock come from the
    # scene's TileWorld system, and the region worth drawing comes from the view
    # — so a scene mounts one and never touches it again.
    #
    # ## Two calls, because the actors go between them
    #
    # The below band (ground, same-level detail) draws at `TileWorld::GROUND_Z`
    # and the above band (canopies, roofs) at `TileWorld::CANOPY_Z`, with actors
    # at a z in between. The renderer sorts by z, so the order these are issued
    # in does not matter — but collapsing them into one call would put every
    # canopy behind every character.
    class TileMapLayer < Node2D
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

        id = @world.tilemap_id
        elapsed = @world.elapsed
        renderer.tilemap(id, camera.x, camera.y, view.width, view.height, elapsed: elapsed)
        renderer.tilemap_overlay(id, camera.x, camera.y, view.width, view.height,
                                 z: Components::TileWorld::CANOPY_Z, elapsed: elapsed)
      end
    end
  end
end
