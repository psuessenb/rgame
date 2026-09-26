# frozen_string_literal: true

module Adventure
  # Something to press. It carries a collider on the `:interactable` layer and
  # nothing else — no input, no range, no knowledge of a hero.
  #
  # A Hero's Interactor finds it by that layer and calls `open`; the same hero's
  # own `_control` calls `search` while the button is held. Which of the two
  # happened is the input map's answer, not this class's: `interact` is a tap and
  # `search` is a hold, both on E and the pad's X.
  #
  # It draws its state as a word so a driven run can tell a tap from a hold. A
  # test project draws Strings; an example would draw a translation key.
  #
  # Its state is a field of its Components::Facts, kept in the facts database
  # under the key the room names, so a room built anew holds the chest as it was
  # left. It reads the field as it enters the tree, and writes it at each change.
  class Chest < Engine::Node2D
    SIZE = 20

    CLOSED = Util::Color.new(150, 104, 56)
    OPEN = Util::Color.new(96, 78, 56)
    SEARCHED = Util::Color.new(72, 96, 78)

    LABELS = { closed: 'chest', open: 'open', searched: 'searched' }.freeze

    STRAW = Util::Color.new(232, 200, 112)
    COLORS = { closed: CLOSED, open: OPEN, searched: SEARCHED }.freeze

    def initialize(key:, **)
      super(**)
      add_component(Components::BoxCollider.new(width: SIZE, height: SIZE,
                                                layer: :interactable))
      @facts = add_component(Components::Facts.new(key:, state: 'closed'))
    end

    attr_reader :state

    def _enter_tree = @state = @facts[:state].to_sym

    def open
      change(:open) if @state == :closed
    end

    # Returns the hat inside, once. Only an open chest has anything to search, so
    # a hold on a closed one finds nothing — which is what makes the two actions
    # distinguishable in a report rather than merely both firing.
    def search
      return unless @state == :open

      change(:searched)
      Item.new('hat', slot: :head, color: STRAW)
    end

    def _draw(renderer, _view)
      renderer.rect(0, 0, SIZE, SIZE, color: COLORS.fetch(@state))
      renderer.text(LABELS.fetch(@state), 0, -12)
    end

    private

    def change(state)
      @state = state
      @facts[:state] = state.name
    end
  end
end
