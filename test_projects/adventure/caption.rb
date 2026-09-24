# frozen_string_literal: true

# A line of text along the bottom of the window, for a cutscene to say what is
# happening. It is in the `:overlay` band, outside any WorldView, so it draws
# once across the window, over the world and both bags. With no text it draws
# nothing.
class Caption < RGame::Engine::Node2D
  COLOR = RGame::Util::Color.new(250, 244, 220)

  attr_accessor :text

  def initialize
    super(band: :overlay)
    @text = nil
  end

  def _draw(renderer, view)
    return unless @text

    renderer.text(@text, (view.width - renderer.text_width(@text)) / 2, view.height - 40, color: COLOR)
  end
end
