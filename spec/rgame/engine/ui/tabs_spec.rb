# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Tabs do
  let(:ui) { RGame::Engine::UI }
  let(:root) { RGame::Engine::Node2D.new }
  let(:row) { ui::Row.new(item_width: 90, item_height: 20, spacing: 4) }
  let(:tabs) { root.add_node(described_class.new(layout: row)) }
  # One reused snapshot over hashes shifted in place, as ActionMapper builds it.
  let(:snapshot) do
    reads = %i[ui_up ui_down ui_left ui_right ui_confirm ui_tab_prev ui_tab_next skill1]
    held = reads.to_h { |name| [name, false] }
    previous = reads.to_h { |name| [name, false] }
    actions = RGame::Engine::Actions.new(held: held, axes: {}, prev_held: previous)

    lambda do |*down|
      held.each { |name, state| previous[name] = state }
      reads.each { |name| held[name] = down.include?(name) }
      actions
    end
  end

  # A page holding one column menu of the given labels.
  def page_of(*labels)
    page = RGame::Engine::Node2D.new
    menu = page.add_node(ui::Menu.new(layout: ui::Column.new(item_width: 80, item_height: 30)))
    labels.each { |label| menu.add(ui::TextButton.new(label: label)) }
    page
  end

  def menu_on(page) = page.children.first

  def tab(label, **) = ui::TextButton.new(label: label, **)

  def poll(*down) = root.control(snapshot.call(*down))

  def texts_drawn(node)
    renderer = FakeRenderer.new
    node.draw(renderer, nil)
    renderer.calls_to(:text).map { it.args.first }
  end

  def press(*actions)
    poll(*actions)
    poll
  end

  # Three tabs, each with a page, entered and polled once with nothing held.
  def screen(**tab_options)
    pages = %w[a b c].map do |name|
      tabs.add(tab(name, **tab_options.fetch(name.to_sym, {})), page_of("#{name}0", "#{name}1"))
    end
    root.enter_tree
    poll
    pages
  end

  describe 'switching' do
    it 'shows the next tab on ui_tab_next' do
      _a, b, = screen
      press(:ui_tab_next)
      expect(tabs.current).to be(b)
    end

    it 'wraps to the last tab on ui_tab_prev' do
      *, c = screen
      press(:ui_tab_prev)
      expect(tabs.current).to be(c)
    end

    it 'skips a disabled tab' do
      *, c = screen(b: { enabled: false })
      press(:ui_tab_next)
      expect(tabs.current).to be(c)
    end

    it 'emits on_changed with the page shown' do
      _a, b, = screen
      shown = []
      tabs.on_changed { |page| shown << page }
      press(:ui_tab_next)
      expect(shown).to eq([b])
    end

    it 'shows the page of a tab whose hotkey is pressed' do
      *, c = screen(c: { hotkey: :skill1 })
      poll
      press(:skill1)
      expect(tabs.current).to be(c)
    end

    it 'marks the tab shown as focused' do
      screen
      press(:ui_tab_next)
      expect(tabs.children.first.buttons.map(&:focused?)).to eq([false, true, false])
    end
  end

  describe 'the first page' do
    it 'is the first tab\'s' do
      a, = screen
      expect(tabs.current).to be(a)
    end

    it 'is the first enabled tab\'s' do
      _a, b, = screen(a: { enabled: false })
      expect(tabs.current).to be(b)
    end

    it 'is nil before any tab' do
      expect(tabs.current).to be_nil
    end
  end

  describe 'pages' do
    it 'starts a page under the bar' do
      a, = screen
      expect(a.world_y).to eq(20)
    end

    it 'lists the pages in the order their tabs were added' do
      expect(screen).to eq(tabs.pages)
    end

    it 'returns the page from add' do
      page = RGame::Engine::Node2D.new
      expect(tabs.add(tab('p'), page)).to be(page)
    end

    it 'refuses a page that is not a node' do
      expect { tabs.add(tab('p'), :page) }.to raise_error(TypeError, /Node2D/)
    end

    it 'refuses a page it already holds' do
      page = tabs.add(tab('p'), RGame::Engine::Node2D.new)
      expect { tabs.add(tab('q'), page) }.to raise_error(ArgumentError, /already/)
    end

    it 'follows the tabs when they move' do
      a, = screen
      a.world_y
      tabs.x = 50
      expect(a.world_x).to eq(50)
    end
  end

  describe 'the page shown' do
    it 'is the only one controlled' do
      a, b, = screen
      press(:ui_down)
      expect([menu_on(a).focused_index, menu_on(b).focused_index]).to eq([1, 0])
    end

    it 'is the only one drawn' do
      RGame::Engine::I18n.load_hash(en: %w[a b c a0 a1 b0 b1 c0 c1].to_h { [it.to_sym, it] })
      screen
      expect(texts_drawn(tabs)).to eq(%w[a b c a0 a1])
    end

    it 'keeps a hidden page\'s focus where the player left it' do
      a, = screen
      press(:ui_down)
      press(:ui_tab_next)
      press(:ui_tab_prev)
      expect(menu_on(a).focused_index).to eq(1)
    end

    # Hiding is not pausing, as closing a menu is not.
    it 'updates every page, so a hidden button\'s pressed look runs out' do
      a, = screen
      button = menu_on(a).focused
      button.activate_with_feedback
      press(:ui_tab_next)
      tabs.update(1.0)
      expect(button.pressed?).to be(false)
    end

    it 'is first controlled on the next tick' do
      _a, b, = screen
      activated = []
      menu_on(b).buttons.each { |button| button.on_activated { activated << button.label.key } }
      poll(:ui_tab_next, :ui_confirm)
      poll
      expect([tabs.current, activated]).to eq([b, []])
    end

    # The page left is earlier in the tree than the page shown, so without the
    # wait the page shown would read the same press of ui_down.
    it 'is first controlled on the next tick when the page left switches them' do
      a, b, = screen
      menu_on(a).add(tab('switch', hotkey: :skill1)).on_activated { tabs.current = b }
      poll
      poll(:skill1, :ui_down)
      poll
      expect([tabs.current, menu_on(b).focused_index]).to eq([b, 0])
    end
  end

  describe '#current=' do
    it 'shows the page' do
      *, c = screen
      tabs.current = c
      expect(tabs.current).to be(c)
    end

    it 'emits only on a change' do
      a, b, = screen
      shown = []
      tabs.on_changed { |page| shown << page }
      tabs.current = a
      tabs.current = b
      tabs.current = b
      expect(shown).to eq([b])
    end

    it 'refuses a page the tabs do not hold' do
      screen
      expect { tabs.current = RGame::Engine::Node2D.new }.to raise_error(ArgumentError, /not a page/)
    end
  end

  describe 'open and closed' do
    it 'starts open' do
      expect(tabs.open?).to be(true)
    end

    it 'draws nothing while closed' do
      screen
      tabs.close
      expect(texts_drawn(root)).to be_empty
    end

    it 'reads no input while closed' do
      a, = screen
      tabs.close
      press(:ui_tab_next)
      press(:ui_down)
      expect([tabs.current, menu_on(a).focused_index]).to eq([a, 0])
    end

    it 'still ticks while closed' do
      a, = screen
      button = menu_on(a).focused
      button.activate_with_feedback
      tabs.close
      root.update(1.0)
      expect(button.pressed?).to be(false)
    end

    it 'emits on_opened and on_closed only on a change' do
      events = []
      tabs.on_opened { events << :opened }
      tabs.on_closed { events << :closed }
      tabs.open
      tabs.close
      tabs.close
      tabs.open
      expect(events).to eq(%i[closed opened])
    end
  end

  describe 'the bar' do
    it 'activates nothing on ui_confirm' do
      a, = screen
      activated = []
      tabs.children.first.buttons.each { |button| button.on_activated { activated << button } }
      press(:ui_confirm)
      expect([activated, tabs.current]).to eq([[], a])
    end
  end

  describe 'focus groups' do
    it 'keeps the bar out of a group round the tabs' do
      group = root.add_node(ui::FocusGroup.new)
      inner = group.add_node(described_class.new(layout: row))
      inner.add(tab('a'), page_of('a0'))
      root.enter_tree
      expect([inner.children.first.group, group.menus]).to eq([nil, []])
    end

    it 'keeps a page\'s menus out of a group round the tabs' do
      group = root.add_node(ui::FocusGroup.new)
      inner = group.add_node(described_class.new(layout: row))
      page = inner.add(tab('a'), page_of('a0'))
      root.enter_tree
      expect(menu_on(page).group).to be_nil
    end

    it 'lets a page\'s menus join a group on that page' do
      own = RGame::Engine::Node2D.new
      group = own.add_node(ui::FocusGroup.new)
      menu = group.add_node(ui::Menu.new(layout: ui::Column.new(item_width: 80, item_height: 30)))
      menu.add(tab('a0'))
      tabs.add(tab('a'), own)
      root.enter_tree
      expect(menu.group).to be(group)
    end

    it 'refuses a Tabs inside another\'s page' do
      inner = described_class.new(layout: row)
      page = RGame::Engine::Node2D.new
      page.add_node(inner)
      tabs.add(tab('a'), page)
      expect { root.enter_tree }.to raise_error(ArgumentError, /another's page/)
    end
  end

  # The equipment screen's shape: a page holding a group of a scrolled grid and
  # a column of verbs.
  describe 'a page with a group of a scrolled grid and a column' do
    #   bag, two rows in view    verbs
    #   b0 b1                    v0
    #   b2 b3 ─ first_row 1 ─    v1
    #   b4 b5 ─────────────      v2
    #   b6 b7                    v3
    def bag_and_verbs
      page = RGame::Engine::Node2D.new
      group = page.add_node(ui::FocusGroup.new)
      grid = ui::Grid.new(columns: 2, item_width: 40, item_height: 40, spacing: 10, visible_rows: 2)
      bag = group.add_node(ui::Menu.new(layout: grid))
      8.times { |index| bag.add(tab("b#{index}")) }
      verbs = group.add_node(ui::Menu.new(x: 200, layout: ui::Column.new(item_width: 80, item_height: 40, spacing: 10)))
      4.times { |index| verbs.add(tab("v#{index}")) }
      tabs.add(tab('items'), page)
      tabs.add(tab('keys'), page_of('k0', 'k1'))
      root.enter_tree
      poll
      [group, bag, verbs]
    end

    def walk(*steps) = steps.each { press(it) }

    it 'scrolls the grid as focus steps down it' do
      _group, bag, = bag_and_verbs
      walk(:ui_down, :ui_down)
      expect([bag.focused_index, bag.first_row]).to eq([4, 1])
    end

    it 'crosses from the grid to the verb nearest the button left' do
      group, _bag, verbs = bag_and_verbs
      walk(:ui_down, :ui_down, :ui_right, :ui_right)
      expect([group.current, verbs.focused_index]).to eq([verbs, 1])
    end

    # From v3 the nearest slot is b7, below the window; the nearest in view is b5.
    it 'crosses back to the nearest slot in view, and scrolls nothing' do
      group, bag, = bag_and_verbs
      walk(:ui_down, :ui_down, :ui_right, :ui_right, :ui_down, :ui_down, :ui_left)
      expect([group.current, bag.focused_index, bag.first_row]).to eq([bag, 5, 1])
    end

    it 'keeps focus and scroll where they were across a switch away and back' do
      group, bag, = bag_and_verbs
      walk(:ui_down, :ui_down, :ui_right)
      walk(:ui_tab_next, :ui_down, :ui_tab_prev)
      expect([group.current, bag.focused_index, bag.first_row]).to eq([bag, 5, 1])
    end
  end

  describe 'two players' do
    it 'switches each player\'s own tabs' do
      players = RGame::Engine::Players.new(
        [RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD),
         RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0))]
      )
      root.add_component(players)
      screens = players.to_a.map do |player|
        layer = root.add_node(RGame::Engine::PlayerLayer.new(player: player))
        own = layer.add_node(described_class.new(layout: row))
        [own, own.add(tab('a'), page_of('a0')), own.add(tab('b'), page_of('b0'))]
      end
      root.enter_tree
      backend = FakeInputBackend.new
      [0, 1].each do |tick|
        backend.hold(RGame::Util::Controls::PAD_RIGHT_SHOULDER, device: RGame::Util::Controls.gamepad(0)) if tick == 1
        players.poll(backend, 0.016)
        root.control(players)
      end
      (one, one_a,), (two, _two_a, two_b) = screens
      expect([one.current, two.current]).to eq([one_a, two_b])
    end
  end
end
