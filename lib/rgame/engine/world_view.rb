# frozen_string_literal: true

module RGame
  module Engine
    # The node that marks where world space begins.
    #
    #   view = scene.add_node(WorldView.new)
    #   view.add_node(player)     # draws at its own world coordinates
    #
    # Its children live in **world** coordinates and are drawn once per active
    # viewport: for each one, clip to that viewport's rectangle and translate by
    # its camera, then run the same subtree again. Everything outside a
    # WorldView is screen space and draws once.
    #
    # That is the whole of split-screen, and it is why the transform and clip
    # stacks in Core are proper push/pop stacks — a clip always narrows, so a
    # child can never draw outside the region its parent allowed.
    #
    # ## The subtree does not know how many times it is drawn
    #
    # Children draw at their own absolute origin and never see a camera. This
    # node supplies the view, so the same world serves one player or four with
    # nothing below it changing — which is exactly what a camera owned by a node
    # *inside* the world could not do, and why cameras belong to players.
    #
    # Nothing here is per-player state: `update` and `control` still run once for
    # this subtree, however many viewports draw it. Only `draw` multiplies, which
    # makes the standing rule load-bearing — a `draw` with a side effect now
    # happens once per player, and an allocation in one costs that many times.
    class WorldView < Node2D
      # Drawn once per viewport, so this overrides the whole of `draw` rather
      # than just `draw_children`: the node's own visuals belong inside the
      # viewport too, not once outside all of them.
      #
      # `view` is the screen-space view this node was reached with, and is
      # deliberately ignored — a WorldView asks the system which viewports exist
      # rather than being told, so a game can place one anywhere in the tree.
      def draw(renderer, _view = nil)
        viewports = system(Viewports)
        viewports.views.each do |world_view|
          renderer.clipped(world_view.x, world_view.y, world_view.width, world_view.height) do
            renderer.translated(world_view.offset_x, world_view.offset_y) do
              super(renderer, world_view)
            end
          end
        end
      end
    end
  end
end
