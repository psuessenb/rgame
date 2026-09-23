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
      expect(menu.focused.label.key).to eq('Two')
    end

    it 'wraps before the start with ui_up' do
      press(:ui_up)
      expect(menu.focused.label.key).to eq('Three')
    end

    it 'hands ui_right to the focused button, and moves no focus' do
      press(:ui_down)
      press(:ui_right)
      expect([menu.focused.label.key, menu.focused.value]).to eq(['Two', 2])
    end
  end

  describe 'along a horizontal axis' do
    let!(:menu) { build(layout: row) }

    it 'steps right with ui_right' do
      press(:ui_right)
      expect(menu.focused.label.key).to eq('Two')
    end

    it 'steps left with ui_left, wrapping before the start' do
      press(:ui_left)
      expect(menu.focused.label.key).to eq('Three')
    end

    it 'wraps past the end' do
      3.times { press(:ui_right) }
      expect(menu.focused.label.key).to eq('One')
    end

    it 'moves no focus with ui_down' do
      press(:ui_down)
      expect(menu.focused.label.key).to eq('One')
    end

    it 'hands ui_up and ui_down to the focused button' do
      press(:ui_right)
      press(:ui_down)
      press(:ui_down)
      press(:ui_up)
      expect([menu.focused.label.key, menu.focused.value]).to eq(['Two', 1])
    end
  end

  describe 'across a grid' do
    # Four columns, so seven buttons make a full row and a short one:
    #
    #   b0 b1 b2 b3
    #   b4 b5 b6
    def grid_menu(count = 7, disabled: [])
      grid = RGame::Engine::UI::Grid.new(columns: 4, item_width: 40, item_height: 40)
      menu = root.add_node(RGame::Engine::UI::Menu.new(layout: grid))
      count.times do |index|
        menu.add(RGame::Engine::UI::TextButton.new(label: "b#{index}", enabled: !disabled.include?(index)))
      end
      root.enter_tree
      menu
    end

    def focused_label(menu) = menu.focused.label.key

    def after(menu, *presses)
      presses.each { press(it) }
      focused_label(menu)
    end

    it 'steps along the row with ui_right' do
      expect(after(grid_menu, :ui_right)).to eq('b1')
    end

    it 'steps down the column with ui_down' do
      expect(after(grid_menu, :ui_right, :ui_down)).to eq('b5')
    end

    it 'steps up the column with ui_up' do
      expect(after(grid_menu, :ui_right, :ui_down, :ui_up)).to eq('b1')
    end

    it 'takes the last button of a short row that has none in this column' do
      expect(after(grid_menu, :ui_left, :ui_down)).to eq('b6')
    end

    it 'skips a disabled button along the row' do
      expect(after(grid_menu(disabled: [1]), :ui_right)).to eq('b2')
    end

    it 'skips a disabled button down the column, and goes on to the next one' do
      expect(after(grid_menu(11, disabled: [5]), :ui_right, :ui_down)).to eq('b9')
    end

    it 'wraps past the end of a row, inside it' do
      expect(after(grid_menu, :ui_left, :ui_right)).to eq('b0')
    end

    it 'wraps before the start of a row, inside it' do
      expect(after(grid_menu, :ui_left)).to eq('b3')
    end

    it 'wraps inside a short last row' do
      expect(after(grid_menu, :ui_down, :ui_left)).to eq('b6')
    end

    it 'wraps past the end of a column, inside it' do
      expect(after(grid_menu, :ui_right, :ui_down, :ui_down)).to eq('b1')
    end

    it 'counts the edge from the last enabled button before it' do
      expect(after(grid_menu(disabled: [3]), :ui_right, :ui_right, :ui_right)).to eq('b0')
    end

    it 'leaves focus where it is on a line with no other enabled button' do
      expect(after(grid_menu(disabled: [4, 6]), :ui_right, :ui_down, :ui_right)).to eq('b5')
    end

    it 'moves along the row with #step' do
      menu = grid_menu
      menu.navigation.step(1)
      expect(focused_label(menu)).to eq('b1')
    end

    # The pair that would adjust on a column moves focus on a grid, so an
    # OptionButton in one keeps its value.
    it 'adjusts nothing' do
      grid = RGame::Engine::UI::Grid.new(columns: 2, item_width: 40, item_height: 40)
      menu = root.add_node(RGame::Engine::UI::Menu.new(layout: grid))
      option = menu.add(RGame::Engine::UI::OptionButton.new(label: 'Volume', values: [0, 1, 2], index: 1))
      2.times { menu.add(RGame::Engine::UI::TextButton.new(label: 'Other')) }
      root.enter_tree
      press(:ui_down)
      expect([menu.focused_index, option.value]).to eq([2, 1])
    end

    it 'refuses an axis other than the grid\'s' do
      grid = RGame::Engine::UI::Grid.new(columns: 4, item_width: 40, item_height: 40)
      expect { RGame::Engine::UI::Menu.new(layout: grid, navigation: described_class.new(axis: :vertical)) }
        .to raise_error(ArgumentError, /a grid steps along its rows, so axis: must be :horizontal/)
    end

    it 'takes the grid\'s own axis when passed' do
      grid = RGame::Engine::UI::Grid.new(columns: 4, item_width: 40, item_height: 40)
      menu = RGame::Engine::UI::Menu.new(layout: grid, navigation: described_class.new(axis: :horizontal))
      expect(menu.navigation.axis).to eq(:horizontal)
    end
  end

  describe 'the axis' do
    # The pair, as one example: a Row said nothing about navigation and still
    # steps the way it is laid out.
    it 'follows the layout when none is passed, so a Row steps with left and right' do
      menu = build(layout: row)
      press(:ui_right)
      expect([menu.navigation.axis, menu.focused.label.key]).to eq([:horizontal, 'Two'])
    end

    it 'is nil until a menu is built with it, when none is passed' do
      expect(described_class.new.axis).to be_nil
    end

    it 'overrides the layout\'s when passed' do
      menu = build(layout: column, navigation: described_class.new(axis: :horizontal))
      press(:ui_right)
      expect([menu.navigation.axis, menu.focused.label.key]).to eq([:horizontal, 'Two'])
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

  describe 'actions:' do
    let(:snapshot) do
      reads = %i[ui_up ui_down ui_left ui_right ui_confirm ui_tab_prev ui_tab_next]
      held = reads.to_h { |name| [name, false] }
      previous = reads.to_h { |name| [name, false] }
      actions = RGame::Engine::Actions.new(held: held, axes: {}, prev_held: previous)

      lambda do |*down|
        held.each { |name, state| previous[name] = state }
        reads.each { |name| held[name] = down.include?(name) }
        actions
      end
    end

    let(:tabs) { described_class.new(actions: %i[ui_tab_prev ui_tab_next]) }

    it 'steps on with the second action' do
      menu = build(layout: row, navigation: tabs)
      press(:ui_tab_next)
      expect(menu.focused.label.key).to eq('Two')
    end

    it 'wraps back with the first' do
      menu = build(layout: row, navigation: tabs)
      press(:ui_tab_prev)
      expect(menu.focused.label.key).to eq('Three')
    end

    it 'reads neither pair of arrows' do
      menu = build(layout: row, navigation: tabs)
      %i[ui_left ui_right ui_up ui_down].each { press(it) }
      expect(menu.focused.label.key).to eq('One')
    end

    it 'adjusts nothing' do
      menu = build(layout: column, navigation: tabs)
      press(:ui_tab_next)
      press(:ui_right)
      expect(menu.focused.value).to eq(1)
    end

    it 'never crosses, and wraps inside its own menu' do
      group = root.add_node(RGame::Engine::UI::FocusGroup.new)
      menu = group.add_node(RGame::Engine::UI::Menu.new(layout: row, navigation: tabs))
      %w[One Two].each { |label| menu.add(RGame::Engine::UI::TextButton.new(label: label)) }
      beside = group.add_node(RGame::Engine::UI::Menu.new(x: 400, layout: row))
      beside.add(RGame::Engine::UI::TextButton.new(label: 'Beside'))
      root.enter_tree
      root.control(snapshot.call)
      2.times { press(:ui_tab_next) }
      expect([group.current, menu.focused.label.key]).to eq([menu, 'One'])
    end

    it 'keeps the names it was given' do
      expect(tabs.actions).to eq(%i[ui_tab_prev ui_tab_next])
    end

    [[:ui_tab_next], %i[a b c], 'ui_tab_prev', %w[ui_tab_prev ui_tab_next]].each do |given|
      it "refuses #{given.inspect}" do
        expect { described_class.new(actions: given) }.to raise_error(ArgumentError, /actions:/)
      end
    end
  end

  describe '#step' do
    it 'skips a disabled button' do
      menu = root.add_node(RGame::Engine::UI::Menu.new(layout: row))
      %w[One Two Three].each { |label| menu.add(RGame::Engine::UI::TextButton.new(label: label, enabled: label != 'Two')) }
      menu.navigation.step(1)
      expect(menu.focused.label.key).to eq('Three')
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
