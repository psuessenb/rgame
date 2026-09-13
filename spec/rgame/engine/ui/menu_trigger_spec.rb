# frozen_string_literal: true

# A menu held open by an action: closed until the trigger goes down, open while
# it is held, and choosing the focused button when it comes up. Driven here with
# a wheel of four buttons, because pointing and letting go is the gesture the
# trigger exists for; the rules hold for any navigation.
RSpec.describe RGame::Engine::UI::Menu do
  let(:root) { RGame::Engine::Node2D.new }
  let(:navigation) { RGame::Engine::UI::Pointing.new }
  let(:menu) do
    ring = RGame::Engine::UI::Ring.new(radius: 100, item_width: 40, item_height: 40)
    root.add_node(described_class.new(layout: ring, navigation: navigation, trigger: :quick))
  end

  let(:snapshot) do
    reads = %i[quick ui_confirm skill1]
    held = reads.to_h { |name| [name, false] }
    previous = reads.to_h { |name| [name, false] }
    axes = { ui_radial_x: 0.0, ui_radial_y: 0.0 }
    actions = RGame::Engine::Actions.new(held: held, axes: axes, prev_held: previous)

    lambda do |down, x, y|
      held.each { |name, state| previous[name] = state }
      reads.each { |name| held[name] = down.include?(name) }
      axes[:ui_radial_x] = x
      axes[:ui_radial_y] = y
      actions
    end
  end

  # Labels of the buttons activated, and of what each on_closed said, in order.
  def chosen = (@chosen ||= [])
  def closed_with = (@closed_with ||= [])

  # One tick at 60 Hz: control, then update. `stick` is [x, y].
  def tick(*down, stick: [0.0, 0.0])
    root.control(snapshot.call(down, *stick))
    root.update(1.0 / 60)
  end

  # N, E, S, W. The menu has been on screen for a frame with nothing held.
  def build(**)
    %w[N E S W].each do |label|
      button = menu.add(RGame::Engine::UI::Button.new(label: label, **))
      button.on_activated { chosen << label }
    end
    menu.on_closed { |button| closed_with << button&.label }
    root.enter_tree
    tick
    menu
  end

  describe 'opening' do
    before { build }

    it 'starts closed' do
      expect(menu.open?).to be(false)
    end

    it 'opens on the trigger going down, and stays open while it is held' do
      opened = 0
      menu.on_opened { opened += 1 }
      tick(:quick)
      5.times { tick(:quick, stick: [1.0, 0.0]) }
      expect([menu.open?, opened]).to eq([true, 1])
    end

    it 'focuses nothing on the stick while closed' do
      tick(stick: [1.0, 0.0])
      expect(menu.focused).to be_nil
    end

    it 'reads the stick on the frame it opens' do
      tick(:quick, stick: [1.0, 0.0])
      expect(menu.focused&.label).to eq('E')
    end

    it 'raises when opened by hand, naming the trigger' do
      expect { menu.open }.to raise_error(RuntimeError, /:quick/)
    end
  end

  describe 'letting go' do
    before { build }

    it 'activates the focused button once, closes, and says which' do
      tick(:quick)
      tick(:quick, stick: [1.0, 0.0])
      tick(stick: [1.0, 0.0])
      3.times { tick }
      expect([chosen, menu.open?, closed_with]).to eq([['E'], false, ['E']])
    end

    it 'activates the button focus moved to during the hold, not the first' do
      tick(:quick, stick: [1.0, 0.0])
      tick(:quick, stick: [0.0, 1.0])
      tick(stick: [0.0, 1.0])
      expect(chosen).to eq(['S'])
    end

    it 'activates the last button pointed at when the stick came home inside the grace window' do
      tick(:quick, stick: [1.0, 0.0])
      4.times { tick(:quick) } # a fifteenth of a second at rest, inside 0.15 s
      tick
      expect(chosen).to eq(['E'])
    end

    it 'activates nothing when the stick was at rest for longer than the window, and closes' do
      tick(:quick, stick: [1.0, 0.0])
      20.times { tick(:quick) } # a third of a second
      tick
      expect([chosen, menu.open?, closed_with]).to eq([[], false, [nil]])
    end

    it 'activates nothing when nothing was ever pointed at' do
      tick(:quick)
      tick
      expect([chosen, closed_with]).to eq([[], [nil]])
    end
  end

  describe 'confirm' do
    before { build }

    it 'activates nothing while the trigger is held, and the release still chooses' do
      tick(:quick, stick: [1.0, 0.0])
      tick(:quick, :ui_confirm, stick: [1.0, 0.0])
      tick(:quick, stick: [1.0, 0.0])
      after_confirm = chosen.dup
      tick(stick: [1.0, 0.0])
      expect([after_confirm, chosen]).to eq([[], ['E']])
    end
  end

  describe 'a press it did not see' do
    it 'opens nothing for a trigger already down when the menu is first controlled' do
      %w[N E].each { |label| menu.add(RGame::Engine::UI::Button.new(label: label)) }
      root.enter_tree
      3.times { tick(:quick, stick: [1.0, 0.0]) }
      expect(menu.open?).to be(false)
    end

    it 'closes without choosing when the trigger came up while the menu was paused' do
      build
      tick(:quick, stick: [1.0, 0.0])
      menu.paused = true
      tick(stick: [1.0, 0.0]) # released, unseen
      menu.paused = false
      tick(stick: [1.0, 0.0])
      expect([menu.open?, chosen, closed_with]).to eq([false, [], [nil]])
    end
  end

  describe 'opening again' do
    before { build }

    it 'forgets the last opening: nothing focused and the aim at rest before the stick is read' do
      tick(:quick, stick: [1.0, 0.0])
      tick(stick: [1.0, 0.0])
      aims = []
      menu.on_opened { aims << [navigation.aim_x, navigation.aim_y, menu.focused] }
      tick(:quick)
      expect([aims, menu.focused]).to eq([[[0.0, 0.0, nil]], nil])
    end
  end

  # The menu closes on the tick it activates, so pressed feedback would never be
  # seen — except on a reopening a few frames later, where it would be stale.
  describe 'the button a release chose' do
    before { build }

    it 'is not drawn pressed when the menu opens again at once' do
      tick(:quick, stick: [1.0, 0.0])
      tick(stick: [1.0, 0.0])
      tick(:quick, stick: [1.0, 0.0])
      expect(menu.focused.state).to eq(:focused)
    end
  end

  describe '#close on a held menu' do
    before { build }

    it 'closes at once, and the release that follows neither chooses nor reopens' do
      tick(:quick, stick: [1.0, 0.0])
      menu.close
      tick(:quick, stick: [1.0, 0.0])
      tick(stick: [1.0, 0.0])
      tick(stick: [1.0, 0.0])
      expect([menu.open?, chosen, closed_with]).to eq([false, [], [nil]])
    end

    it 'reopens on the next press' do
      tick(:quick, stick: [1.0, 0.0])
      menu.close
      tick
      tick(:quick)
      expect(menu.open?).to be(true)
    end
  end

  describe 'drawing' do
    let(:renderer) { FakeRenderer.new }
    let(:menu) do
      root.add_node(RGame::Engine::UI::RadialMenu.new(radius: 100, button_width: 40, trigger: :quick))
    end

    def draw
      renderer.clear
      root.draw(renderer, screen_view)
      renderer.calls.map(&:name)
    end

    before do
      menu.add(RGame::Engine::UI::TextButton.new(label: 'N'))
      root.enter_tree
      tick
    end

    it 'draws neither its backdrop nor its buttons while closed' do
      expect(draw).to be_empty
    end

    it 'draws both while the trigger is held' do
      tick(:quick)
      expect(draw).to include(:circle, :line, :rect, :text)
    end

    it 'draws nothing again once let go' do
      tick(:quick)
      tick
      expect(draw).to be_empty
    end
  end

  describe 'with no navigation' do
    let(:navigation) { nil }

    it 'lets go onto whatever the game focused when it opened' do
      build
      menu.on_opened { menu.focus(2) }
      tick(:quick)
      tick
      expect(chosen).to eq(['S'])
    end
  end

  describe 'hotkeys' do
    it 'press their button while the menu is open, and not while it is closed' do
      menu.add(RGame::Engine::UI::Button.new(label: 'N', hotkey: :skill1)).on_activated { chosen << 'N' }
      root.enter_tree
      tick
      tick(:skill1)
      tick
      tick(:quick)
      tick(:quick, :skill1)
      expect(chosen).to eq(['N'])
    end
  end

  it 'costs nothing to control, opening, pointing, choosing and closing over and over' do
    build
    reads = { quick: false, ui_confirm: false, skill1: false }
    previous = reads.dup
    axes = { ui_radial_x: 0.0, ui_radial_y: 0.0 }
    actions = RGame::Engine::Actions.new(held: reads, axes: axes, prev_held: previous)
    count = 0
    expect do
      count += 1
      previous[:quick] = reads[:quick]
      reads[:quick] = (count % 30) < 20
      axes[:ui_radial_x] = (count % 30) < 12 ? 1.0 : 0.0
      root.control(actions)
      root.update(1.0 / 60)
    end.to allocate_nothing.over(3_000).after_warmup(60)
  end
end
