# frozen_string_literal: true

RSpec.describe RGame::Engine::PlayerLayer do
  def player(id, active: true)
    RGame::Engine::Player.new(
      id: id, device: active ? RGame::Util::Controls.gamepad(id) : nil
    )
  end

  let(:players)   { RGame::Engine::Players.new([player(0), player(1)]) }
  let(:viewports) { RGame::Engine::Viewports.new(players, width: 640, height: 480) }
  let(:renderer)  { FakeRenderer.new }

  let(:root) do
    RGame::Engine::Node2D.new.tap do |node|
      node.add_component(players)
      node.add_component(viewports)
    end
  end

  # The second player's region, which the layout puts in the bottom half.
  let(:layer) { root.add_node(described_class.new(player: players[1])) }

  def draw_frame
    layer # mount it
    root.draw(renderer, viewports.screen)
  end

  describe 'drawing into one region' do
    it 'clips to that player\'s viewport' do
      draw_frame
      expect(renderer.calls_to(:clipped).map(&:args)).to eq([[0, 240, 640, 240]])
    end

    it 'translates to its corner, so its children are positioned inside it' do
      draw_frame
      expect(renderer.calls_to(:translated).map(&:args)).to eq([[0, 240]])
    end

    it 'draws its subtree exactly once, however many viewports there are' do
      drawn = 0
      child = layer.add_node(RGame::Engine::Node2D.new)
      allow(child).to receive(:draw) { drawn += 1 }
      draw_frame
      expect(drawn).to eq(1)
    end

    it 'hands its subtree that player\'s own region' do
      seen = nil
      child = layer.add_node(RGame::Engine::Node2D.new)
      allow(child).to receive(:draw) { |_r, view| seen = view }
      draw_frame
      expect([seen.width, seen.height, seen.player]).to eq([640, 240, players[1]])
    end

    # It is screen space: nothing here is seen through a camera.
    it 'hands down a view with no camera' do
      seen = nil
      child = layer.add_node(RGame::Engine::Node2D.new)
      allow(child).to receive(:draw) { |_r, view| seen = view }
      draw_frame
      expect(seen.camera).to be_nil
    end

    # Its own visuals belong inside the region too, not once outside it.
    it 'draws its own content inside the clip' do
      seen = nil
      component = RGame::Engine::Component.new
      allow(component).to receive(:draw) { |_r, view| seen = view }
      layer.add_component(component)
      draw_frame
      expect(seen.width).to eq(640)
    end
  end

  describe 'the player it belongs to' do
    it 'is the one it was built with' do
      expect(layer.player).to equal(players[1])
    end

    # Stored only as input_owner: two fields would be two things to keep in step.
    it 'is the same thing as its input owner' do
      expect(layer.input_owner).to equal(layer.player)
    end

    it 'follows a reassignment' do
      layer.input_owner = players[0]
      expect(layer.player).to equal(players[0])
    end

    # Ownership is inherited, so a menu anywhere under here reads that player's
    # controller and nobody else's — with nothing declared inside it.
    it 'gives its whole subtree that player as their input owner' do
      leaf = layer.add_node(RGame::Engine::Node2D.new).add_node(RGame::Engine::Node2D.new)
      players.poll(FakeInputBackend.new)
      root.control(players)
      expect(leaf.abs_input_owner).to equal(players[1])
    end
  end

  describe 'when there is no region to draw into' do
    it 'draws nothing for a seat nobody is in' do
      waiting = RGame::Engine::Players.new([player(0), player(1, active: false)])
      empty_root = RGame::Engine::Node2D.new
      empty_root.add_component(waiting)
      empty_root.add_component(RGame::Engine::Viewports.new(waiting, width: 640, height: 480))
      empty_root.add_node(described_class.new(player: waiting[1]))
      empty_root.draw(renderer, screen_view)

      expect(renderer.calls).to be_empty
    end

    # A cutscene is everybody looking at one thing, so per-player UI has no
    # place to be while the split is collapsed.
    it 'draws nothing while the split is collapsed' do
      layer
      viewports.solo!(RGame::Engine::Camera.new)
      viewports.update(0.016)
      root.draw(renderer, viewports.screen)

      expect(renderer.calls).to be_empty
    end
  end

  # An empty seat is a steady state, not an edge case: a two-seat game played by
  # one person has one of these drawing nothing on every frame of the session.
  #
  # Measured on that branch rather than the drawing one, because FakeRenderer
  # records every call it receives and so allocates by design. What the drawing
  # branch adds over it — one lookup and two renderer calls — is guarded where
  # the lookup lives, in viewports_spec.
  it 'costs no allocation when there is no region to draw into' do
    waiting = RGame::Engine::Players.new([player(0), player(1, active: false)])
    empty_root = RGame::Engine::Node2D.new
    empty_root.add_component(waiting)
    empty_root.add_component(RGame::Engine::Viewports.new(waiting, width: 640, height: 480))
    empty_root.add_node(described_class.new(player: waiting[1]))
    view = screen_view
    empty_root.draw(renderer, view)

    expect { empty_root.draw(renderer, view) }.to allocate_nothing
  end
end
