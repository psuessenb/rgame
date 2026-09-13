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

  def build(*labels)
    labels.each { |label| menu.add_item(label) }
    root.enter_tree
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
      expect(menu.items.map(&:focused?)).to eq([false, false, true, false])
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
      menu.items[0].x = 60 # (60..100, -10..10): due east of the origin
      menu.items[0].y = -10
      menu.items[1].x = -20 # centred on (0, 90): due south
      menu.items[1].y = 80
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
      root.add_node(RGame::Engine::UI::Menu.new(layout: ring, navigation: wide)).add_item('Only')
      expect(wide.index_at(0.0, -0.8)).to be_nil
    end
  end

  describe 'activation' do
    let(:chosen) { [] }

    before do
      build('N', 'E', 'S', 'W').items.each do |item|
        item.on_activated { chosen << item.label }
      end
    end

    it 'activates the focused item on confirm' do
      poll(1.0, 0.0, confirm: true)
      expect(chosen).to eq(['E'])
    end

    it 'fires once for a held confirm, not every frame' do
      3.times { poll(1.0, 0.0, confirm: true) }
      expect(chosen).to eq(['E'])
    end

    # Letting go of the stick and pressing A must not pick whatever was under
    # it last — the reason the dead zone selects nothing at all.
    it 'activates nothing when confirm is pressed after the stick has come back to centre' do
      poll(1.0, 0.0)
      poll(0.0, 0.0, confirm: true)
      expect(chosen).to be_empty
    end
  end

  describe 'a disabled item' do
    before do
      menu.add_item('N')
      menu.add_item('S', enabled: false) # two items on a ring: the second is due south
      root.enter_tree
    end

    it 'is never focused, so pointing at it selects nothing' do
      poll(0.0, 1.0)
      expect(menu.focused).to be_nil
    end

    it 'cannot be activated by pointing at it and confirming' do
      activated = false
      menu.items[1].on_activated { activated = true }
      poll(0.0, 1.0, confirm: true)
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

  it 'selects nothing with no items at all' do
    root.enter_tree
    poll(1.0, 0.0, confirm: true)
    expect(menu.focused).to be_nil
  end
end
