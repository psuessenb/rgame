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

  def button(label, **) = RGame::Engine::UI::PanelButton.new(label: label, **)

  def build(*labels)
    labels.each { |label| menu.add(button(label)) }
    root.enter_tree
    menu
  end

  def poll(*down) = root.control(snapshot.call(*down))

  def press(*actions)
    poll(*actions)
    poll # release, so the next press is an edge of its own
  end

  describe '#add' do
    it 'returns the button it was given' do
      given = button('One')
      expect(menu.add(given)).to be(given)
    end

    it 'makes the button a child of the menu' do
      given = menu.add(button('One'))
      expect(given.parent).to be(menu)
    end

    # The menu never builds a button, so anything it is handed has to already be
    # one — and a node that is not would otherwise sit in the list answering
    # nothing the menu asks.
    it 'refuses a node that is not a button' do
      expect { menu.add(RGame::Engine::Node2D.new) }.to raise_error(TypeError, /UI::Button/)
    end

    it 'refuses a label passed where a button belongs' do
      expect { menu.add('Resume') }.to raise_error(TypeError, /UI::Button/)
    end

    it 'adds nothing it refused' do
      begin
        menu.add('Resume')
      rescue TypeError
        nil
      end
      expect([menu.buttons, menu.children]).to eq([[], []])
    end
  end

  # A game's own look is a Button subclass with an on_draw, and the menu treats
  # it exactly as it treats a shipped one.
  describe 'a button written by the game' do
    before do
      swatch = Class.new(RGame::Engine::UI::Button) do
        def on_draw(renderer, _view)
          renderer.rect(0, 0, width, height, color: state == :focused ? [255, 255, 255] : [0, 0, 0])
        end
      end
      2.times { menu.add(swatch.new) }
      root.enter_tree
    end

    it 'is focused by the navigation' do
      press(:ui_down)
      expect(menu.buttons.map(&:state)).to eq(%i[idle focused])
    end

    it 'is activated on confirm' do
      fired = false
      menu.buttons.first.on_activated { fired = true }
      press(:ui_confirm)
      expect(fired).to be(true)
    end

    it 'draws its own look in the slot its layout gave it' do
      renderer = FakeRenderer.new
      root.draw(renderer, screen_view)
      expect(renderer.calls_to(:rect).map { |call| [call.args, call.options[:color]] })
        .to eq([[[0, 0, 200, 40], [255, 255, 255]], [[0, 0, 200, 40], [0, 0, 0]]])
    end
  end

  describe '#focus' do
    # A focus sound or animation hangs off on_focus_changed, so a menu that
    # reasserts focus every frame must not replay it.
    it 'tells only the buttons whose focus changed' do
      counting = Class.new(RGame::Engine::UI::Button) do
        def changes = @changes ||= []
        def on_focus_changed(focused) = changes << focused
      end
      buttons = Array.new(3) { menu.add(counting.new) }
      menu.focus(1)
      menu.focus(1)
      menu.focus(2)
      expect(buttons.map(&:changes)).to eq([[true, false], [true, false], [true]])
    end
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
      expect(menu.buttons.map(&:focused?)).to eq([true, false, false])
    end

    it 'tells the buttons which of them has it' do
      press(:ui_down)
      expect(menu.buttons.map(&:focused?)).to eq([false, true, false])
    end
  end

  describe 'activation' do
    it 'fires the focused item\'s signal on confirm' do
      build('One', 'Two')
      fired = nil
      menu.buttons.last.on_activated { fired = 'Two' }
      press(:ui_down)
      press(:ui_confirm)
      expect(fired).to eq('Two')
    end

    it 'does not fire an item that is merely focused' do
      build('One')
      fired = false
      menu.buttons.first.on_activated { fired = true }
      press(:ui_down)
      expect(fired).to be(false)
    end

    # An edge, not a held button: one press chooses one thing.
    it 'fires once for a press that is held' do
      build('One')
      count = 0
      menu.buttons.first.on_activated { count += 1 }
      2.times { poll(:ui_confirm) }
      expect(count).to eq(1)
    end
  end

  describe 'disabled items' do
    it 'skips one when moving down' do
      menu.add(button('One'))
      menu.add(button('Two', enabled: false))
      menu.add(button('Three'))
      root.enter_tree
      press(:ui_down)
      expect(menu.focused.label).to eq('Three')
    end

    it 'does not start on one' do
      menu.add(button('One', enabled: false))
      menu.add(button('Two'))
      root.enter_tree
      expect(menu.focused.label).to eq('Two')
    end

    it 'cannot be activated even if focus somehow reaches it' do
      disabled = menu.add(button('One', enabled: false))
      fired = false
      disabled.on_activated { fired = true }
      expect([disabled.activate, fired]).to eq([nil, false])
    end

    it 'leaves focus alone when nothing can take it' do
      menu.add(button('One', enabled: false))
      root.enter_tree
      press(:ui_down)
      expect(menu.focused.label).to eq('One')
    end
  end

  describe 'layout' do
    it 'places items where its layout says' do
      build('One', 'Two', 'Three')
      expect(menu.buttons.map(&:y)).to eq([0, 48, 96])
    end

    it 'gives them the size its layout says' do
      build('One')
      expect([menu.buttons.first.width, menu.buttons.first.height]).to eq([200, 40])
    end

    it 'can be a ring as well as a column' do
      ring = RGame::Engine::UI::Ring.new(radius: 100, item_width: 40, item_height: 20)
      wheel = root.add_node(described_class.new(layout: ring))
      %w[N E S W].each { |label| wheel.add(button(label)) }
      expect(wheel.buttons.map { |item| [item.x.round, item.y.round] })
        .to eq([[-20, -110], [80, -10], [-20, 90], [-120, -10]])
    end
  end

  # Confirming belongs to the menu whatever moves focus, so a navigation only
  # has to say which item is focused.
  describe 'navigation' do
    let(:first_enabled) do
      Class.new(RGame::Engine::UI::Navigation) do
        def on_control(_actions) = menu.focus(menu.buttons.index(&:enabled?))
      end
    end

    it 'steps by default' do
      expect(menu.navigation).to be_a(RGame::Engine::UI::Stepping)
    end

    it 'activates what any navigation focused, on confirm' do
      custom = root.add_node(described_class.new(layout: column, navigation: first_enabled.new))
      custom.add(button('Off', enabled: false))
      fired = nil
      custom.add(button('On')).on_activated { fired = 'On' }
      root.enter_tree
      press(:ui_confirm)
      expect(fired).to eq('On')
    end

    it 'activates nothing when the navigation focuses nothing' do
      nothing = Class.new(RGame::Engine::UI::Navigation) { def on_control(_actions) = menu.focus(nil) }
      custom = root.add_node(described_class.new(layout: column, navigation: nothing.new))
      fired = false
      custom.add(button('One')).on_activated { fired = true }
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
      menu.add(button('Back'))
      option = menu.add(RGame::Engine::UI::OptionButton.new(label: 'Volume', values: [0, 50, 100], index: 1))
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
      menu.add(button('Back'))
      root.enter_tree
      expect { press(:ui_right) }.not_to raise_error
    end

    it 'stacks an option row like any other' do
      menu.add(button('Back'))
      menu.add(RGame::Engine::UI::OptionButton.new(label: 'Volume', values: [0, 100]))
      root.enter_tree
      expect(menu.buttons.map(&:y)).to eq([0, 48])
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
      [one, two].each { |m| labels.each { |label| m.add(button(label)) } }
      root.enter_tree

      backend = FakeInputBackend.new
      backend.hold(RGame::Util::Controls::PAD_DPAD_DOWN, device: RGame::Util::Controls.gamepad(0))
      players.poll(backend)
      root.control(players)

      expect([one.focused.label, two.focused.label]).to eq(%w[A B])
    end
  end
end
