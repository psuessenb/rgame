# frozen_string_literal: true

# A hero's two status lines, drawn in its player's PlayerLayer, so each player
# reads their own in their own region.
class Hud < RGame::Engine::Node2D
  MARGIN = 12
  LINE = 18

  def initialize(hero:)
    super()
    @hero = hero
  end

  def _draw(renderer, _view)
    renderer.text(@hero.falls_line, MARGIN, MARGIN)
    renderer.text(@hero.checkpoint_line, MARGIN, MARGIN + LINE)
  end
end
