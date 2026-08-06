# frozen_string_literal: true

# The pool's reclaim rides every frame, so it must not allocate in steady state (no frees
# → reclaim_if's in-place reject! moves nothing).
RSpec.describe RGame::Engine::Components::Pool do
  it 'reclaims without allocating per frame' do
    owner = RGame::Engine::Node2D.new
    pool = owner.add_component(described_class.new { RGame::Engine::Node2D.new })
    owner.enter_tree
    5.times { pool.spawn } # a steady set of live nodes, none freed

    expect { pool.update(1.0 / 60.0) }.to allocate_nothing
  end
end
