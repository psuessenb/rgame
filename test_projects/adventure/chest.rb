# frozen_string_literal: true

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
class Chest < RGame::Engine::Node2D
  SIZE = 20

  CLOSED = RGame::Util::Color.new(150, 104, 56)
  OPEN = RGame::Util::Color.new(96, 78, 56)
  SEARCHED = RGame::Util::Color.new(72, 96, 78)

  LABELS = { closed: 'chest', open: 'open', searched: 'searched' }.freeze

  STRAW = RGame::Util::Color.new(232, 200, 112)
  COLORS = { closed: CLOSED, open: OPEN, searched: SEARCHED }.freeze

  def initialize(**)
    super
    add_component(RGame::Engine::Components::BoxCollider.new(width: SIZE, height: SIZE,
                                                             layer: :interactable))
    @state = :closed
  end

  attr_reader :state

  def open
    @state = :open if @state == :closed
  end

  # Returns the hat inside, once. Only an open chest has anything to search, so
  # a hold on a closed one finds nothing — which is what makes the two actions
  # distinguishable in a report rather than merely both firing.
  def search
    return unless @state == :open

    @state = :searched
    Item.new('hat', slot: :head, color: STRAW)
  end

  def _draw(renderer, _view)
    renderer.rect(0, 0, SIZE, SIZE, color: COLORS.fetch(@state))
    renderer.text(LABELS.fetch(@state), 0, -12)
  end
end
