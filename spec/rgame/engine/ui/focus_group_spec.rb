# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::FocusGroup do
  let(:ui) { RGame::Engine::UI }
  let(:root) { RGame::Engine::Node2D.new }
  let(:group) { root.add_node(described_class.new) }
  # One reused snapshot over hashes shifted in place, as ActionMapper builds it.
  let(:snapshot) do
    reads = %i[ui_up ui_down ui_left ui_right ui_confirm skill1]
    held = reads.to_h { |name| [name, false] }
    previous = reads.to_h { |name| [name, false] }
    actions = RGame::Engine::Actions.new(held: held, axes: {}, prev_held: previous)

    lambda do |*down|
      held.each { |name, state| previous[name] = state }
      reads.each { |name| held[name] = down.include?(name) }
      actions
    end
  end

  # The bag is a two-column grid and the verbs a column to its right:
  #
  #   b0 b1        v0
  #   b2 b3        v1
  #                v2
  def bag_at(parent = group, x: 0, y: 0, count: 4)
    grid = ui::Grid.new(columns: 2, item_width: 40, item_height: 40, spacing: 10)
    menu = parent.add_node(ui::Menu.new(x: x, y: y, layout: grid))
    count.times { |index| menu.add(ui::TextButton.new(label: "b#{index}")) }
    menu
  end

  def verbs_at(parent = group, x: 200, y: 0, labels: %w[v0 v1 v2])
    column = ui::Column.new(item_width: 80, item_height: 40, spacing: 10)
    menu = parent.add_node(ui::Menu.new(x: x, y: y, layout: column))
    labels.each { |label| menu.add(ui::TextButton.new(label: label)) }
    menu
  end

  def poll(*down) = root.control(snapshot.call(*down))

  def press(*actions)
    poll(*actions)
    poll
  end

  def focused_label(menu) = menu.focused&.label&.key

  # Built, entered, and polled once with nothing held: a menu takes no confirm
  # until it has seen confirm up.
  def screen
    bag = bag_at
    verbs = verbs_at
    root.enter_tree
    poll
    [bag, verbs]
  end

  describe 'one menu reads' do
    it 'moves focus only in the current menu' do
      bag, verbs = screen
      press(:ui_down)
      expect([focused_label(bag), focused_label(verbs)]).to eq(['b2', nil])
    end

    # The measured case: two open menus under one owner each activated a button
    # on one press of confirm.
    it 'activates one button on one press of confirm' do
      bag, verbs = screen
      activated = []
      [bag, verbs].each { |menu| menu.buttons.each { |button| button.on_activated { activated << button } } }
      press(:ui_confirm)
      expect(activated.map { it.label.key }).to eq(['b0'])
    end

    it 'presses no hotkey of a menu that is not current' do
      _bag, verbs = screen
      button = verbs.add(ui::TextButton.new(label: 'hot', hotkey: :skill1))
      activated = 0
      button.on_activated { activated += 1 }
      poll
      press(:skill1)
      expect(activated).to eq(0)
    end

    it 'leaves every other menu with nothing focused' do
      _bag, verbs = screen
      expect([verbs.focused, verbs.buttons.any?(&:focused?)]).to eq([nil, false])
    end
  end

  describe '#current' do
    it 'starts on the first menu to join that is open and has an enabled button' do
      bag, = screen
      expect(group.current).to be(bag)
    end

    it 'passes over a closed menu' do
      bag_at.close
      verbs = verbs_at
      root.enter_tree
      expect(group.current).to be(verbs)
    end

    it 'passes over a menu with no enabled button' do
      bag = bag_at
      bag.buttons.each { it.enabled = false }
      verbs = verbs_at
      root.enter_tree
      expect(group.current).to be(verbs)
    end

    it 'is nil while no menu has an enabled button' do
      verbs_at.buttons.each { it.enabled = false }
      root.enter_tree
      expect(group.current).to be_nil
    end

    it 'lists the menus in the order they joined' do
      bag, verbs = screen
      expect(group.menus).to eq([bag, verbs])
    end

    it 'counts a menu wrapped in a plain node' do
      panel = group.add_node(RGame::Engine::Node2D.new)
      verbs = verbs_at(panel)
      root.enter_tree
      expect([verbs.group, group.current]).to eq([group, verbs])
    end
  end

  describe 'the check each tick' do
    it 'hands over from a current menu that closed to the first that qualifies' do
      bag, verbs = screen
      bag.close
      poll
      expect([group.current, focused_label(verbs)]).to eq([verbs, 'v0'])
    end

    it 'hands over from a current menu whose buttons were all disabled' do
      bag, verbs = screen
      bag.buttons.each { it.enabled = false }
      poll
      expect(group.current).to be(verbs)
    end

    it 'hands over from a current menu that left the tree' do
      bag, verbs = screen
      group.remove_node(bag)
      poll
      expect([group.current, group.menus, bag.group]).to eq([verbs, [verbs], nil])
    end

    it 'finds the first menu to qualify once none did' do
      verbs = verbs_at
      verbs.buttons.each { it.enabled = false }
      root.enter_tree
      poll
      verbs.buttons.last.enabled = true
      poll
      expect([group.current, focused_label(verbs)]).to eq([verbs, 'v2'])
    end
  end

  describe 'a change of current' do
    it 'clears the focus of the menu left' do
      bag, verbs = screen
      group.current = verbs
      expect([bag.focused, bag.buttons.any?(&:focused?)]).to eq([nil, false])
    end

    it 'focuses the enabled button nearest the one left' do
      bag, verbs = screen
      bag.focus(3)
      group.current = verbs
      expect(focused_label(verbs)).to eq('v1')
    end

    it 'passes over a disabled button nearer the one left' do
      bag, verbs = screen
      verbs.buttons[1].enabled = false
      bag.focus(3)
      group.current = verbs
      expect(focused_label(verbs)).to eq('v0')
    end

    it 'lets the menu entered read from the next tick' do
      _bag, verbs = screen
      group.current = verbs
      press(:ui_down)
      expect(focused_label(verbs)).to eq('v1')
    end

    # Right crosses from the end of the bag's first row; the down pressed with it
    # reaches neither menu.
    it 'reads no more input in either menu on the tick it crossed' do
      bag, verbs = screen
      press(:ui_right)
      press(:ui_right, :ui_down)
      expect([focused_label(bag), focused_label(verbs)]).to eq([nil, 'v0'])
    end

    it 'presses no hotkey in the menu left on the tick it crossed' do
      bag, = screen
      hot = bag.add(ui::TextButton.new(label: 'hot', hotkey: :skill1))
      activated = 0
      hot.on_activated { activated += 1 }
      poll
      press(:ui_right)
      press(:ui_right, :skill1)
      expect(activated).to eq(0)
    end

    it 'activates nothing with a confirm pressed on the tick it crossed' do
      bag, verbs = screen
      activated = 0
      [bag, verbs].each { |menu| menu.buttons.each { it.on_activated { activated += 1 } } }
      press(:ui_right)
      press(:ui_right, :ui_confirm)
      expect(activated).to eq(0)
    end

    # The verbs saw confirm up while they were current before. Entering again
    # starts that wait over, so a confirm on their first tick back is refused.
    it 'takes no confirm in the menu entered until it has seen confirm up' do
      bag, verbs = screen
      group.current = verbs
      poll
      group.current = bag
      poll
      group.current = verbs
      activated = 0
      verbs.buttons.each { it.on_activated { activated += 1 } }
      press(:ui_confirm)
      press(:ui_confirm)
      expect(activated).to eq(1)
    end
  end

  describe 'crossing' do
    it 'crosses to the neighbour past the end of a row' do
      _bag, verbs = screen
      press(:ui_right)
      press(:ui_right)
      expect([group.current, focused_label(verbs)]).to eq([verbs, 'v0'])
    end

    it 'wraps inside the line when no neighbour lies that way' do
      _bag, verbs = screen
      group.current = verbs
      poll
      press(:ui_up)
      expect([group.current, focused_label(verbs)]).to eq([verbs, 'v2'])
    end

    it 'counts the end of a line from the last enabled button before it' do
      bag, verbs = screen
      bag.buttons[1].enabled = false
      press(:ui_right)
      expect([group.current, focused_label(verbs)]).to eq([verbs, 'v0'])
    end

    it 'crosses on a direction a plain button does not adjust' do
      bag, verbs = screen
      group.current = verbs
      poll
      press(:ui_down)
      press(:ui_left)
      expect([group.current, focused_label(bag)]).to eq([bag, 'b3'])
    end

    it 'moves nothing on a direction with no neighbour that the button does not adjust' do
      _bag, verbs = screen
      group.current = verbs
      poll
      press(:ui_right)
      expect([group.current, focused_label(verbs)]).to eq([verbs, 'v0'])
    end

    it 'adjusts an OptionButton instead, even at the end of its values' do
      bag = bag_at
      verbs = verbs_at(labels: [])
      option = verbs.add(ui::OptionButton.new(label: 'volume', values: [0, 1]))
      root.enter_tree
      poll
      group.current = verbs
      poll
      press(:ui_left)
      press(:ui_right)
      expect([group.current, option.value, bag.focused]).to eq([verbs, 1, nil])
    end

    it 'adjusts a game\'s button that overrides adjust' do
      slider = Class.new(ui::Button) do
        attr_reader :moved

        def adjust(delta) = @moved = delta
      end
      verbs = verbs_at(labels: [])
      button = verbs.add(slider.new)
      bag_at
      root.enter_tree
      poll
      press(:ui_left)
      expect([group.current, button.moved]).to eq([verbs, -1])
    end

    it 'lands on the nearest button of a column below a grid, not the one after it' do
      bag = bag_at
      verbs = verbs_at(x: 0, y: 150)
      root.enter_tree
      poll
      bag.focus(2)
      press(:ui_down)
      expect([group.current, focused_label(verbs)]).to eq([verbs, 'v0'])
    end

    it 'lands on the nearest button of a grid right of a column, not the one after it' do
      verbs_at(x: 0)
      bag = bag_at(x: 200)
      root.enter_tree
      poll
      press(:ui_right)
      expect([group.current, focused_label(bag)]).to eq([bag, 'b0'])
    end

    it 'crosses back into the menu the tree controls first, on the nearest button' do
      bag, verbs = screen
      group.current = verbs
      poll
      press(:ui_left)
      expect([group.current, focused_label(bag)]).to eq([bag, 'b1'])
    end
  end

  describe '#cross' do
    it 'answers false and changes nothing with no neighbour that way' do
      bag, = screen
      expect([group.cross(:up), group.current]).to eq([false, bag])
    end

    it 'answers true when it crossed' do
      _bag, verbs = screen
      expect([group.cross(:right), group.current]).to eq([true, verbs])
    end

    it 'takes the nearest menu beyond the edge' do
      bag_at
      verbs_at(x: 300)
      near = verbs_at(x: 150)
      root.enter_tree
      group.cross(:right)
      expect(group.current).to be(near)
    end

    it 'breaks a tie on the gap by the distance between centres across it' do
      bag_at
      verbs_at(y: 200)
      level = verbs_at(y: 0)
      root.enter_tree
      group.cross(:right)
      expect(group.current).to be(level)
    end

    it 'passes over a menu that overlaps the current one\'s edge' do
      bag_at
      verbs_at(x: 60)
      beyond = verbs_at(x: 300)
      root.enter_tree
      group.cross(:right)
      expect(group.current).to be(beyond)
    end

    it 'passes over a closed menu between two open ones' do
      bag_at
      verbs_at(x: 150).close
      beyond = verbs_at(x: 300)
      root.enter_tree
      group.cross(:right)
      expect(group.current).to be(beyond)
    end

    it 'passes over a menu with no enabled button' do
      bag_at
      verbs_at(x: 150).buttons.each { it.enabled = false }
      beyond = verbs_at(x: 300)
      root.enter_tree
      group.cross(:right)
      expect(group.current).to be(beyond)
    end

    it 'refuses a direction it does not know' do
      expect { group.cross(:forward) }.to raise_error(ArgumentError, /:left, :right, :up, :down/)
    end
  end

  describe 'Menu#focus' do
    it 'makes a menu that is not current current, on the button asked for' do
      bag, verbs = screen
      verbs.focus(2)
      expect([group.current, focused_label(verbs), bag.focused]).to eq([verbs, 'v2', nil])
    end

    it 'changes nothing for nil on a menu that is not current' do
      bag, verbs = screen
      verbs.focus(nil)
      expect([group.current, focused_label(bag)]).to eq([bag, 'b0'])
    end

    it 'focuses nothing when buttons are added to a menu that is not current' do
      _bag, verbs = screen
      verbs.clear.add(ui::TextButton.new(label: 'again'))
      expect(verbs.focused).to be_nil
    end
  end

  describe '#current=' do
    it 'refuses a menu outside the group' do
      stray = root.add_node(ui::Menu.new(layout: ui::Column.new(item_width: 10, item_height: 10)))
      expect { group.current = stray }.to raise_error(ArgumentError, /not a menu in this FocusGroup/)
    end
  end

  describe 'the menus it refuses' do
    it 'refuses a menu with a trigger as it joins' do
      group.add_node(ui::Menu.new(layout: ui::Column.new(item_width: 10, item_height: 10), trigger: :quick_menu))
      expect { root.enter_tree }.to raise_error(ArgumentError, /trigger: :quick_menu/)
    end

    it 'refuses a DialogueBox as its menu joins' do
      RGame::Engine::I18n.load_hash(en: { speakers: { smith: 'Smith' }, hello: 'Hello.' })
      script = RGame::Engine::Dialogue::Script.build(start: :hello) do
        beat :hello, speaker: :smith, line: 'hello'
      end
      group.add_node(ui::DialogueBox.new(dialogue: RGame::Engine::Dialogue.new(script), unavailable: :hide,
                                         width: 300))
      expect { root.enter_tree }.to raise_error(ArgumentError, /DialogueBox/)
    end

    it 'refuses a menu answering to another player' do
      one = RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD)
      two = RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0))
      group.input_owner = one
      verbs_at.input_owner = two
      expect { root.enter_tree }.to raise_error(ArgumentError, /another player/)
    end

    it 'takes a menu that names the group\'s own player' do
      one = RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD)
      group.input_owner = one
      verbs = verbs_at
      verbs.input_owner = one
      root.enter_tree
      expect(verbs.group).to be(group)
    end
  end

  describe 'a menu that scrolls' do
    # A list of eight right of the verbs, two rows in view and scrolled to
    # rows 2 and 3. From v2 the nearest button is 4, below the window; the
    # nearest in view is 3.
    it 'lands a crossing on the nearest enabled button in view' do
      column = ui::Column.new(item_width: 80, item_height: 40, spacing: 10, visible_rows: 2)
      list = group.add_node(ui::Menu.new(x: 200, layout: column))
      8.times { |index| list.add(ui::TextButton.new(label: "l#{index}")) }
      verbs = verbs_at(x: 0)
      root.enter_tree
      poll
      list.focus(3)
      verbs.focus(2)
      press(:ui_right)
      expect([focused_label(list), list.first_row]).to eq(['l3', 2])
    end
  end

  describe 'two players' do
    let(:players) do
      RGame::Engine::Players.new(
        [RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD),
         RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0))]
      )
    end

    it 'moves each player in their own group' do
      root.add_component(players)
      screens = players.to_a.map do |player|
        layer = root.add_node(RGame::Engine::PlayerLayer.new(player: player))
        own = layer.add_node(described_class.new)
        [bag_at(own), verbs_at(own)]
      end
      root.enter_tree
      backend = FakeInputBackend.new
      [0, 1].each do |tick|
        backend.hold(RGame::Util::Controls::PAD_DPAD_RIGHT, device: RGame::Util::Controls.gamepad(0)) if tick == 1
        players.poll(backend, 0.016)
        root.control(players)
      end
      (one_bag, one_verbs), (two_bag, two_verbs) = screens
      expect([one_bag.group.current, focused_label(one_bag), two_bag.group.current, focused_label(two_bag)])
        .to eq([one_bag, 'b0', two_bag, 'b1'])
      expect([one_verbs.focused, two_verbs.focused]).to eq([nil, nil])
    end
  end
end
