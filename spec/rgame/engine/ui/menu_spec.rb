# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Menu do
  let(:root) { RGame::Engine::Node2D.new }
  let(:column) { RGame::Engine::UI::Column.new(item_width: 200, item_height: 40) }
  let(:menu) { root.add_node(described_class.new(layout: column)) }
  # One reused snapshot over hashes shifted in place, which is how ActionMapper
  # builds the real thing — and the only way `pressed?` means anything, since it
  # compares this frame against the last.
  #
  # Every action a menu reads is declared, down or not: Actions answers only for
  # what it was given, which is the point of it being strict.
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

  def build(*labels)
    labels.each { |label| menu.add_item(label) }
    root.enter_tree
    menu
  end

  def poll(*down) = root.control(snapshot.call(*down))

  def press(*actions)
    poll(*actions)
    poll # release, so the next press is an edge of its own
  end

  describe 'focus' do
    before { build('One', 'Two', 'Three') }

    it 'starts on the first item' do
      expect(menu.focused.label).to eq('One')
    end

    it 'moves down' do
      press(:ui_down)
      expect(menu.focused.label).to eq('Two')
    end

    it 'moves up' do
      press(:ui_down)
      press(:ui_up)
      expect(menu.focused.label).to eq('One')
    end

    # A short vertical list is quicker to use when the ends join, and every
    # console menu does it.
    it 'wraps past the end' do
      3.times { press(:ui_down) }
      expect(menu.focused.label).to eq('One')
    end

    it 'wraps before the start' do
      press(:ui_up)
      expect(menu.focused.label).to eq('Three')
    end

    # Not just `focused` answering: the item has to know, or a menu that has
    # just opened draws with no highlight until the first press.
    it 'tells the first item it has focus before any input' do
      expect(menu.items.map(&:focused?)).to eq([true, false, false])
    end

    it 'tells the items which of them has it' do
      press(:ui_down)
      expect(menu.items.map(&:focused?)).to eq([false, true, false])
    end
  end

  describe 'activation' do
    it 'fires the focused item\'s signal on confirm' do
      build('One', 'Two')
      fired = nil
      menu.items.last.on_activated { fired = 'Two' }
      press(:ui_down)
      press(:ui_confirm)
      expect(fired).to eq('Two')
    end

    it 'does not fire an item that is merely focused' do
      build('One')
      fired = false
      menu.items.first.on_activated { fired = true }
      press(:ui_down)
      expect(fired).to be(false)
    end

    # An edge, not a held button: one press chooses one thing.
    it 'fires once for a press that is held' do
      build('One')
      count = 0
      menu.items.first.on_activated { count += 1 }
      2.times { poll(:ui_confirm) }
      expect(count).to eq(1)
    end
  end

  describe 'disabled items' do
    it 'skips one when moving down' do
      menu.add_item('One')
      menu.add_item('Two', enabled: false)
      menu.add_item('Three')
      root.enter_tree
      press(:ui_down)
      expect(menu.focused.label).to eq('Three')
    end

    it 'does not start on one' do
      menu.add_item('One', enabled: false)
      menu.add_item('Two')
      root.enter_tree
      expect(menu.focused.label).to eq('Two')
    end

    it 'cannot be activated even if focus somehow reaches it' do
      item = menu.add_item('One', enabled: false)
      fired = false
      item.on_activated { fired = true }
      expect([item.activate, fired]).to eq([nil, false])
    end

    it 'leaves focus alone when nothing can take it' do
      menu.add_item('One', enabled: false)
      root.enter_tree
      press(:ui_down)
      expect(menu.focused.label).to eq('One')
    end
  end

  describe 'layout' do
    it 'places items where its layout says' do
      build('One', 'Two', 'Three')
      expect(menu.items.map(&:y)).to eq([0, 48, 96])
    end

    it 'gives them the size its layout says' do
      build('One')
      expect([menu.items.first.width, menu.items.first.height]).to eq([200, 40])
    end

    it 'can be a ring as well as a column' do
      ring = RGame::Engine::UI::Ring.new(radius: 100, item_width: 40, item_height: 20)
      wheel = root.add_node(described_class.new(layout: ring))
      %w[N E S W].each { |label| wheel.add_item(label) }
      expect(wheel.items.map { |item| [item.x.round, item.y.round] })
        .to eq([[-20, -110], [80, -10], [-20, 90], [-120, -10]])
    end
  end

  # Confirming belongs to the menu whatever moves focus, so a navigation only
  # has to say which item is focused.
  describe 'navigation' do
    let(:first_enabled) do
      Class.new(RGame::Engine::UI::Navigation) do
        def on_control(_actions) = menu.focus(menu.items.index(&:enabled?))
      end
    end

    it 'steps by default' do
      expect(menu.navigation).to be_a(RGame::Engine::UI::Stepping)
    end

    it 'activates what any navigation focused, on confirm' do
      custom = root.add_node(described_class.new(layout: column, navigation: first_enabled.new))
      custom.add_item('Off', enabled: false)
      fired = nil
      custom.add_item('On').on_activated { fired = 'On' }
      root.enter_tree
      press(:ui_confirm)
      expect(fired).to eq('On')
    end

    it 'activates nothing when the navigation focuses nothing' do
      nothing = Class.new(RGame::Engine::UI::Navigation) { def on_control(_actions) = menu.focus(nil) }
      custom = root.add_node(described_class.new(layout: column, navigation: nothing.new))
      fired = false
      custom.add_item('One').on_activated { fired = true }
      root.enter_tree
      press(:ui_confirm)
      expect([custom.focused, fired]).to eq([nil, false])
    end

    # A navigation may keep state about the menu it drives, so two menus
    # sharing one would share that state without either knowing.
    it 'refuses to drive a second menu' do
      shared = RGame::Engine::UI::Stepping.new
      described_class.new(layout: column, navigation: shared)
      expect { described_class.new(layout: column, navigation: shared) }
        .to raise_error(ArgumentError, /already navigates another menu/)
    end
  end

  # Vertical belongs to the menu, horizontal to the focused row. The menu does
  # not know what kind of row it is talking to — it calls `adjust` and a plain
  # item answers nil.
  describe 'option rows' do
    def build_options
      menu.add_item('Back')
      option = menu.add_option('Volume', values: [0, 50, 100], index: 1)
      root.enter_tree
      option
    end

    it 'moves the focused row\'s value right' do
      option = build_options
      press(:ui_down)
      press(:ui_right)
      expect(option.value).to eq(100)
    end

    it 'moves it left' do
      option = build_options
      press(:ui_down)
      press(:ui_left)
      expect(option.value).to eq(0)
    end

    # Horizontal reaches exactly one row, the same way confirm does.
    it 'leaves an unfocused row alone' do
      option = build_options
      press(:ui_right)
      expect(option.value).to eq(50)
    end

    it 'does nothing when the focused row is a plain item' do
      menu.add_item('Back')
      root.enter_tree
      expect { press(:ui_right) }.not_to raise_error
    end

    it 'stacks an option row like any other' do
      menu.add_item('Back')
      menu.add_option('Volume', values: [0, 100])
      root.enter_tree
      expect(menu.items.map(&:y)).to eq([0, 48])
    end
  end

  # The whole point of doing this after ownership routing: a menu never mentions
  # players, and two of them are independent because the tree already says whose
  # input each subtree reads.
  describe 'two players, two menus' do
    let(:players) do
      RGame::Engine::Players.new(
        [RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD),
         RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0))]
      )
    end

    it 'moves only the menu belonging to the player who pressed' do
      root.add_component(players)
      one = root.add_node(RGame::Engine::PlayerLayer.new(player: players[0]))
                .add_node(described_class.new(layout: column))
      two = root.add_node(RGame::Engine::PlayerLayer.new(player: players[1]))
                .add_node(described_class.new(layout: column))
      labels = %w[A B]
      [one, two].each { |m| labels.each { |label| m.add_item(label) } }
      root.enter_tree

      backend = FakeInputBackend.new
      backend.hold(RGame::Util::Controls::PAD_DPAD_DOWN, device: RGame::Util::Controls.gamepad(0))
      players.poll(backend)
      root.control(players)

      expect([one.focused.label, two.focused.label]).to eq(%w[A B])
    end
  end
end
