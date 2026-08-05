# frozen_string_literal: true

# A program-lifetime high-score table. It lives as a component on the Root node, so
# it is a *global*-scoped system (cf. the scene-scoped CollisionWorld): any node
# reaches it with `node.system(HighScores)`, which resolves scene-first and then
# falls through to the root. The game-over scene records into it and reads it back.
class HighScores < Engine::Component
  def initialize(limit: 5)
    super()
    @limit = limit
    @scores = []
  end

  def record(score)
    @scores << score
    @scores.sort! { |a, b| b <=> a }
    @scores = @scores.first(@limit)
  end

  def top = @scores
end
