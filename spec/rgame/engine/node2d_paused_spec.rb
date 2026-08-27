# frozen_string_literal: true

# Pausing is about time, not visibility: a paused subtree stops ticking and
# keeps drawing, which is what lets a frozen world sit under a cutscene overlay
# that carries on animating.
RSpec.describe RGame::Engine::Node2D do
  let(:renderer) { FakeRenderer.new }
  let(:root)  { described_class.new }
  let(:node)  { root.add_node(counter) }
  let(:child) { node.add_node(counter) }
  let(:actions) { RGame::Engine::Actions.new }

  # Counts the phases it was driven through.
  def counter
    Class.new(described_class) do
      attr_reader :updates, :controls, :draws

      def initialize(**)
        super
        @updates = @controls = @draws = 0
      end

      def on_update(_dt) = @updates += 1
      def on_control(_actions) = @controls += 1
      def on_draw(_renderer, _view) = @draws += 1
    end.new
  end

  def tick
    root.control(actions)
    root.update(0.016)
    root.draw(renderer, screen_view)
  end

  describe 'a paused node' do
    before do
      child # mount it
      node.paused = true
      tick
    end

    it 'does not update' do
      expect(node.updates).to eq(0)
    end

    it 'does not control' do
      expect(node.controls).to eq(0)
    end

    it 'still draws, so the frozen state stays on screen' do
      expect(node.draws).to eq(1)
    end
  end

  # No abs_paused is needed: a paused node never descends, so its subtree is
  # skipped by construction rather than by resolution.
  describe 'its subtree' do
    before do
      child
      node.paused = true
      tick
    end

    it 'stops ticking with it' do
      expect(child.updates).to eq(0)
    end

    it 'keeps drawing with it' do
      expect(child.draws).to eq(1)
    end
  end

  describe 'an unpaused sibling' do
    it 'carries on ticking' do
      other = root.add_node(counter)
      node.paused = true
      tick
      expect(other.updates).to eq(1)
    end
  end

  describe 'resuming' do
    it 'starts ticking again' do
      node.paused = true
      tick
      node.paused = false
      tick
      expect(node.updates).to eq(1)
    end
  end

  # `draw` resolves the transform before drawing, so a paused node under an
  # ancestor that is still moving is drawn where it now is rather than where it
  # was when it stopped.
  describe 'a paused node under a moving ancestor' do
    it 'is drawn at its resolved position, not a stale one' do
      branch = root.add_node(described_class.new(x: 100.0))
      leaf = branch.add_node(described_class.new(x: 5.0))
      leaf.paused = true
      root.draw(renderer, screen_view)
      branch.x = 900.0
      root.draw(renderer, screen_view)

      expect(leaf.world_x).to eq(905.0)
    end
  end

  it 'costs no allocation on the phases it guards' do
    child
    root.control(actions)
    expect { root.control(actions) }.to allocate_nothing
  end
end
