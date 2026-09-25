# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Makes one cell of the scene's tile map solid for as long as its node is in the
      # tree: a crate, a closed door, a statue.
      #
      #   crate.add_component(OccupiesCell.new(col: 12, row: 7))
      #
      # The cell is solid in the store TileWorld keeps, so a body declaring
      # `blocked_by: [:tiles]` stops at it, a route planned after it arrives goes round
      # it, and TileWorld#solid? says so, all from the moment the node enters the tree.
      # When the node leaves, or this component is removed, the cell is as the map made
      # it again.
      #
      # **The cell is counted, not flagged.** Two things occupying one cell keep it solid
      # until both have gone, and a cell the map already made solid stays solid when its
      # occupant leaves.
      #
      # **It does not place the node.** The cell is the thing that blocks, and where
      # the node draws is its own business: a node's origin may be its sprite's
      # top-left, and only its class knows. Put it on the cell with
      # TileWorld#cell_x and #cell_centre_x.
      #
      # **The cell is fixed.** Something that walks from cell to cell is a body, and a
      # mover declaring its layer in `blocked_by` already stops against it.
      class OccupiesCell < Engine::Component
        sealed_reader :col, :row

        def initialize(col:, row:)
          super()
          @rgame_col = col
          @rgame_row = row
          @rgame_world = nil
        end

        # Raises when the scene has no TileWorld, and ArgumentError when the cell is
        # outside the map, so a misplaced crate fails as it arrives rather than
        # blocking nothing.
        def _attach
          world = node.system(TileWorld) ||
                  raise("OccupiesCell makes a cell of the scene's TileWorld solid, and the " \
                        "scene has none. Mount one before adding a node that occupies (#{@rgame_col}, #{@rgame_row}).")
          world.occupy(@rgame_col, @rgame_row)
          @rgame_world = world
        end

        def _detach
          @rgame_world&.vacate(@rgame_col, @rgame_row)
          @rgame_world = nil
        end
      end
    end
  end
end
