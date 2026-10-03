# frozen_string_literal: true

module Adventure
  # A hero's two status lines, drawn in its player's PlayerLayer, so each player
  # reads their own in their own region. They stand at the region's top right,
  # clear of the bag at its top left.
  class Hud < Engine::Node2D
    MARGIN = 12
    LINE = 18

    def initialize(hero:)
      super()
      @hero = hero
    end

    def _draw(renderer, view)
      right(renderer, view, @hero.falls_line, MARGIN)
      right(renderer, view, @hero.checkpoint_line, MARGIN + LINE)
    end

    private

    # hot-path
    def right(renderer, view, text, y)
      renderer.text(text, view.width - MARGIN - renderer.text_width(text), y)
    end
  end
end
