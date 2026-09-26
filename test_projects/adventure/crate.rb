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
  # Where it stands and which way it last moved are the fields of its
  # Components::Facts, kept in the facts database under the key the room names.
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
      @facts = add_component(Components::Facts.new(key:, x:, y:, way: 'still'))
    end

    def _enter_tree
      self.x = @facts[:x]
      self.y = @facts[:y]
      @way = @facts[:way].to_sym
    end

    def _update(_dt)
      pushed = @pushable.pushed_x
      @way = pushed.positive? ? :east : :west unless pushed.zero?
      keep unless x == @facts[:x] && y == @facts[:y]
    end

    def _draw(renderer, _view)
      renderer.rect(0, 0, SIZE, SIZE, color: COLOR)
      renderer.text(LABELS.fetch(@way), 0, -12)
    end

    private

    def keep
      @facts[:x] = x
      @facts[:y] = y
      @facts[:way] = @way.name
    end
  end
end
