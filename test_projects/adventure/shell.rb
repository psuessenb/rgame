# frozen_string_literal: true

# The root: a SceneStack with the room pushed into it.
#
# It holds nothing else. Everything this project grows — a second room, a
# transition between them, state that outlives a scene — lands here, and starting
# with the stack means none of it has to move the root out from under the room
# first.
class Shell < RGame::Engine::Node2D
  def initialize
    super
    @stack = add_component(RGame::Engine::Scene::SceneStack.new)
  end

  def _enter_tree = @stack.push(Room.new)
end
