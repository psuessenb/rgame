# frozen_string_literal: true

# A y-sorted node sorts its children on every draw, and a top-down game draws
# one every frame, per viewport. The sort, the footing it reads and the
# collider lookup behind that may not allocate, or every walking actor is a
# little GC pressure.
RSpec.describe RGame::Engine::Node2D do
  let(:renderer) { QuietRenderer.new }
  let(:view) { screen_view }
  let(:actors) { described_class.new(y_sort: true) }

  # Fifty children, half of them standing on a box, each moving up or down by
  # up to 1.5px a frame, so the order changes as they pass each other.
  let(:walkers) do
    Array.new(50) do |i|
      actors.add_node(described_class.new(y: i * 7 % 200)).tap do |node|
        node.add_component(RGame::Engine::Components::BoxCollider.new(width: 12, height: 6, offset_y: 10)) if i.even?
      end
    end
  end

  let(:speeds) { Array.new(50) { |i| ((i % 7) - 3) * 0.5 } }

  before do
    walkers
    actors.draw(renderer, view)
  end

  it 'allocates nothing while its children pass each other' do
    expect do
      walkers.each_index { |i| walkers[i].y += speeds[i] }
      actors.draw(renderer, view)
    end.to allocate_nothing
  end

  it 'allocates nothing drawing the same frame twice, as two viewports do' do
    expect { 2.times { actors.draw(renderer, view) } }.to allocate_nothing
  end
end
