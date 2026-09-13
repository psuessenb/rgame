# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Hop do
  subject(:hop) { described_class.new(peak: 20.0, duration: 0.5) }

  let(:node) { RGame::Engine::Node2D.new(x: 10, y: 30) }

  before do
    node.add_component(hop)
    node.enter_tree
  end

  def actions(held: false, prev_held: false)
    RGame::Engine::Actions.new(held: { jump: held }, prev_held: { jump: prev_held })
  end

  describe '.new' do
    it 'refuses a peak that is not positive' do
      expect { described_class.new(peak: 0, duration: 0.5) }.to raise_error(ArgumentError, /peak/)
    end

    it 'refuses a duration that is not positive' do
      expect { described_class.new(peak: 10, duration: -1) }.to raise_error(ArgumentError, /duration/)
    end
  end

  describe 'on the ground' do
    it 'is not airborne and has no height' do
      expect([hop.airborne?, hop.height, node.elevation]).to eq([false, 0.0, 0])
    end

    it 'does not rise on update alone' do
      node.update(0.1)
      expect(node.elevation).to eq(0)
    end
  end

  describe 'starting a hop' do
    it 'leaves the ground on the press edge of the action' do
      node.control(actions(held: true))
      expect(hop).to be_airborne
    end

    it 'does not start again while the action is merely held' do
      node.control(actions(held: true))
      node.update(0.6) # lands
      node.control(actions(held: true, prev_held: true))
      expect(hop).not_to be_airborne
    end

    it 'reads no action when built with action: nil' do
      manual = described_class.new(peak: 20.0, duration: 0.5, action: nil)
      other = RGame::Engine::Node2D.new.tap { it.add_component(manual) }
      other.control(RGame::Engine::Actions.new)
      expect(manual).not_to be_airborne
    end

    it 'can be started by #jump, which does not restart a hop already in the air' do
      hop.jump
      node.update(0.25)
      hop.jump
      expect(hop.height).to eq(20.0)
    end
  end

  describe 'the arc' do
    before { hop.jump }

    it 'peaks halfway through the duration' do
      node.update(0.25)
      expect([hop.height, node.elevation]).to eq([20.0, 20.0])
    end

    it 'follows a parabola either side of the peak' do
      node.update(0.125)
      expect(node.elevation).to be_within(1e-9).of(15.0)
    end

    it 'lands once the duration has passed, and can hop again' do
      node.update(0.5)
      expect([hop.airborne?, node.elevation]).to eq([false, 0])
      hop.jump
      expect(hop).to be_airborne
    end

    it 'hangs in the air while the node is paused' do
      node.update(0.1)
      node.paused = true
      expect { node.update(1.0) }.not_to(change(node, :elevation))
    end

    it 'never moves the node itself' do
      node.update(0.25)
      expect([node.x, node.y]).to eq([10, 30])
    end
  end

  it 'lands a node that attaches again mid-hop' do
    hop.jump
    node.update(0.2)
    node.exit_tree
    node.enter_tree
    expect([hop.airborne?, node.elevation]).to eq([false, 0])
  end

  it 'does not allocate per frame, in the air or on the ground' do
    dt = 1.0 / 60.0
    expect do
      hop.jump
      hop.update(dt)
    end.to allocate_nothing.after_warmup(120)
  end
end
