# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Stepping do
  let(:root) { RGame::Engine::Node2D.new }
  # One reused snapshot over hashes shifted in place, as ActionMapper builds it.
  let(:snapshot) do
    reads = %i[ui_up ui_down ui_left ui_right ui_confirm]
    held = reads.to_h { |name| [name, false] }
    previous = reads.to_h { |name| [name, false] }
    actions = RGame::Engine::Actions.new(held: held, axes: {}, prev_held: previous)

    lambda do |*down|
      held.each { |name, state| previous[name] = state }
      reads.each { |name| held[name] = down.include?(name) }
      actions
    end
  end

  def column = RGame::Engine::UI::Column.new(item_width: 60, item_height: 40)
  def row = RGame::Engine::UI::Row.new(item_width: 60, item_height: 40)

  def build(layout:, navigation: described_class.new)
    menu = root.add_node(RGame::Engine::UI::Menu.new(layout: layout, navigation: navigation))
    menu.add(RGame::Engine::UI::TextButton.new(label: 'One'))
    menu.add(RGame::Engine::UI::OptionButton.new(label: 'Two', values: [0, 1, 2], index: 1))
    menu.add(RGame::Engine::UI::TextButton.new(label: 'Three'))
    root.enter_tree
    menu
  end

  def press(*actions)
    root.control(snapshot.call(*actions))
    root.control(snapshot.call)
  end

  describe 'along a vertical axis' do
    let!(:menu) { build(layout: column) }

    it 'steps down with ui_down' do
      press(:ui_down)
      expect(menu.focused.label).to eq('Two')
    end

    it 'wraps before the start with ui_up' do
      press(:ui_up)
      expect(menu.focused.label).to eq('Three')
    end

    it 'hands ui_right to the focused button, and moves no focus' do
      press(:ui_down)
      press(:ui_right)
      expect([menu.focused.label, menu.focused.value]).to eq(['Two', 2])
    end
  end

  describe 'along a horizontal axis' do
    let!(:menu) { build(layout: row) }

    it 'steps right with ui_right' do
      press(:ui_right)
      expect(menu.focused.label).to eq('Two')
    end

    it 'steps left with ui_left, wrapping before the start' do
      press(:ui_left)
      expect(menu.focused.label).to eq('Three')
    end

    it 'wraps past the end' do
      3.times { press(:ui_right) }
      expect(menu.focused.label).to eq('One')
    end

    it 'moves no focus with ui_down' do
      press(:ui_down)
      expect(menu.focused.label).to eq('One')
    end

    it 'hands ui_up and ui_down to the focused button' do
      press(:ui_right)
      press(:ui_down)
      press(:ui_down)
      press(:ui_up)
      expect([menu.focused.label, menu.focused.value]).to eq(['Two', 1])
    end
  end

  describe 'the axis' do
    # The pair, as one example: a Row said nothing about navigation and still
    # steps the way it is laid out.
    it 'follows the layout when none is passed, so a Row steps with left and right' do
      menu = build(layout: row)
      press(:ui_right)
      expect([menu.navigation.axis, menu.focused.label]).to eq([:horizontal, 'Two'])
    end

    it 'is nil until a menu is built with it, when none is passed' do
      expect(described_class.new.axis).to be_nil
    end

    it 'overrides the layout\'s when passed' do
      menu = build(layout: column, navigation: described_class.new(axis: :horizontal))
      press(:ui_right)
      expect([menu.navigation.axis, menu.focused.label]).to eq([:horizontal, 'Two'])
    end

    it 'refuses one outside Stack::AXES when the menu is built' do
      navigation = described_class.new(axis: :diagonal)
      expect { RGame::Engine::UI::Menu.new(layout: column, navigation: navigation) }
        .to raise_error(ArgumentError, /:diagonal/)
    end

    it 'cannot be taken from a layout that has none' do
      layout = Class.new do
        def arrange(_buttons) = nil
        def bounds(_buttons) = [0, 0, 0, 0]
      end
      expect { RGame::Engine::UI::Menu.new(layout: layout.new) }.to raise_error(NoMethodError, /axis/)
    end

    it 'can be passed for a layout that has none' do
      layout = Class.new do
        def arrange(_buttons) = nil
        def bounds(_buttons) = [0, 0, 0, 0]
      end
      menu = RGame::Engine::UI::Menu.new(layout: layout.new, navigation: described_class.new(axis: :vertical))
      expect(menu.navigation.axis).to eq(:vertical)
    end
  end

  describe '#step' do
    it 'skips a disabled button' do
      menu = root.add_node(RGame::Engine::UI::Menu.new(layout: row))
      %w[One Two Three].each { |label| menu.add(RGame::Engine::UI::TextButton.new(label: label, enabled: label != 'Two')) }
      menu.navigation.step(1)
      expect(menu.focused.label).to eq('Three')
    end

    it 'does nothing when no button can take focus' do
      menu = root.add_node(RGame::Engine::UI::Menu.new(layout: row))
      2.times { menu.add(RGame::Engine::UI::TextButton.new(label: 'Off', enabled: false)) }
      menu.navigation.step(1)
      expect(menu.focused_index).to eq(0)
    end

    it 'does nothing for a menu with no buttons' do
      menu = root.add_node(RGame::Engine::UI::Menu.new(layout: row))
      menu.navigation.step(1)
      expect(menu.focused_index).to be_nil
    end
  end
end
