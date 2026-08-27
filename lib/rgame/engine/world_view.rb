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
    # Children draw in their own local space and never see a camera. This node
    # supplies the view — one clip and one translate around the whole subtree —
    # so the same world serves one player or four with nothing below it changing,
    # which is exactly what a camera owned by a node *inside* the world could not
    # do, and why cameras belong to players.
    #
    # ## Only `draw` multiplies, and deliberately
    #
    # `control` and `update` still run **once** for this subtree, however many
    # viewports draw it. That is what keeps simulation cost independent of player
    # count, and it is also a safety property: a world node's `on_update` is
    # where mutation belongs, so per-view updating would move an actor at twice
    # the speed with two players — correctly in single player, silently wrong the
    # moment somebody joins.
    #
    # It does make the standing "draw renders state" rule load-bearing rather
    # than stylistic: a `draw` with a side effect now happens once per player,
    # and an allocation in one costs that many times.
    #
    # A node that genuinely needs per-view work at draw time can read
    # `system(Viewports).views` itself. Anything needing per-view state *over
    # time* — a screen shake, a hit flash — is per-*player* rather than per-view,
    # and belongs on that player's camera or their own subtree, which tick once.
    class WorldView < Node2D
      # World content, which is the default anyway — stated because this is the
      # node that marks where world space begins, and a reader looking for
      # "which band is the world in" should find the answer here.
      def initialize(**)
        super(band: :world, **)
      end

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
