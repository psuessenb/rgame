# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Navigator do
  # Maps are drawn as rows of text, '#' solid and anything else open, over 16 px tiles, and
  # mounted on the scene as a real TileWorld: what a navigator plans over is the world's
  # NavGrid, and what it smooths against is the world's TileBlockers, so both are the real
  # classes, and so is the map underneath, built from the rows by WalledTileMap.
  def tile = 16

  # A town-shaped fence: full width, one gap three tiles wide, a few trees either side.
  def fence
    [
      '....................',
      '....................',
      '..#.................',
      '....................',
      '..........#.........',
      '....................',
      '########...#########',
      '....................',
      '.....#..............',
      '....................',
      '..............#.....',
      '....................'
    ].freeze
  end

  # Not drawn by hand: searched for as a map where a sweep whose windows do not overlap
  # keeps a segment the walker is then stopped on, so the invariant below covers the overlap.
  def scattered
    [
      '....#....#......',
      '..#.....#.#.....',
      '.....###.##.....',
      '.....#.#.#.#....',
      '............#...',
      '...........#..#.',
      '.......#........',
      '....#...........',
      '#............###',
      '..........#.....',
      '##........#....#',
      '#..#.....#......'
    ].freeze
  end

  # One tree. The straight line from the centre of (0, 0) to the centre of (5, 2) passes
  # 1.6 px above its top-left corner: a point clears it, a 12x6 feet box does not.
  def tree
    [
      '......',
      '......',
      '...#..',
      '......'
    ].freeze
  end

  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }

  def dt = 1.0 / 60

  def mount(rows)
    map = WalledTileMap.build(rows, tile: tile)
    scene.add_component(RGame::Engine::Components::TileWorld.new(map: map, tilemap_id: :level))
  end

  def centre(col, row) = [(col + 0.5) * tile, (row + 0.5) * tile]

  # A hero-sized node — a 16x22 frame with a 12x6 FeetCollider, so its anchor, the centre of
  # the feet box, is 3px above its origin — standing with that anchor on a cell's centre.
  def hero_at(col, row, speed: 60.0, blocked_by: [:tiles])
    x, y = centre(col, row)
    hero = RGame::Engine::Node2D.new(x: x, y: y + 3)
    hero.width = 16
    hero.height = 22
    hero.add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6))
    navigator = hero.add_component(described_class.new(speed: speed, blocked_by: blocked_by))
    scene.add_node(hero)
    navigator
  end

  def anchor(navigator) = [navigator.node.world_x, navigator.node.world_y - 3]

  def waypoints(path) = Array.new(path.count) { [path.x_at(it), path.y_at(it)] }

  # Tick the whole scene until the walk finishes, and say how many ticks it took — nil if
  # it never did.
  def walk(navigator, limit: 5000)
    finished = false
    navigator.on_finished { finished = true }
    limit.times do |tick|
      scene.update(dt)
      return tick + 1 if finished
    end
    nil
  end

  def go_to_cell(navigator, col, row) = navigator.go_to(*centre(col, row))

  # The invariant the component exists for: a route it planned is one its own resolver lets
  # it walk. Random targets, chained from wherever the last walk ended, and half of them
  # abandoned partway for another — so a route also starts from a node standing off a
  # cell's centre, halfway along a segment.
  describe 'walking the routes it plans' do
    { fence: 'the fence', scattered: 'scattered trees' }.each do |fixture, name|
      it "is never stopped by the map it planned over, around #{name}" do
        mount(public_send(fixture))
        navigator = hero_at(0, 0, speed: 120.0)
        scene.enter_tree
        grid = scene.get_component(RGame::Engine::Components::TileWorld).nav_grid
        open = (0...grid.height).to_a.product((0...grid.width).to_a).map(&:reverse).select { grid.walkable?(*it) }
        stopped = []
        navigator.on_blocked { |by| stopped << by.layer }
        random = Random.new(7)
        arrived = []

        30.times do |route|
          target = open[random.rand(open.length)]
          next unless go_to_cell(navigator, *target)

          if route.odd?
            random.rand(1..40).times { scene.update(dt) }
            next
          end
          walk(navigator)
          arrived << anchor(navigator).zip(centre(*target)).all? { |got, want| (got - want).abs < 1e-6 }
        end

        expect(stopped).to be_empty
        expect(arrived).to all(be(true))
        expect(arrived.length).to be >= 10
      end
    end
  end

  describe '#go_to' do
    it 'starts the route where the node stands, and moves nothing doing it' do
      mount(fence)
      navigator = hero_at(1, 1)
      scene.enter_tree
      navigator.node.x += 3.0
      go_to_cell(navigator, 15, 9)
      expect(waypoints(navigator.path).first).to eq([navigator.node.x, navigator.node.y])
      expect([navigator.node.x, navigator.node.y]).to eq([centre(1, 1)[0] + 3, centre(1, 1)[1] + 3])
    end

    it 'is two waypoints across open ground, however many cells the search went through' do
      mount(Array.new(10, '.' * 12))
      navigator = hero_at(0, 1)
      scene.enter_tree
      go_to_cell(navigator, 11, 8)
      expect([navigator.cells.length, navigator.path.count]).to eq([12, 2])
    end

    it 'goes through the gap in the fence, in far fewer waypoints than cells' do
      mount(fence)
      navigator = hero_at(1, 1)
      scene.enter_tree
      go_to_cell(navigator, 18, 10)
      expect(navigator.cells.select { |_col, row| row == 6 }.map(&:first)).to all(be_between(8, 10))
      expect(navigator.path.count).to be < navigator.cells.length / 2 # 6 for 18, cornering two trees
    end

    it 'ends with the anchor on the centre of the target cell' do
      mount(fence)
      navigator = hero_at(1, 1)
      scene.enter_tree
      navigator.go_to(290.0, 165.0) # anywhere inside cell (18, 10)
      walk(navigator)
      expect(anchor(navigator)).to eq(centre(18, 10))
    end

    it 'returns true for a route' do
      mount(fence)
      navigator = hero_at(1, 1)
      scene.enter_tree
      expect(go_to_cell(navigator, 18, 10)).to be(true)
    end

    describe 'past a tree corner' do
      # The same route planned for a point, whose anchor is the node's origin.
      def point_route
        point = RGame::Engine::Node2D.new(x: centre(0, 0)[0], y: centre(0, 0)[1])
        navigator = point.add_component(described_class.new(speed: 60.0))
        scene.add_node(point)
        scene.enter_tree
        go_to_cell(navigator, 5, 2)
        waypoints(navigator.path)
      end

      it 'keeps a corner a point would cut' do
        mount(tree)
        navigator = hero_at(0, 0)
        scene.enter_tree
        go_to_cell(navigator, 5, 2)
        expect([point_route.length, navigator.path.count]).to eq([2, 3])
      end

      # What the fixture is for: the point's straight line really does clip the box.
      it 'is right to, since the feet box walking the straight line is stopped by the tree' do
        mount(tree)
        straight = point_route.map { |x, y| [x, y + 3] }
        walker = RGame::Engine::Node2D.new(x: straight[0][0], y: straight[0][1])
        walker.width = 16
        walker.height = 22
        walker.add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6))
        follow = walker.add_component(RGame::Engine::Components::PathFollow.new(
                                        path: RGame::Engine::Path.new(straight), speed: 60.0, blocked_by: [:tiles]
                                      ))
        stopped = []
        follow.on_blocked { |by| stopped << by.layer }
        scene.add_node(walker)
        scene.enter_tree
        120.times { scene.update(dt) }
        expect(stopped).to eq([:tiles])
      end
    end

    describe 'with no route' do
      let(:navigator) { hero_at(1, 1) }

      before do
        mount(fence)
        navigator
        scene.enter_tree
        go_to_cell(navigator, 18, 10)
        20.times { scene.update(dt) }
      end

      it 'returns false for a solid target, and leaves the walk alone' do
        path = navigator.path
        cells = navigator.cells
        expect(go_to_cell(navigator, 0, 6)).to be(false)
        expect([navigator.path, navigator.cells]).to eq([path, cells])
        expect(walk(navigator)).not_to be_nil
      end

      it 'returns false for a target outside the map' do
        expect(navigator.go_to(-40.0, 30.0)).to be(false)
      end
    end

    it 're-routes a walker from where it is, with no jump' do
      mount(fence)
      navigator = hero_at(1, 1)
      scene.enter_tree
      go_to_cell(navigator, 18, 10)
      30.times { scene.update(dt) }
      before = [navigator.node.x, navigator.node.y]
      go_to_cell(navigator, 1, 4)
      expect([navigator.node.x, navigator.node.y]).to eq(before)
      scene.update(dt)
      travelled = Math.hypot(navigator.node.x - before[0], navigator.node.y - before[1])
      expect(travelled).to be_within(1e-6).of(1.0) # 60 px/s for one sixtieth of a second
      walk(navigator)
      expect(anchor(navigator)).to eq(centre(1, 4))
    end

    describe 'to the cell the node is already in' do
      it 'walks to the centre of it' do
        mount(fence)
        navigator = hero_at(3, 3)
        scene.enter_tree
        navigator.node.x += 5.0
        expect(go_to_cell(navigator, 3, 3)).to be(true)
        walk(navigator)
        expect(anchor(navigator)).to eq(centre(3, 3))
      end

      it 'finishes on the next step when already there, never inside go_to' do
        mount(fence)
        navigator = hero_at(3, 3)
        scene.enter_tree
        finishes = 0
        navigator.on_finished { finishes += 1 }
        go_to_cell(navigator, 3, 3)
        expect(finishes).to eq(0)
        scene.update(dt)
        expect(finishes).to eq(1)
      end
    end

    it 'measures from the node origin on a node with no collider' do
      mount(fence)
      node = RGame::Engine::Node2D.new(x: 20.0, y: 20.0)
      navigator = node.add_component(described_class.new(speed: 120.0))
      scene.add_node(node)
      scene.enter_tree
      navigator.go_to(*centre(18, 10))
      walk(navigator)
      expect([node.x, node.y]).to eq(centre(18, 10))
    end

    it 'records the unsmoothed cells of the last route, start to target' do
      mount(fence)
      navigator = hero_at(1, 1)
      scene.enter_tree
      expect(navigator.cells).to be_nil
      go_to_cell(navigator, 18, 10)
      expect([navigator.cells.first, navigator.cells.last]).to eq([[1, 1], [18, 10]])
    end

    describe 'for a collider the size of a tile or larger' do
      def navigator_with_box(width, height)
        mount(fence)
        node = RGame::Engine::Node2D.new(x: 20.0, y: 20.0)
        node.add_component(RGame::Engine::Components::BoxCollider.new(width: width, height: height))
        navigator = node.add_component(described_class.new(speed: 120.0, blocked_by: [:tiles]))
        scene.add_node(node)
        scene.enter_tree
        navigator
      end

      it 'plans for a collider exactly one tile' do
        navigator = navigator_with_box(16, 16)
        expect([navigator.go_to(*centre(18, 10)), walk(navigator).nil?]).to eq([true, false])
      end

      it 'refuses one wider than a tile, naming its size and the tile size' do
        expect { navigator_with_box(17, 6).go_to(*centre(18, 10)) }
          .to raise_error(ArgumentError, /Navigator#go_to .* 17x6 over 16x16 tiles/)
      end

      it 'refuses one taller than a tile' do
        expect { navigator_with_box(12, 20).go_to(*centre(18, 10)) }.to raise_error(ArgumentError, /12x20/)
      end
    end

    it 'refuses to plan before the node is in the tree' do
      mount(fence)
      expect { go_to_cell(hero_at(1, 1), 3, 3) }.to raise_error(/Navigator#go_to .* in the tree first/)
    end
  end

  it 'refuses a scene with no TileWorld at attach, naming itself' do
    hero_at(1, 1, blocked_by: [])
    expect do
      scene.enter_tree
    end.to raise_error(/Navigator plans routes over the scene's TileWorld, and the scene has none/)
  end

  # The caller using both: a route planned over the map, walked through a CollisionWorld of
  # other actors the map knows nothing about. It waits behind one, as any PathFollow does.
  describe 'held by another actor on its route' do
    let(:npc) { RGame::Engine::Node2D.new(x: 120.0, y: 32.0) }

    before do
      mount(Array.new(6, '.' * 20))
      scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
      npc.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 48, layer: :npc))
      scene.add_node(npc)
    end

    it 'waits, resumes once it is gone, and is never stopped by the map' do
      navigator = hero_at(1, 3, blocked_by: %i[tiles npc])
      scene.enter_tree
      stopped = []
      navigator.on_blocked { |by| stopped << by.layer }
      go_to_cell(navigator, 18, 3)
      finished = false
      navigator.on_finished { finished = true }

      300.times { scene.update(dt) }
      held_at = navigator.node.x
      60.times { scene.update(dt) }
      expect([navigator.node.x, finished]).to eq([held_at, false])

      npc.y = 400.0
      expect(walk(navigator)).not_to be_nil
      expect(anchor(navigator)).to eq(centre(18, 3))
      expect(stopped).to eq([:npc])
    end
  end

  describe 'beside an AnimatedSprite' do
    let(:renderer) { instance_double(FakeRenderer, layered: nil, sprite: nil) }

    it 'walks down a route that runs mostly down' do
      animations = { stand: { row: 0, frames: 1, fps: 1 }, walk_right: { row: 1, frames: 1, fps: 1 },
                     walk_left: { row: 2, frames: 1, fps: 1 }, walk_up: { row: 3, frames: 1, fps: 1 },
                     walk_down: { row: 4, frames: 1, fps: 1 } }
      sheet = instance_double(FakeSheet, animations: animations, frame_width: 16, frame_height: 22)
      scene.context = instance_double(FakeGame, assets: instance_double(FakeAssets, sheet: sheet))
      mount(Array.new(8, '.' * 8))
      navigator = hero_at(2, 0)
      sprite = navigator.node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: :hero))
      scene.enter_tree
      go_to_cell(navigator, 3, 6)
      5.times { scene.update(dt) }
      sprite._draw(renderer, screen_view)
      expect(renderer).to have_received(:sprite).with(:hero, 4, any_args)
    end
  end
end
