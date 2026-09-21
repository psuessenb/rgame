# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::OccupiesCell do
  def components = RGame::Engine::Components

  # 8x3 cells of 16 px, open but for one tree the map itself made solid at (3, 1).
  let(:map) { WalledTileMap.build(['........', '...#....', '........']) }
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:world) { scene.add_component(components::TileWorld.new(map: map, tilemap_id: :level)) }

  before do
    world
    scene.enter_tree
  end

  def crate(col, row) = RGame::Engine::Node2D.new.tap { it.add_component(described_class.new(col:, row:)) }

  describe 'the cell it occupies' do
    it 'is solid once its node enters the tree, and not before' do
      box = crate(5, 1)
      before = world.solid?(5, 1)
      scene.add_node(box)
      expect([before, world.solid?(5, 1)]).to eq([false, true])
    end

    it 'opens again when its node leaves the tree' do
      box = scene.add_node(crate(5, 1))
      scene.remove_node(box)
      expect(world.solid?(5, 1)).to be(false)
    end

    it 'opens again when the component leaves a node still in the tree' do
      box = scene.add_node(crate(5, 1))
      box.remove_component(described_class)
      expect(world.solid?(5, 1)).to be(false)
    end

    it 'is solid when the component is added to a node already in the tree' do
      box = scene.add_node(RGame::Engine::Node2D.new)
      box.add_component(described_class.new(col: 5, row: 1))
      expect(world.solid?(5, 1)).to be(true)
    end

    it 'stays solid while a second occupant is still there' do
      first = scene.add_node(crate(5, 1))
      second = scene.add_node(crate(5, 1))
      scene.remove_node(first)
      still = world.solid?(5, 1)
      scene.remove_node(second)
      expect([still, world.solid?(5, 1)]).to eq([true, false])
    end

    it 'stays solid after its occupant leaves, when the map made it solid' do
      scene.remove_node(scene.add_node(crate(3, 1)))
      expect(world.solid?(3, 1)).to be(true)
    end

    it 'is solid to the blockers and the route at once, as it is to solid?' do
      scene.add_node(crate(5, 1))
      # Under a tile per step, as the sweep asks: 72 to 82 reaches the crate at 80.
      landed = world.blockers.resolve_x(60.0, 20.0, 12, 6, 10.0)
      expect([landed, world.nav_grid.walkable?(5, 1)]).to eq([68.0, false])
    end
  end

  describe 'refusing a cell it cannot occupy' do
    it 'raises at attach for a cell outside the map, naming the cell and the map size' do
      expect { scene.add_node(crate(8, 1)) }.to raise_error(ArgumentError, /\(8, 1\).*8x3/)
    end

    it 'raises at attach when the scene has no TileWorld, naming it' do
      bare = RGame::Engine::Node2D.new.tap { it.scene = it }
      bare.enter_tree
      expect { bare.add_node(crate(5, 1)) }.to raise_error(RuntimeError, /TileWorld/)
    end

    it 'leaves nothing behind to vacate after a refused attach' do
      box = crate(8, 1)
      expect { scene.add_node(box) }.to raise_error(ArgumentError)
      expect { scene.remove_node(box) }.not_to raise_error
    end
  end

  # CLAUDE.md's composition test: a runtime blocker and the two things it has to stop,
  # in one scene. Nothing else mounts a cell that changes under a body and a navigator.
  describe 'in a scene with a body and a navigator' do
    def dt = 1.0 / 60

    def walker(x, y, mover)
      node = RGame::Engine::Node2D.new(x: x, y: y)
      node.add_component(components::BoxCollider.new(width: 12, height: 6))
      node.add_component(mover)
      scene.add_node(node)
      mover
    end

    it 'stops a body walking into the crate, and reports the tiles as what stopped it' do
      # Row 2, clear of the map's own tree in row 1.
      body = walker(20.0, 37.0, components::CharacterBody.new(speed: 60.0, blocked_by: [:tiles]))
      scene.add_node(crate(5, 2))
      stopped = []
      body.on_blocked { |by| stopped << by.layer }
      body.set_intent(1.0, 0.0)
      120.times { scene.update(dt) }
      expect([body.node.x, stopped]).to eq([68.0, [:tiles]])
    end

    it 'routes a navigator planning after the crate arrives round it, and walks it unstopped' do
      navigator = walker(2.0, 21.0, components::Navigator.new(speed: 90.0, blocked_by: [:tiles]))
      navigator.go_to(world.cell_centre_x(7), world.cell_centre_y(1))
      straight = navigator.cells

      scene.add_node(crate(5, 1))
      scene.add_node(crate(5, 0))
      stopped = []
      navigator.on_blocked { |by| stopped << by.layer }
      navigator.go_to(world.cell_centre_x(7), world.cell_centre_y(1))
      finished = false
      navigator.on_finished { finished = true }
      300.times { scene.update(dt) }

      expect([straight.include?([5, 1]), navigator.cells.include?([5, 2])]).to eq([true, true])
      expect([finished, stopped]).to eq([true, []])
    end
  end
end
