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
#
# Where it stands and which way it last moved are kept in Facts, under keys
# made from the one the room names. It reads them as it is built, and writes
# them on each tick it has moved, so a room built anew puts the crate back where
# it was left.
class Crate < RGame::Engine::Node2D
  SIZE = 16

  COLOR = RGame::Util::Color.new(176, 128, 72)

  LABELS = { still: 'crate', east: 'east', west: 'west' }.freeze

  KEPT = %w[x y way].freeze

  def initialize(facts:, key:, x:, y:)
    @keys = KEPT.map { :"#{key}_#{it}" }.freeze
    x_key, y_key, way_key = @keys
    super(x: @kept_x = facts.fetch(x_key, x), y: @kept_y = facts.fetch(y_key, y))
    add_component(RGame::Engine::Components::BoxCollider.new(width: SIZE, height: SIZE, layer: :crate))
    @pushable = add_component(RGame::Engine::Components::Pushable.new(blocked_by: %i[tiles crate hero]))
    @facts = facts
    @way = facts.fetch(way_key, 'still').to_sym
  end

  def _update(_dt)
    pushed = @pushable.pushed_x
    @way = pushed.positive? ? :east : :west unless pushed.zero?
    keep unless x == @kept_x && y == @kept_y
  end

  def _draw(renderer, _view)
    renderer.rect(0, 0, SIZE, SIZE, color: COLOR)
    renderer.text(LABELS.fetch(@way), 0, -12)
  end

  private

  def keep
    x_key, y_key, way_key = @keys
    @facts[x_key] = @kept_x = x
    @facts[y_key] = @kept_y = y
    @facts[way_key] = @way.name
  end
end
