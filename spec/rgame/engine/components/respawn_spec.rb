# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Respawn do
  let(:root) { RGame::Engine::Node2D.new }
  let(:world) { root.add_node(RGame::Engine::Node2D.new(x: 100, y: 50)) }
  let(:node) { RGame::Engine::Node2D.new(x: 20, y: 30) }
  let(:respawn) { node.add_component(described_class.new) }

  def dt = 1.0 / 60

  before do
    respawn
    world.add_node(node)
    root.enter_tree
  end

  describe '.new' do
    it 'takes no arguments, flash: included: a Blink shows where a node came back' do
      expect { described_class.new(flash: 1.0) }.to raise_error(ArgumentError, /given 1, expected 0/)
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

    it 'says so once, with the node on its point' do
      seen = []
      respawn.on_respawned { seen << [node.world_x, node.world_y] }
      respawn.respawn
      node.update(dt)

      expect(seen).to eq([[120, 80]])
    end

    it 'starts a Blink connected to on_respawned, from its point' do
      blink = node.add_component(RGame::Engine::Components::Blink.new)
      respawn.on_respawned { blink.start(0.5) }
      respawn.respawn
      6.times { node.update(dt) }

      expect([node.world_x, node.world_y, node.opacity, blink.blinking?]).to eq([120, 80, 0, true])
    end
  end
end
