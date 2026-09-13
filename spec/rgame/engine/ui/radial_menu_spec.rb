# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::RadialMenu do
  let(:root) { RGame::Engine::Node2D.new }
  let(:menu) do
    root.add_node(described_class.new(x: 300, y: 200, radius: 100, item_width: 40, item_height: 20))
  end

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

  def build(*labels)
    labels.each { |label| menu.add_item(label) }
    root.enter_tree
    menu
  end

  def poll(x, y, confirm: false) = root.control(snapshot.call(x, y, confirm))

  def label = menu.focused&.label

  describe 'placing items on the ring' do
    before { build('N', 'E', 'S', 'W') }

    it 'puts the first item straight up, centred on the ring' do
      item = menu.items.first
      expect([item.world_x + 20, item.world_y + 10]).to eq([300, 100])
    end

    it 'goes clockwise, so the second of four is to the right' do
      item = menu.items[1]
      expect([item.world_x + 20, item.world_y + 10]).to eq([400, 200])
    end

    it 're-spaces every item when another is added' do
      menu.add_item('Fifth')
      expect(menu.items[1].world_y + 10).to be_within(0.001).of(200 - (100 * Math.cos(Math::PI * 2 / 5)))
    end
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

    it 'follows the stick from one sector to another' do
      poll(1.0, 0.0)
      poll(-1.0, 0.0)
      expect(label).to eq('W')
    end

    it 'marks only the focused item as focused' do
      poll(0.0, 1.0)
      expect(menu.items.map(&:focused?)).to eq([false, false, true, false])
    end

    it 'maps a diagonal on the edge of two sectors to one of them rather than neither' do
      expect(menu.sector_at(1.0, 1.0)).to eq(2)
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
      expect(label).to eq('S')
    end

    it 'drops the selection when the stick returns to centre' do
      poll(1.0, 0.0)
      poll(0.0, 0.0)
      expect(menu.focused).to be_nil
    end

    it 'can be set per menu' do
      wide = root.add_node(described_class.new(radius: 50, item_width: 10, item_height: 10, dead_zone: 0.9))
      wide.add_item('Only')
      expect(wide.sector_at(0.0, -0.8)).to be_nil
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
      menu.add_item('E', enabled: false)
      root.enter_tree
    end

    it 'is never focused, so pointing at it selects nothing' do
      poll(1.0, 0.0)
      expect(menu.focused).to be_nil
    end

    it 'cannot be activated by pointing at it and confirming' do
      activated = false
      menu.items[1].on_activated { activated = true }
      poll(1.0, 0.0, confirm: true)
      expect(activated).to be(false)
    end
  end

  describe 'the aim' do
    before { build('N', 'E') }

    it 'keeps the last vector read, for a game drawing a pointer' do
      poll(0.25, -0.5)
      expect([menu.aim_x, menu.aim_y]).to eq([0.25, -0.5])
    end
  end

  it 'selects nothing with no items at all' do
    root.enter_tree
    poll(1.0, 0.0, confirm: true)
    expect(menu.focused).to be_nil
  end
end
