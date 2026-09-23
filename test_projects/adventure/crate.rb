# frozen_string_literal: true

# Something to push and pull. It carries a collider on the `:crate` layer and a
# Pushable, and nothing that reads input: a hero's `pushes: [:crate]` moves it by
# walking into it, and a hero's Grab drags it while a button is held.
#
# Its own `blocked_by:` names the map, other crates and the heroes, so it stops at
# the fence as a hero does, and two heroes pushing it from either side hold it
# still.
#
# It draws which way the last push moved it, as a word, so a driven run can tell
# a push from a pull: "crate" until something moves it, then "east" or "west".
class Crate < RGame::Engine::Node2D
  SIZE = 16

  COLOR = RGame::Util::Color.new(176, 128, 72)

  LABELS = { still: 'crate', east: 'east', west: 'west' }.freeze

  def initialize(**)
    super
    add_component(RGame::Engine::Components::BoxCollider.new(width: SIZE, height: SIZE, layer: :crate))
    @pushable = add_component(RGame::Engine::Components::Pushable.new(blocked_by: %i[tiles crate hero]))
    @way = :still
  end

  def _update(_dt)
    pushed = @pushable.pushed_x
    @way = pushed.positive? ? :east : :west unless pushed.zero?
  end

  def _draw(renderer, _view)
    renderer.rect(0, 0, SIZE, SIZE, color: COLOR)
    renderer.text(LABELS.fetch(@way), 0, -12)
  end
end
