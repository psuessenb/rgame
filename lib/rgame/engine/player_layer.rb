# frozen_string_literal: true

module RGame
  module Engine
    # One player's own corner of the screen.
    #
    #   layer = scene.add_node(PlayerLayer.new(player: players[1]))
    #   layer.add_node(inventory)
    #
    # Its subtree is drawn **once**, clipped to that player's viewport and
    # translated to its corner, in screen space. That is the third kind of
    # content a frame holds: the world is drawn once per viewport under a
    # camera, a global overlay once across the whole window, and this once per
    # player inside their own region.
    #
    # ## Its children are positioned relative to it
    #
    # A node at (10, 10) under this layer is ten pixels inside *that player's*
    # region, wherever the layout has put it. The layer's translate is what does
    # that, so the same HUD class serves either player with nothing to configure
    # — which is the point of it being a node rather than a rect a HUD looks up.
    #
    # For laying out against the far edge, use the view's **size**:
    # `view.width - margin`. `view.x` and `view.y` are where the region sits on
    # the window and are the clip's business, not a layout origin; adding them
    # would offset a second time.
    #
    # ## It says whose input its subtree reads
    #
    # `input_owner` is set to that player, and ownership is inherited, so a menu
    # anywhere under here reads their controller and nobody else's. Two players
    # with a menu open at once are independent without either one knowing the
    # other exists — see docs/api/scene_graph.md, "Who a node answers to".
    #
    # ## An empty region draws nothing
    #
    # `Viewports#screen_for` is nil for a seat nobody is in, and for everybody
    # while the split is collapsed — a cutscene is everyone looking at one thing,
    # so per-player UI has no place to be. Either way this draws nothing and
    # needs no guard at the call site.
    class PlayerLayer < Node2D
      def initialize(player:, **)
        super(**)
        self.input_owner = player
      end

      # Whose layer this is. The same thing as `input_owner`, and stored only
      # there: two fields would be two things to keep in step.
      def player = input_owner

      def draw(renderer, _view = nil)
        region = system(Viewports).screen_for(player)
        return if region.nil?

        renderer.clipped(region.x, region.y, region.width, region.height) do
          renderer.translated(region.offset_x, region.offset_y) do
            super(renderer, region)
          end
        end
      end
    end
  end
end
