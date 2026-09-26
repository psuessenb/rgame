# frozen_string_literal: true

module Adventure
  # A second thing to press, which a hero pulls with the tap that opens the chest.
  #
  # It carries a collider on the `:interactable` layer, as the chest does, so a
  # hero's Interactor finds whichever of the two is nearer. It stands far enough
  # from the chest that a hero in reach of one is out of reach of the other.
  #
  # It draws its state as a word, "lever" or "pulled", so a driven run can say
  # which press reached it and which did not. A hold searches it and finds
  # nothing.
  #
  # Like the chest, it keeps its state in Facts, through a Components::Fact under
  # the key the room names.
  class Lever < Engine::Node2D
    WIDTH = 12
    HEIGHT = 20

    BASE = Util::Color.new(96, 96, 112)
    HANDLE = Util::Color.new(200, 64, 56)

    LABELS = { up: 'lever', down: 'pulled' }.freeze

    def initialize(key:, **)
      super(**)
      add_component(Components::BoxCollider.new(width: WIDTH, height: HEIGHT,
                                                layer: :interactable))
      @kept = add_component(Components::Fact.new(key:, default: 'up'))
    end

    attr_reader :state

    def _enter_tree = @state = @kept.value.to_sym

    def open
      @state = @state == :up ? :down : :up
      @kept.value = @state.name
    end

    def search = nil

    def _draw(renderer, _view)
      renderer.rect(0, HEIGHT - 6, WIDTH, 6, color: BASE)
      tip_y = @state == :up ? 0 : HEIGHT - 4
      renderer.line(WIDTH / 2, HEIGHT - 6, WIDTH / 2, tip_y, thickness: 2, color: HANDLE)
      renderer.text(LABELS.fetch(@state), 0, -12)
    end
  end
end
