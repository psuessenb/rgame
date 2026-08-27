# frozen_string_literal: true

require_relative 'high_scores'

# The game-over screen: records the run into the root-scoped HighScores system,
# then shows the final score and the top list, Enter to play again. The display
# strings are built in on_add (not on_draw) so per-frame drawing allocates nothing
# (the Game/NoInterpolationInDraw rule). Centring is against the `view` — see
# StartScene for why that is the window's question and not the world's.
class GameOverScene < RGame::Engine::Node2D
  TITLE = 'G A M E   O V E R'
  HINT  = 'Press Enter to play again'
  TITLE_COLOR = [255, 200, 200].freeze
  TEXT_COLOR  = [220, 225, 235].freeze
  HINT_COLOR  = [150, 170, 200].freeze

  def initialize(score:)
    super()
    @score = score
  end

  def on_add
    high_scores = system(HighScores)
    high_scores.record(@score)
    @score_text = "Final score: #{@score}"
    @high_lines = high_scores.top.each_with_index.map { |score, i| "#{i + 1}.  #{score}" }
  end

  def on_control(actions)
    return unless actions.pressed?(:ui_confirm)

    RGame::Engine::AudioBus.play_sound(:blip)
    root.go(:play)
  end

  def on_draw(renderer, view)
    renderer.background(:space)
    centered(renderer, view, TITLE, 90, TITLE_COLOR)
    centered(renderer, view, @score_text, 130, TEXT_COLOR)
    centered(renderer, view, 'High Scores', 180, TEXT_COLOR)
    @high_lines.each_with_index { |line, i| centered(renderer, view, line, 210 + (i * 24), TEXT_COLOR) }
    centered(renderer, view, HINT, view.height - 40, HINT_COLOR)
  end

  private

  # No z and no band — see StartScene: one node, backdrop under text by default.
  # hot-path
  def centered(renderer, view, text, y, color)
    renderer.text(text, (view.width - renderer.text_width(text)) / 2, y, color: color)
  end
end
