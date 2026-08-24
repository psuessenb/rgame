# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::MenuItem do
  # FakeRenderer hands a nine-slice draw straight to the registered slice, so
  # that is where the call lands — the same shape a sprite takes through a sheet.
  let(:slices) { described_class::STYLE.values.to_h { |id| [id, recorder] } }

  let(:renderer) do
    FakeRenderer.new.tap { |r| slices.each { |id, slice| r.register_nine_slice(id, slice) } }
  end
  let(:root) { RGame::Engine::Node2D.new }

  # Records whatever it is asked to do, so an element can say it was the one
  # drawn without pretending to be a real nine-slice.
  def recorder
    Class.new do
      attr_reader :received

      def initialize = @received = []
      def method_missing(name, *args, **options) = @received << [name, args, options]
      def respond_to_missing?(*) = true
    end.new
  end

  def item(**)
    root.add_node(described_class.new(label: 'Resume', width: 200, height: 40, **))
        .tap { root.enter_tree }
  end

  # The style key of whichever element was drawn, and the arguments it got.
  def drew
    root.draw(renderer, screen_view)
    key, slice = slices.find { |_id, s| s.received.any? }
                       .then { |id, s| [described_class::STYLE.key(id), s] }
    [key, slice.received.last]
  end

  # There is no hover, because there is no pointer. What a mouse-driven control
  # would take from the cursor being over it, this takes from the menu telling
  # it that it is the focused one — which is why the shipped atlas has an
  # element per state rather than two.
  describe 'the element it draws for its state' do
    it 'is idle when it is not focused' do
      item
      expect(drew.first).to eq(:idle)
    end

    it 'is the focus element once it has focus' do
      item.focused = true
      expect(drew.first).to eq(:focus)
    end

    it 'is the pressed element while confirm is held on it' do
      subject_item = item
      subject_item.focused = true
      subject_item.pressed = true
      expect(drew.first).to eq(:pressed)
    end

    it 'is the disabled element whatever else is true' do
      subject_item = item(enabled: false)
      subject_item.focused = true
      expect(drew.first).to eq(:disabled)
    end
  end

  describe 'where it draws' do
    it 'fills its own box, resolved through the tree' do
      root.add_node(RGame::Engine::Node2D.new(x: 30.0, y: 70.0)).add_node(
        described_class.new(label: 'Resume', width: 200, height: 40, x: 5.0, y: 6.0)
      )
      root.enter_tree
      name, call = drew
      expect([name, call[1]]).to eq([:idle, [renderer, 35.0, 76.0, 200, 40]])
    end

    it 'centres its label in that box' do
      item
      root.draw(renderer, screen_view)
      text = renderer.calls_to(:text).last
      expect(text.args.first).to eq('Resume')
    end

    it 'draws the label above the element behind it' do
      item
      slice_z = drew.last[2][:z]
      expect(renderer.calls_to(:text).last.options[:z]).to be > slice_z
    end

    # A menu belongs in a player's own screen space, and gets there by living
    # under a PlayerLayer rather than by naming a number. On its own it is in
    # the default band, like anything else with no band ancestor.
    it 'inherits its band rather than declaring one' do
      expect(item.band).to be_nil
      expect(item.abs_band).to eq(:world)
    end

    it 'is in the HUD band under a PlayerLayer' do
      player = RGame::Engine::Player.new(id: 0)
      layer = root.add_node(RGame::Engine::PlayerLayer.new(player: player))
      menu_item = layer.add_node(described_class.new(label: 'Resume', width: 200, height: 40))
      root.enter_tree
      root.update(0)

      expect(menu_item.abs_band).to eq(:hud)
    end
  end

  describe 'activation' do
    it 'emits when it is enabled' do
      fired = false
      subject_item = item
      subject_item.on_activated { fired = true }
      expect([subject_item.activate, fired]).to eq([subject_item, true])
    end

    # A caller never has to check first, and no route can activate a disabled
    # item.
    it 'refuses when it is not' do
      fired = false
      subject_item = item(enabled: false)
      subject_item.on_activated { fired = true }
      expect([subject_item.activate, fired]).to eq([nil, false])
    end
  end

  # A game with its own art is not obliged to name it the way the shipped atlas
  # does.
  it 'takes a style of its own' do
    mine = recorder
    renderer.register_nine_slice(:mine, mine)
    root.add_node(described_class.new(label: 'Resume', width: 10, height: 10,
                                      style: described_class::STYLE.merge(idle: :mine)))
    root.enter_tree
    root.draw(renderer, screen_view)
    expect(mine.received.map(&:first)).to eq([:draw])
  end
end
