# frozen_string_literal: true

# A Scene::Room that logs what reached it, and places what arrives at a spot
# per entrance, under a node of its own. The rooms specs build their rooms
# from it. It logs only when handed a log, so a room built without one
# allocates nothing.
class SpecRoom < RGame::Engine::Scene::Room
  SPOTS = { 'gate' => [10, 20], 'well' => [30, 40] }.freeze

  attr_reader :actors, :arrivals

  def initialize(log = nil)
    super()
    @log = log
    @arrivals = []
  end

  def _enter_tree = @actors = add_node(RGame::Engine::Node2D.new)

  def _arrive(node, entrance)
    @arrivals << [node, entrance]
    node.x = SPOTS.fetch(entrance).first
    node.y = SPOTS.fetch(entrance).last
    @actors.add_node(node)
  end

  def _control(_actions) = @log&.push([name, :control])
  def _update(_dt) = @log&.push([name, :update])
end
