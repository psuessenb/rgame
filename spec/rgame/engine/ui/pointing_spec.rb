# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Pointing do
  let(:root) { RGame::Engine::Node2D.new }
  let(:pointing) { described_class.new }
  let(:menu) { root.add_node(RGame::Engine::UI::Menu.new(x: 300, y: 200, layout: ring, navigation: pointing)) }

  # One reused snapshot over hashes shifted in place, the way ActionMapper
  # builds it — `pressed?` means nothing otherwise.
  let(:snapshot) do
    held = { ui_confirm: false }
    previous = { ui_confirm: false }
    axes = { ui_radial_x: 0.0, ui_radial_y: 0.0 }
    actions = RGame::Engine::Actions.new(held: held, axes: axes, prev_held: previous)

    lambda do |x, y, confirm|
      previous[:ui_confirm] = held[:ui_confirm]
      held[:ui_confirm] = confirm
      axes[:ui_radial_x] = x
      axes[:ui_radial_y] = y
      actions
    end
  end

  def ring = RGame::Engine::UI::Ring.new(radius: 100, item_width: 40, item_height: 20)

  def button(label, **) = RGame::Engine::UI::PanelButton.new(label: label, **)

  # A menu takes no press until it has seen confirm up, so a built menu is
  # polled once at rest first.
  def build(*labels)
    labels.each { |label| menu.add(button(label)) }
    root.enter_tree
    poll(0.0, 0.0)
    menu
  end

  def poll(x, y, confirm: false) = root.control(snapshot.call(x, y, confirm))

  def label = menu.focused&.label

  it 'starts with nothing focused' do
    build('N', 'E')
    expect(menu.focused).to be_nil
  end

  describe 'selection by direction' do
    before { build('N', 'E', 'S', 'W') }

    it 'focuses nothing with the stick at rest' do
      poll(0.0, 0.0)
      expect(menu.focused).to be_nil
    end

    it 'focuses the item the stick points at' do
      poll(1.0, 0.0)
      expect(label).to eq('E')
    end

    it 'reads up as negative y, like the stick and the screen' do
      poll(0.0, -1.0)
      expect(label).to eq('N')
    end

    it 'gives each item the sector centred on it' do
      poll(-0.8, 0.9) # south-west, just on the south side of the diagonal
      expect(label).to eq('S')
    end

    it 'follows the stick from one item to another' do
      poll(1.0, 0.0)
      poll(-1.0, 0.0)
      expect(label).to eq('W')
    end

    it 'marks only the focused item as focused' do
      poll(0.0, 1.0)
      expect(menu.buttons.map(&:focused?)).to eq([false, false, true, false])
    end

    it 'maps a diagonal on the edge of two sectors to one of them rather than neither' do
      expect(pointing.index_at(1.0, 1.0)).to eq(1).or eq(2)
    end

    it 'wraps round the back of the circle, where the angle jumps' do
      expect(pointing.index_at(-1.0, -0.01)).to eq(3)
    end
  end

  # The angles come from where the items are, not from a convention it shares
  # with Ring — so a layout that is not a ring cannot disagree with it.
  describe 'items it did not place' do
    it 'points at wherever an item actually is' do
      build('A', 'B')
      menu.buttons[0].x = 60 # (60..100, -10..10): due east of the origin
      menu.buttons[0].y = -10
      menu.buttons[1].x = -20 # centred on (0, 90): due south
      menu.buttons[1].y = 80
      expect([pointing.index_at(1.0, 0.0), pointing.index_at(0.0, 1.0)]).to eq([0, 1])
    end
  end

  describe 'the dead zone' do
    before { build('N', 'E', 'S', 'W') }

    it 'selects nothing for a deflection shorter than the dead zone' do
      poll(0.3, 0.3)
      expect(menu.focused).to be_nil
    end

    it 'measures the combined vector, not each axis on its own' do
      poll(0.4, 0.4)
      expect(label).to eq('E').or eq('S')
    end

    it 'drops the selection when the stick returns to centre' do
      poll(1.0, 0.0)
      poll(0.0, 0.0)
      expect(menu.focused).to be_nil
    end

    it 'can be set per navigation' do
      wide = described_class.new(dead_zone: 0.9)
      root.add_node(RGame::Engine::UI::Menu.new(layout: ring, navigation: wide)).add(button('Only'))
      expect(wide.index_at(0.0, -0.8)).to be_nil
    end
  end

  describe 'activation' do
    let(:chosen) { [] }

    before do
      build('N', 'E', 'S', 'W').buttons.each do |button|
        button.on_activated { chosen << button.label }
      end
    end

    it 'activates the focused item when confirm is let go' do
      poll(1.0, 0.0, confirm: true)
      poll(1.0, 0.0)
      expect(chosen).to eq(['E'])
    end

    it 'fires once for a held confirm, not every frame' do
      3.times { poll(1.0, 0.0, confirm: true) }
      poll(1.0, 0.0)
      expect(chosen).to eq(['E'])
    end

    # Pointing somewhere else while holding confirm moves focus, and moving focus
    # cancels a press that has not been let go.
    it 'activates nothing when the stick moves to another button while confirm is held' do
      poll(1.0, 0.0, confirm: true)
      poll(0.0, 1.0, confirm: true)
      poll(0.0, 1.0)
      expect(chosen).to be_empty
    end

    # Letting go of the stick and pressing A must not pick whatever was under
    # it last — the reason the dead zone selects nothing at all.
    it 'activates nothing when confirm is pressed after the stick has come back to centre' do
      poll(1.0, 0.0)
      poll(0.0, 0.0, confirm: true)
      poll(0.0, 0.0)
      expect(chosen).to be_empty
    end
  end

  describe 'a disabled item' do
    before do
      menu.add(button('N'))
      menu.add(button('S', enabled: false)) # two items on a ring: the second is due south
      root.enter_tree
      poll(0.0, 0.0)
    end

    it 'is never focused, so pointing at it selects nothing' do
      poll(0.0, 1.0)
      expect(menu.focused).to be_nil
    end

    it 'cannot be activated by pointing at it and confirming' do
      activated = false
      menu.buttons[1].on_activated { activated = true }
      poll(0.0, 1.0, confirm: true)
      poll(0.0, 1.0)
      expect(activated).to be(false)
    end
  end

  describe 'the aim' do
    before { build('N', 'E') }

    it 'keeps the last vector read, for a game drawing a pointer' do
      poll(0.25, -0.5)
      expect([pointing.aim_x, pointing.aim_y]).to eq([0.25, -0.5])
    end
  end

  describe 'grace' do
    let(:pointing) { described_class.new(grace: 0.15) }

    # One tick: control, then update, as the loop runs them.
    def tick(x, y, dt: 0.05)
      poll(x, y)
      root.update(dt)
    end

    before { build('N', 'E', 'S', 'W') }

    it 'is 0.0 when built with nothing said and no trigger, so focus clears at once' do
      plain = described_class.new
      root.add_node(RGame::Engine::UI::Menu.new(layout: ring, navigation: plain))
      expect(plain.grace).to eq(0.0)
    end

    it 'is GRACE when built with nothing said on a menu with a trigger, which is chosen by letting go' do
      held = described_class.new
      RGame::Engine::UI::Menu.new(layout: ring, navigation: held, trigger: :quick)
      expect(held.grace).to eq(described_class::GRACE)
    end

    it 'keeps an explicit value' do
      expect(pointing.grace).to eq(0.15)
    end

    it 'keeps an explicit 0.0 on a menu with a trigger' do
      none = described_class.new(grace: 0.0)
      RGame::Engine::UI::Menu.new(layout: ring, navigation: none, trigger: :quick)
      expect(none.grace).to eq(0.0)
    end

    it 'keeps focus while the stick has been at rest for less than the window' do
      tick(1.0, 0.0)
      2.times { tick(0.0, 0.0) } # at rest for 0.0, then 0.05 s, when control reads it
      poll(0.0, 0.0)             # 0.1 s
      expect(label).to eq('E')
    end

    it 'clears focus once the window has run out' do
      tick(1.0, 0.0)
      4.times { tick(0.0, 0.0) } # 0.2 s at rest by the next control
      poll(0.0, 0.0)
      expect(menu.focused).to be_nil
    end

    it 'counts time only in update, so reading the stick again and again runs nothing out' do
      tick(1.0, 0.0)
      20.times { poll(0.0, 0.0) }
      expect(label).to eq('E')
    end

    it 'starts a full window again after the stick leaves the dead zone' do
      tick(1.0, 0.0)
      2.times { tick(0.0, 0.0) } # 0.1 s used
      tick(0.0, 1.0)             # pointing at S restarts it
      2.times { tick(0.0, 0.0) }
      poll(0.0, 0.0)             # 0.1 s into the new window, not 0.2 s into the old one
      expect(label).to eq('S')
    end

    it 'does not run while the menu is paused' do
      tick(1.0, 0.0)
      tick(0.0, 0.0)
      menu.paused = true
      root.update(10.0)
      menu.paused = false
      poll(0.0, 0.0)
      expect(label).to eq('E')
    end

    it 'does not keep focus on a disabled button the stick moves on to' do
      menu.buttons[2].enabled = false
      tick(1.0, 0.0)
      poll(0.0, 1.0) # S, disabled
      expect(menu.focused).to be_nil
    end

    it 'lets a confirm inside the window activate what was pointed at' do
      chosen = []
      menu.buttons[1].on_activated { chosen << :east }
      tick(1.0, 0.0)
      tick(0.0, 0.0)
      poll(0.0, 0.0, confirm: true)
      poll(0.0, 0.0)
      expect(chosen).to eq([:east])
    end

    it 'costs nothing, pointing and resting in turn' do
      held = { ui_confirm: false }
      axes = { ui_radial_x: 0.0, ui_radial_y: 0.0 }
      actions = RGame::Engine::Actions.new(held: held, axes: axes, prev_held: held.dup)
      count = 0
      expect do
        count += 1
        axes[:ui_radial_x] = (count % 13) < 6 ? 1.0 : 0.0
        root.control(actions)
        root.update(0.016)
      end.to allocate_nothing.over(2_100).after_warmup(50)
    end
  end

  describe 'on_opened' do
    before { build('N', 'E') }

    it 'forgets the aim and focuses nothing' do
      poll(1.0, 0.0)
      pointing.on_opened
      expect([pointing.aim_x, pointing.aim_y, menu.focused]).to eq([0.0, 0.0, nil])
    end
  end

  it 'selects nothing with no items at all' do
    root.enter_tree
    poll(1.0, 0.0, confirm: true)
    expect(menu.focused).to be_nil
  end
end
