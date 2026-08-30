# frozen_string_literal: true

# The title screen: text over the space backdrop, Enter to play. Text-only (no UI
# widgets yet). The confirm transition is requested via root.go, which the Root
# applies safely at the end of the tick.
#
# It centres against the `view` it is handed rather than against a size passed in:
# this is the *window* question, not the world one, and the View is what answers it
# — correctly even when the window is resized or is one player's half of a split.
class StartScene < RGame::Engine::Node2D
  TITLE = 'A S T E R O I D S'
  HINT  = 'Press Enter to start'
  TITLE_COLOR = [230, 240, 255].freeze
  HINT_COLOR  = [150, 170, 200].freeze

  def on_control(actions)
    return unless actions.pressed?(:ui_confirm)

    RGame::Engine::AudioBus.play_sound(:blip)
    root.go(:play)
  end

  def on_draw(renderer, view)
    renderer.background(:space)
    centered(renderer, view, TITLE, (view.height / 2) - 30, TITLE_COLOR)
    centered(renderer, view, HINT, (view.height / 2) + 20, HINT_COLOR)
  end

  private

  # No z and no band. This scene is the only thing on screen and draws its
  # backdrop and its text in one node, and `text` already defaults above
  # `background` inside a node's own slot.
  # hot-path
  def centered(renderer, view, text, y, color)
    renderer.text(text, (view.width - renderer.text_width(text)) / 2, y, color: color)
  end
end
