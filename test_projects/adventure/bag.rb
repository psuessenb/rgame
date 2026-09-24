# frozen_string_literal: true

# One player's bag: a Tabs of two pages, Carried and Worn, over what their hero
# holds.
#
# It lives in that player's PlayerLayer, so it draws in their region and reads
# their input with nothing configured. The hero owns what it carries and wears;
# the bag is handed the hero and reads both lists each time it opens, so no hook
# hands it anything.
#
# A closed Tabs reads no input, so the bag itself reads `bag`, I or the pad's
# Start, and opens and closes it. While the tabs are open the hero is paused: it
# stands still in a world that goes on for the other player. A press begun in
# the bag stays there, because a node reads only the presses it saw start, so E
# switching a tab never reaches the hero's Interactor, even when it is let go
# after the bag closes.
#
# Carried lists what the hero holds, with a count for more than one of a thing.
# Choosing a wearable wears it. Worn lists each slot and what it wears, and
# choosing a slot takes its piece off. Both pages are rebuilt when the bag opens
# on a hero whose `revision` moved since the last rebuild, and after a choice.
class Bag < RGame::Engine::Node2D
  UI = RGame::Engine::UI

  WIDTH = 216
  HEIGHT = 136
  BACKDROP = RGame::Util::Color.new(24, 20, 32, 220)

  def initialize(hero:, **)
    super(**)
    @hero = hero
    @revision = nil
    @tabs = add_node(UI::Tabs.new(x: 8, y: 8, layout: UI::Row.new(item_width: 96, item_height: 24, spacing: 4)))
    @carried = page_menu
    @worn = page_menu
    @tabs.add(UI::TextButton.new(label: RGame::Engine::Text.literal('Carried')), @carried.parent)
    @tabs.add(UI::TextButton.new(label: RGame::Engine::Text.literal('Worn')), @worn.parent)
    @tabs.on_opened { opened }
    @tabs.on_closed { @hero.paused = false }
  end

  def _enter_tree = @tabs.close

  def _control(actions)
    return unless actions.pressed?(:bag)

    @tabs.open? ? @tabs.close : @tabs.open
  end

  def _draw(renderer, _view)
    renderer.rect(0, 0, WIDTH, HEIGHT, color: BACKDROP) if @tabs.open?
  end

  private

  def page_menu
    page = RGame::Engine::Node2D.new
    page.add_node(UI::Menu.new(y: 8, layout: UI::Column.new(item_width: 196, item_height: 22, spacing: 4)))
  end

  def opened
    @hero.paused = true
    refresh
  end

  def refresh
    return if @revision == @hero.revision

    @revision = @hero.revision
    @carried.clear
    @hero.carried.group_by(&:name).each_value { |items| list(items) }
    @worn.clear
    Hero::SLOTS.each { |slot| show(slot) }
  end

  def list(items)
    item = items.first
    label = items.size > 1 ? "#{item.name} x #{items.size}" : item.name
    button = @carried.add(UI::TextButton.new(label: RGame::Engine::Text.literal(label)))
    button.on_activated { choose { @hero.wear(item) } } if item.wearable?
  end

  def show(slot)
    worn = @hero.worn[slot]
    label = "#{slot}: #{worn ? worn.name : 'empty'}"
    @worn.add(UI::TextButton.new(label: RGame::Engine::Text.literal(label))).on_activated do
      choose { @hero.take_off(slot) }
    end
  end

  def choose
    yield
    refresh
  end
end
