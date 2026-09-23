# frozen_string_literal: true

# A focus group's check runs every tick before its menus read, and a player
# steps and crosses as fast as they press. None of it may allocate.
RSpec.describe RGame::Engine::UI::FocusGroup do
  let(:ui) { RGame::Engine::UI }
  let(:root) { RGame::Engine::Node2D.new }
  let(:group) { root.add_node(described_class.new) }
  let(:reads) { %i[ui_up ui_down ui_left ui_right ui_confirm ui_tab_prev ui_tab_next] }

  # A snapshot whose `pressed` actions press on every read, since the previous
  # frame never had them down.
  def pressing(*pressed)
    held = reads.to_h { |name| [name, pressed.include?(name)] }
    RGame::Engine::Actions.new(held: held, axes: {}, prev_held: reads.to_h { |name| [name, false] })
  end

  def bag
    menu = group.add_node(ui::Menu.new(layout: ui::Grid.new(columns: 3, item_width: 40, item_height: 40)))
    7.times { menu.add(ui::TextButton.new(label: 'item')) }
    menu
  end

  def verbs
    menu = group.add_node(ui::Menu.new(x: 200, layout: ui::Column.new(item_width: 80, item_height: 40)))
    2.times { menu.add(ui::TextButton.new(label: 'verb')) }
    menu
  end

  it 'allocates nothing while checking which menu reads' do
    bag
    verbs
    root.enter_tree
    idle = pressing
    expect { root.control(idle) }.to allocate_nothing
  end

  it 'allocates nothing while stepping a grid along its rows and down its columns' do
    bag
    root.enter_tree
    diagonal = pressing(:ui_right, :ui_down)
    expect { root.control(diagonal) }.to allocate_nothing
  end

  it 'allocates nothing while crossing from a grid to a column and back' do
    grid = bag
    verbs
    root.enter_tree
    grid.focus(2)
    right = pressing(:ui_right)
    left = pressing(:ui_left)
    expect do
      root.control(right)
      root.control(left)
    end.to allocate_nothing
  end

  # Five rows, two in view: a step down scrolls on most rows, and the wrap from
  # the last row to the first scrolls to the top.
  it 'allocates nothing while scrolling a grid a row at a time' do
    grid = ui::Grid.new(columns: 2, item_width: 40, item_height: 40, visible_rows: 2)
    menu = group.add_node(ui::Menu.new(layout: grid))
    9.times { menu.add(ui::TextButton.new(label: 'item')) }
    root.enter_tree
    down = pressing(:ui_down)
    root.control(down)
    expect do
      4.times { root.control(down) }
    end.to allocate_nothing
  end

  it 'allocates nothing while switching tabs' do
    tabs = root.add_node(ui::Tabs.new(layout: ui::Row.new(item_width: 60, item_height: 20)))
    3.times { tabs.add(ui::TextButton.new(label: 'tab'), RGame::Engine::Node2D.new) }
    tabs.on_changed { |_page| nil }
    root.enter_tree
    following = pressing(:ui_tab_next)
    back = pressing(:ui_tab_prev)
    root.control(following)
    expect do
      root.control(following)
      root.control(back)
    end.to allocate_nothing
  end
end
