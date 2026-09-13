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

  # A menu takes no press until it has seen confirm up, so a built menu is
  # polled once with nothing held — it has been on screen for a frame.
  def build(*labels)
    labels.each { |label| menu.add(button(label)) }
    root.enter_tree
    poll
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
      poll
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

  # The menu never asks what kind of button it holds, so one of each — shipped
  # on art, shipped on shapes, shipped on an image, and the game's own — sit in
  # one list, step, and draw in their own slots.
  # rubocop:disable RSpec/MultipleMemoizedHelpers -- four are the file's own menu and input;
  # the other two are the art every kind of button in it needs registered.
  describe 'buttons of every kind in one menu' do
    let(:slice_log) { [] }
    let(:renderer) do
      FakeRenderer.new.tap do |r|
        RGame::Engine::UI::PanelButton::STYLE.elements.each_value { |id| r.register_nine_slice(id, slice(id)) }
        r.register_image(:home, StubImage.new(50, 50))
      end
    end

    def slice(id)
      log = slice_log
      Class.new { define_method(:draw) { |*, **| log << id } }.new
    end

    before do
      swatch = Class.new(RGame::Engine::UI::Button) do
        def on_draw(renderer, _view)
          renderer.rect(0, 0, width, height, color: state == :focused ? [255, 255, 255] : [0, 0, 0])
        end
      end
      menu.add(button('Resume'))
      menu.add(RGame::Engine::UI::TextButton.new(label: 'Options'))
      menu.add(RGame::Engine::UI::IconButton.new(image: :home))
      menu.add(swatch.new)
      root.enter_tree
      poll
      press(:ui_down)
      press(:ui_down)
    end

    # Each call keyed by where it lands: the y of the slot it was drawn inside.
    def by_slot
      root.draw(renderer, screen_view)
      renderer.calls.reject { |call| call.name == :translated }.group_by do |call|
        call.transforms.sum { |transform| transform.args[1] }
      end
    end

    it 'steps through all of them' do
      expect(menu.buttons.map(&:state)).to eq(%i[idle idle focused idle])
    end

    it 'draws every button in its own slot' do
      expect(by_slot.transform_values { |calls| calls.map(&:name) })
        .to eq(0 => %i[text], 48 => %i[rect text], 96 => %i[image], 144 => %i[rect])
    end

    it 'draws the panel button from its own art' do
      by_slot
      expect(slice_log).to eq([:button_idle])
    end

    it 'draws the focused one, and only that one, in its focused look' do
      slots = by_slot
      looks = [slots[48].first.options[:color], slots[96].first.options[:color], slots[144].first.options[:color]]
      expect(looks).to eq([RGame::Engine::UI::ShapeStyle::COLORS[:idle],
                           RGame::Engine::UI::IconButton::TINTS[:focused], [0, 0, 0]])
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

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
      3.times { poll(:ui_confirm) }
      poll
      expect(count).to eq(1)
    end
  end

  describe 'press and release' do
    def build_with(activate_on:)
      menu.add(button('One', activate_on: activate_on))
      menu.add(button('Two', activate_on: activate_on))
      root.enter_tree
      poll
      menu.buttons.first
    end

    def fired_on(target)
      [].tap { |log| target.on_activated { log << :fired } }
    end

    describe 'activate_on: :release' do
      it 'presses on the down tick and activates nothing yet' do
        first = build_with(activate_on: :release)
        fired = fired_on(first)
        poll(:ui_confirm)
        expect([first.state, fired]).to eq([:pressed, []])
      end

      it 'activates on the up tick' do
        first = build_with(activate_on: :release)
        fired = fired_on(first)
        poll(:ui_confirm)
        poll
        expect([first.state, fired]).to eq([:focused, [:fired]])
      end

      it 'activates nothing when focus moves while held' do
        first = build_with(activate_on: :release)
        fired = fired_on(first) + fired_on(menu.buttons.last)
        poll(:ui_confirm)
        poll(:ui_confirm, :ui_down)
        poll
        expect([first.state, fired]).to eq([:idle, []])
      end
    end

    describe 'activate_on: :press' do
      it 'activates on the down tick' do
        first = build_with(activate_on: :press)
        fired = fired_on(first)
        poll(:ui_confirm)
        expect(fired).to eq([:fired])
      end

      it 'stays pressed after a tap for PRESS_FEEDBACK, then returns to focused' do
        first = build_with(activate_on: :press)
        poll(:ui_confirm)
        poll
        states = [first.state]
        root.update(RGame::Engine::UI::Button::PRESS_FEEDBACK)
        expect(states << first.state).to eq(%i[pressed focused])
      end

      it 'stays pressed past PRESS_FEEDBACK while held, until released' do
        first = build_with(activate_on: :press)
        poll(:ui_confirm)
        root.update(RGame::Engine::UI::Button::PRESS_FEEDBACK * 2)
        poll(:ui_confirm)
        states = [first.state]
        poll
        expect(states << first.state).to eq(%i[pressed focused])
      end
    end

    it 'does not move focus' do
      build('One', 'Two')
      press(:ui_down)
      poll(:ui_confirm)
      expect(menu.focused_index).to eq(1)
    end

    # The measured double activation: a node added during control is controlled
    # later in the same traversal, so a submenu opened by a press would read
    # that same press edge.
    describe 'a menu opened by an activation' do
      def open_submenu(activate_on:)
        opener = build_with(activate_on: activate_on)
        submenu = described_class.new(layout: column)
        back = submenu.add(button('Back', activate_on: activate_on))
        fired = fired_on(back)
        opener.on_activated { root.add_node(submenu) }
        [back, fired]
      end

      it 'does not activate from the press that opened it' do
        back, fired = open_submenu(activate_on: :press)
        poll(:ui_confirm)
        expect([back.in_tree?, fired]).to eq([true, []])
      end

      it 'does not draw pressed while that key stays down' do
        back, = open_submenu(activate_on: :press)
        3.times { poll(:ui_confirm) }
        expect(back.state).to eq(:focused)
      end

      it 'does not activate on the release of that press' do
        _back, fired = open_submenu(activate_on: :press)
        poll(:ui_confirm)
        poll
        expect(fired).to eq([])
      end

      it 'does not activate from the release that opened it, under :release' do
        back, fired = open_submenu(activate_on: :release)
        poll(:ui_confirm)
        poll
        poll
        expect([back.in_tree?, back.state, fired]).to eq([true, :focused, []])
      end

      it 'answers the next press of its own' do
        _back, fired = open_submenu(activate_on: :press)
        press(:ui_confirm)
        press(:ui_confirm)
        expect(fired).to eq([:fired])
      end
    end

    # A menu that closes itself from on_activated stops being controlled and
    # updated, so it never sees that key go up. The press is dropped when the
    # menu next looks and finds the key up with no release edge.
    describe 'a menu hidden in on_activated and shown again' do
      def hide_on_activation(activate_on:)
        first = build_with(activate_on: activate_on)
        first.on_activated { menu.paused = true }
        first
      end

      it 'does not reappear pressed' do
        first = hide_on_activation(activate_on: :press)
        poll(:ui_confirm)
        poll
        menu.paused = false
        poll
        expect(first.state).to eq(:focused)
      end

      it 'does not activate again when shown' do
        first = hide_on_activation(activate_on: :press)
        fired = fired_on(first)
        poll(:ui_confirm)
        poll
        menu.paused = false
        poll
        expect(fired).to eq([:fired])
      end

      it 'is still pressed when shown while that key is still held' do
        first = hide_on_activation(activate_on: :press)
        poll(:ui_confirm)
        poll(:ui_confirm)
        menu.paused = false
        poll(:ui_confirm)
        expect(first.state).to eq(:pressed)
      end

      it 'does not activate a :release button whose release happened while hidden' do
        first = build_with(activate_on: :release)
        fired = fired_on(first)
        poll(:ui_confirm)
        menu.paused = true
        poll
        menu.paused = false
        poll
        expect([first.state, fired]).to eq([:focused, []])
      end
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

  describe 'bounds' do
    def bounds = [menu.bounds_x, menu.bounds_y, menu.bounds_width, menu.bounds_height]

    it 'has no extent while it holds no buttons' do
      expect(bounds).to eq([0, 0, 0, 0])
    end

    it 'follows each add' do
      menu.add(button('One'))
      expect { menu.add(button('Two')) }.to change { bounds }.from([0, 0, 200, 40]).to([0, 0, 200, 88])
    end

    it 'is what its layout answers' do
      menu.add(button('One'))
      menu.add(button('Two'))
      expect(bounds).to eq(column.bounds(menu.buttons))
    end

    it 'costs nothing to read' do
      build('One', 'Two')
      expect { menu.bounds_x + menu.bounds_y + menu.bounds_width + menu.bounds_height }.to allocate_nothing
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
      poll
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
