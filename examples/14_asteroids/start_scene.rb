# frozen_string_literal: true

# The title screen: text over the space backdrop, Enter to play. Text-only (no UI
# widgets yet). The confirm transition is requested via root.go, which the Root
# applies safely at the end of the tick.
class StartScene < RGame::Engine::Node2D
  TITLE = 'A S T E R O I D S'
  HINT  = 'Press Enter to start'
  TITLE_COLOR = [230, 240, 255].freeze
  HINT_COLOR  = [150, 170, 200].freeze

  def initialize(width:, height:)
    super()
    @width = width
    @height = height
  end

  def on_control(actions)
    return unless actions.pressed?(:ui_confirm)

    RGame::Engine::AudioBus.play_sound(:blip)
    root.go(:play)
  end

  def on_draw(renderer, _view)
    renderer.background(:space)
    centered(renderer, TITLE, (@height / 2) - 30, TITLE_COLOR)
    centered(renderer, HINT, (@height / 2) + 20, HINT_COLOR)
  end

  private

  def centered(renderer, text, y, color)
    renderer.text(text, (@width - renderer.text_width(text)) / 2, y, z: 20, color: color)
  end
end
