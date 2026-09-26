# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Draws one tile of the scene's tile map with its bottom centre on its
      # node's origin, stretched to the node's width and height. That is a tile
      # object as Tiled draws it: a map's picture, placed as a node.
      #
      #   tree = Engine::Node2D.new(x: 184, y: 312, width: 16, height: 32)
      #   tree.add_component(Components::MapTile.new(tile: 399))
      #
      # `tile` is the map's own id for the tile, and `orientation` how it is
      # turned, as a MapObject gives both. The map id and the animation clock
      # come from the scene's TileWorld, found as the node enters the tree, so
      # an animated tile animates as it does in a layer and stops when the
      # world stops updating.
      #
      # It passes no angle: Node2D#draw has already pushed the node's rotation,
      # so the tile turns with its node. The node's elevation lifts it, as it
      # lifts a Sprite. It draws at the lowest `z` in its node's slot, under
      # everything else the node draws, whichever order the node's components
      # were added in.
      #
      # A node that never set a size is never culled (see Engine::Culling), and
      # draws its tile at no size. The tileset's drawing offset is left out of
      # the cull rect: it moves the tile a few pixels, and a tile is culled only
      # while its box is out of view.
      class MapTile < Engine::Component
        include Engine::Culling

        sealed_reader :tile, :orientation

        def initialize(tile:, orientation: TileMap::Orientation::IDENTITY)
          super()
          @rgame_tile = tile
          @rgame_orientation = orientation
        end

        def _attach = @rgame_world = node.system!(TileWorld)

        def _draw(renderer, view)
          width = node.width
          height = node.height
          left = Engine::Anchor.left(:bottom, width)
          top = Engine::Anchor.top(:bottom, height) - node.elevation
          return if culled?(view, node.world_x + left, node.world_y + top, width, height)

          renderer.map_tile(@rgame_world.tilemap_id, @rgame_tile, left, top, width, height, @rgame_orientation,
                            elapsed: @rgame_world.elapsed, z: Util::Z::Z_MIN)
        end
      end
    end
  end
end
