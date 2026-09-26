# frozen_string_literal: true

module Adventure
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
  # Where it stands and which way it last moved are kept in the facts database,
  # through one Components::Fact for each, under parts of the key the room names.
  # It reads them as it enters the tree, and writes them on each tick it has
  # moved, so a room built anew puts the crate back where it was left.
  class Crate < Engine::Node2D
    SIZE = 16

    COLOR = Util::Color.new(176, 128, 72)

    LABELS = { still: 'crate', east: 'east', west: 'west' }.freeze

    def initialize(key:, x:, y:)
      super(x:, y:)
      add_component(Components::BoxCollider.new(width: SIZE, height: SIZE, layer: :crate))
      @pushable = add_component(Components::Pushable.new(blocked_by: %i[tiles crate hero]))
      @kept_x = add_component(Components::Fact.new(key:, part: :x, default: x), as: :x)
      @kept_y = add_component(Components::Fact.new(key:, part: :y, default: y), as: :y)
      @kept_way = add_component(Components::Fact.new(key:, part: :way, default: 'still'), as: :way)
    end

    def _enter_tree
      self.x = @kept_x.value
      self.y = @kept_y.value
      @way = @kept_way.value.to_sym
    end

    def _update(_dt)
      pushed = @pushable.pushed_x
      @way = pushed.positive? ? :east : :west unless pushed.zero?
      keep unless x == @kept_x.value && y == @kept_y.value
    end

    def _draw(renderer, _view)
      renderer.rect(0, 0, SIZE, SIZE, color: COLOR)
      renderer.text(LABELS.fetch(@way), 0, -12)
    end

    private

    def keep
      @kept_x.value = x
      @kept_y.value = y
      @kept_way.value = @way.name
    end
  end
end
