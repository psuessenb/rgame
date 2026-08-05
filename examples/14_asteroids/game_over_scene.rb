# frozen_string_literal: true

require_relative 'high_scores'

# The game-over screen: records the run into the root-scoped HighScores system,
# then shows the final score and the top list, Enter to play again. The display
# strings are built in on_add (not on_draw) so per-frame drawing allocates nothing
# (the Game/NoInterpolationInDraw rule).
class GameOverScene < Engine::Node2D
  TITLE = 'G A M E   O V E R'
  HINT  = 'Press Enter to play again'
  TITLE_COLOR = [255, 200, 200].freeze
  TEXT_COLOR  = [220, 225, 235].freeze
  HINT_COLOR  = [150, 170, 200].freeze

  def initialize(width:, height:, score:)
    super()
    @width = width
    @height = height
    @score = score
  end

  def on_add
    high_scores = system(HighScores)
    high_scores.record(@score)
    @score_text = "Final score: #{@score}"
    @high_lines = high_scores.top.each_with_index.map { |score, i| "#{i + 1}.  #{score}" }
  end

  def on_control(actions)
    return unless actions.pressed?(:confirm)

    Engine::AudioBus.play_sound(:blip)
    root.go(:play)
  end

  def on_draw(renderer)
    renderer.background(:space)
    centered(renderer, TITLE, 90, TITLE_COLOR)
    centered(renderer, @score_text, 130, TEXT_COLOR)
    centered(renderer, 'High Scores', 180, TEXT_COLOR)
    @high_lines.each_with_index { |line, i| centered(renderer, line, 210 + (i * 24), TEXT_COLOR) }
    centered(renderer, HINT, @height - 40, HINT_COLOR)
  end

  private

  def centered(renderer, text, y, color)
    renderer.text(text, (@width - renderer.text_width(text)) / 2, y, z: 20, color: color)
  end
end
