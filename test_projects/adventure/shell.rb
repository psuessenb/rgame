# frozen_string_literal: true

# The root: a SceneStack with the room pushed into it, and the switch for the
# debug shapes.
#
# It holds nothing else. Everything this project grows — a second room, a
# transition between them, state that outlives a scene — lands here, and starting
# with the stack means none of it has to move the root out from under the room
# first.
#
# The debug switch is here rather than in the room because it belongs to the
# project rather than to any one scene, and because a component on the root
# reads the primary player's actions with nothing declaring an owner.
class Shell < RGame::Engine::Node2D
  def initialize
    super
    @stack = add_component(RGame::Engine::Scene::SceneStack.new)
    add_component(DebugToggle.new)
  end

  def _enter_tree = @stack.push(Room.new)
end
