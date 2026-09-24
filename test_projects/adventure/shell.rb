# frozen_string_literal: true

# The root: a SceneStack with the room pushed into it, the switch for the
# debug shapes, and the storm.
#
# It holds nothing else. Everything this project grows — a second room, a
# door between them, state that outlives a scene — lands here, and starting
# with the stack means none of it has to move the root out from under the room
# first.
#
# The room arrives under the stack's transition. Pushed onto an empty stack, it
# starts covered and reveals over half a second, and the music rises over the
# same half second from the moment the room lands. No player reads input until
# the reveal ends.
#
# The debug switch is here rather than in the room because it belongs to the
# project rather than to any one scene, and because a component on the root
# reads the primary player's actions with nothing declaring an owner. The storm
# is here because it covers the whole window, and a node at the root draws once
# a frame across it.
class Shell < RGame::Engine::Node2D
  ARRIVAL = RGame::Engine::Scene::Fade.new(cover: 0.5, reveal: 0.5)
  MUSIC = 'music.ogg'

  def initialize
    super
    @stack = add_component(RGame::Engine::Scene::SceneStack.new)
    @stack.transition = ARRIVAL
    @stack.on_changed { system!(RGame::Engine::AudioOut).play_music(MUSIC, fade: ARRIVAL.reveal) }
    add_component(DebugToggle.new)
    add_node(Storm.new)
  end

  def _enter_tree = @stack.push(Room.new)
end
