# frozen_string_literal: true

module Adventure
  # The root: a SceneStack with the world pushed into it, the switch for the
  # debug shapes, and the storm.
  #
  # It holds nothing else. The world holds the rooms, the heroes and their bags,
  # and a title screen or a pause menu would be one more scene on this stack.
  #
  # The world lands in the first sweep, and its first hero arrives under the
  # rooms' opening fade: the town starts covered and reveals over half a second,
  # and its song rises over the same half second. No player reads input until
  # the reveal ends.
  #
  # The debug switch is here rather than in a room because it belongs to the
  # project rather than to any one scene, and because a component on the root
  # reads the primary player's actions with nothing declaring an owner. The storm
  # is here because it covers the whole window, and a node at the root draws once
  # a frame across it.
  class Shell < Engine::Node2D
    def initialize
      super
      @stack = add_component(Engine::Scene::SceneStack.new)
      add_component(DebugToggle.new)
      add_node(Storm.new)
    end

    def _enter_tree = @stack.push(World.new)
  end
end
