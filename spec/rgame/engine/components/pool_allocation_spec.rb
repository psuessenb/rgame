# frozen_string_literal: true

# A pool exists so that spawning builds nothing, so its whole cycle is measured
# here: the reclaim that rides every frame, and a spawn, a free and a reclaim
# running together the way examples/pooling runs them.
RSpec.describe RGame::Engine::Components::Pool do
  def dt = 1.0 / 60

  it 'reclaims without allocating per frame' do
    owner = RGame::Engine::Node2D.new
    pool = owner.add_component(described_class.new { RGame::Engine::Node2D.new })
    owner.enter_tree
    5.times { pool.spawn } # a steady set of live nodes, none freed

    expect { pool._update(1.0 / 60.0) }.to allocate_nothing
  end

  # One node a tick, moving right at ten pixels a tick from the middle of a
  # 100-wide world, so each lives six ticks. The warm-up fills the pool to that
  # many; after it every spawn is a recycled node entering the tree again, with
  # its Velocity and DespawnOffscreen attaching again.
  describe 'spawning, freeing and reclaiming' do
    let(:scene) do
      RGame::Engine::Node2D.new.tap do |scene|
        scene.scene = scene
        scene.add_component(RGame::Engine::Components::World.new(width: 100, height: 100))
      end
    end
    let(:spawner) { scene.add_node(RGame::Engine::Node2D.new(x: 50, y: 50)) }
    let(:built) { [] }
    let(:pool) do
      spawner.add_component(described_class.new do
        RGame::Engine::Node2D.new.tap do |mote|
          mote.add_component(RGame::Engine::Components::Velocity.new(vx: 600.0))
          mote.add_component(RGame::Engine::Components::DespawnOffscreen.new)
          built << mote
        end
      end)
    end

    before do
      pool
      scene.enter_tree
    end

    def tick
      pool.spawn { |mote| mote.x = 0 }
      scene.update(dt)
      scene.sweep_freed
    end

    it 'recycles rather than builds once warm' do
      60.times { tick }
      expect { 60.times { tick } }.not_to(change(built, :size))
    end

    it 'allocates nothing once warm' do
      expect { tick }.to allocate_nothing.after_warmup(60)
    end

    it 'keeps nothing it allocates once warm' do
      expect { tick }.to retain_nothing.after_warmup(60)
    end
  end
end
