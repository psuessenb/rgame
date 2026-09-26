# frozen_string_literal: true

module Asteroids
  # The score, in the corner.
  #
  # A node of its own rather than a line in PlayScene's `_draw`, because it has
  # to draw over the ship and the rocks — and those are PlayScene's children, so
  # anything PlayScene draws itself is already behind them. Saying `band: :hud`
  # puts this above every world slot in the frame whatever the tree looks like,
  # which is the whole job of a band.
  class ScoreLabel < Engine::Node2D
    COLOR = Util::Color.new(220, 225, 235)

    def initialize(x:, y:)
      super(x: x, y: y, band: :hud)
      @text = ''
    end

    # A cached String, rebuilt only when the score changes: `draw` runs every
    # frame and interpolating there would allocate one per frame.
    def score=(value)
      @text = "Score #{value}"
    end

    # At its own origin: the traversal has already put the renderer there.
    def _draw(renderer, _view) = renderer.text(@text, 0, 0, color: COLOR)
  end
end
