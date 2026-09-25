# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Respawn do
  let(:root) { RGame::Engine::Node2D.new }
  let(:world) { root.add_node(RGame::Engine::Node2D.new(x: 100, y: 50)) }
  let(:node) { RGame::Engine::Node2D.new(x: 20, y: 30) }
  let(:respawn) { node.add_component(described_class.new(flash: 0.5)) }

  def dt = 1.0 / 60

  before do
    respawn
    world.add_node(node)
    root.enter_tree
  end

  describe '.new' do
    it 'refuses a negative flash' do
      expect { described_class.new(flash: -1) }.to raise_error(ArgumentError, /flash/)
    end
  end

  describe 'the point' do
    it 'is where the node first stood, in world pixels' do
      expect([respawn.point_x, respawn.point_y]).to eq([120, 80])
    end

    it 'stays when the node attaches again somewhere else' do
      root.add_node(node)

      expect([respawn.point_x, respawn.point_y]).to eq([120, 80])
    end

    it 'moves with set_point' do
      respawn.set_point(10.0, 12.0)

      expect([respawn.point_x, respawn.point_y]).to eq([10.0, 12.0])
    end

    it 'goes anywhere with no TileWorld on the scene' do
      respawn.set_point(-500.0, 9000.0)

      expect([respawn.point_x, respawn.point_y]).to eq([-500.0, 9000.0])
    end
  end

  # Gap cells in columns 1 and 2 of row 1, x 16 to 48 and y 16 to 32, and a platform
  # over the first of them.
  describe 'on a map with gaps' do
    let(:scene) do
      parts = RGame::Engine::Components
      RGame::Engine::Node2D.new.tap do |scene|
        scene.scene = scene
        scene.add_component(parts::TileWorld.new(map: WalledTileMap.build(['....', '.~~.', '....']), tilemap_id: :map))
        platform = RGame::Engine::Node2D.new(x: 24.0, y: 24.0)
        platform.add_component(parts::BoxCollider.new(width: 16, height: 16, offset_x: -8, offset_y: -8))
        platform.add_component(parts::Platform.new)
        scene.add_node(platform)
        scene.enter_tree
      end
    end

    def stand(x, y, point: nil)
      spawned = RGame::Engine::Node2D.new(x:, y:)
      part = spawned.add_component(described_class.new)
      part.set_point(*point) if point
      scene.add_node(spawned)
      part
    end

    it 'takes the point a node first stands on, where that is ground' do
      part = stand(8.0, 24.0)

      expect([part.point_x, part.point_y]).to eq([8.0, 24.0])
    end

    it 'raises at the first attach over a gap, naming the class and the point' do
      expect { stand(40.0, 24.0) }
        .to raise_error(ArgumentError, /Node2D's respawn point \(40.0, 24.0\) is over a gap/)
    end

    it 'raises at the first attach under a platform, which is floor and not ground' do
      expect { stand(24.0, 24.0) }.to raise_error(ArgumentError, /over a gap/)
    end

    it 'keeps a point set before the first attach, and that attach checks it' do
      part = stand(40.0, 24.0, point: [8.0, 8.0])

      expect([part.point_x, part.point_y]).to eq([8.0, 8.0])
      expect { stand(8.0, 8.0, point: [40.0, 24.0]) }.to raise_error(ArgumentError, /\(40.0, 24.0\)/)
    end

    it 'refuses set_point over a gap once attached, and keeps the point it had' do
      part = stand(8.0, 24.0)

      expect { part.set_point(24.0, 24.0) }.to raise_error(ArgumentError, /over a gap/)
      expect([part.point_x, part.point_y]).to eq([8.0, 24.0])
    end
  end

  describe '#respawn' do
    before do
      node.world_x = 300
      node.world_y = 200
    end

    it 'places the node on its point, with no fall before it' do
      respawn.respawn

      expect([node.world_x, node.world_y]).to eq([120, 80])
    end

    it 'says so once, as the flash starts' do
      seen = []
      respawn.on_respawned { seen << respawn.flashing? }
      respawn.respawn
      node.update(dt)

      expect(seen).to eq([true])
    end
  end

  describe 'the flash' do
    def opacities(seconds)
      Array.new((seconds / dt).round) do
        node.update(dt)
        node.opacity
      end
    end

    # Six ticks a blink at 60 a second. The first shows for five, since the
    # node already showed on the tick of the respawn, and the last tick of the
    # flash gives the opacity back.
    it 'shows the node for a blink, then hides it for one, until the flash ends' do
      respawn.respawn
      runs = opacities(0.5).chunk_while { |a, b| a == b }.map { [it.first, it.size] }

      expect(runs).to eq([[1, 5], [0, 6], [1, 6], [0, 6], [1, 7]])
    end

    it 'gives back the opacity it found when it ends' do
      node.opacity = 0.75
      respawn.respawn
      opacities(0.3)
      expect(node.opacity).to eq(0)

      opacities(0.3)
      expect([node.opacity, respawn.flashing?]).to eq([0.75, false])
    end

    it 'gives back the first opacity it found when a second respawn restarts it' do
      node.opacity = 0.75
      respawn.respawn
      opacities(0.15)
      respawn.respawn
      opacities(0.6)

      expect(node.opacity).to eq(0.75)
    end

    it 'gives the opacity back when the node leaves the tree mid-flash' do
      respawn.respawn
      opacities(0.15)
      world.remove_node(node)

      expect([node.opacity, respawn.flashing?]).to eq([1, false])
    end

    it 'flashes nothing at 0' do
      still = described_class.new(flash: 0)
      other = RGame::Engine::Node2D.new.tap { it.add_component(still) }
      world.add_node(other)
      still.respawn

      expect(still).not_to be_flashing
    end

    it 'allocates nothing' do
      respawn.respawn
      node.update(dt)

      expect { node.update(dt) }.to allocate_nothing
    end
  end
end
