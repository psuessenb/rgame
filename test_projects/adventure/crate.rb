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
  # Components::Facts, kept in the facts database. The town builds its crate in
  # code and names the key. The course's map builds one, and its key comes from
  # the map object. A crate reads its fields as it enters the tree, and writes
  # them on each tick it has moved, so a room built anew puts the crate back
  # where it was left.
  #
  # It is centred on its node, so its centre is where it stands, and a fall
  # shrinks it toward its middle. Pushed into a gap, it falls as a hero does,
  # and comes back blinking where it first stood in that room. Its Footing has
  # no coyote time, so it drops the tick its centre leaves the floor. The town
  # has no gaps, so only the course's crate ever falls.
  class Crate < Engine::Node2D
    SIZE = 16

    COLOR = Util::Color.new(176, 128, 72)

    LABELS = { still: 'crate', east: 'east', west: 'west' }.freeze

    # @placeable
    def initialize(key: nil, **)
      super(**)
      add_component(Components::BoxCollider.new(width: SIZE, height: SIZE, offset_x: -SIZE / 2,
                                                offset_y: -SIZE / 2, layer: :crate))
      @pushable = add_component(Components::Pushable.new(blocked_by: %i[tiles crate hero]))
      add_component(Components::Footing.new(coyote: 0))
      add_component(Components::Fall.new)
      add_component(Components::Shrink.new)
      blink = add_component(Components::Blink.new)
      add_component(Components::Respawn.new).on_respawned { blink.start(0.5) }
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
      renderer.rect(-SIZE / 2, -SIZE / 2, SIZE, SIZE, color: COLOR)
      renderer.text(LABELS.fetch(@way), -SIZE / 2, (-SIZE / 2) - 12)
    end

    private

    def keep
      @facts[:x] = x
      @facts[:y] = y
      @facts[:way] = @way.name
    end
  end
end
