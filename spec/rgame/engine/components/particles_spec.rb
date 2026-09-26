# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Particles do
  # Answers the middle of every draw, so a particle flies exactly along
  # `direction` at the middle of its speed and lifetime.
  let(:middle_random) do
    Class.new do
      def rand(range = nil) = range ? (range.begin + range.end) / 2.0 : 0.5
    end
  end

  def color = RGame::Util::Color
  def ramp = RGame::Util::ColorRamp.new(color.new(255, 240, 160), color.new(255, 120, 0, 0), steps: 5)

  def emitter(**)
    defaults = { limit: 100, lifetime: 1.0, speed: 10.0, direction: 0.0, spread: 0.0, ramp: ramp,
                 rng: middle_random.new }
    described_class.new(**defaults, **)
  end

  def mount(particles, parent: RGame::Engine::Node2D.new)
    node = parent.add_node(RGame::Engine::Node2D.new)
    node.add_component(particles)
    parent.enter_tree unless parent.in_tree?
    node
  end

  def rects_of(node)
    renderer = FakeRenderer.new
    node.draw(renderer, screen_view)
    renderer.calls_to(:rect)
  end

  describe '#burst' do
    it 'places count particles at its point, in the node\'s local space' do
      particles = emitter(size: 4)
      node = mount(particles)
      placed = particles.burst(5, 10, 20)

      expect([placed, particles.live]).to eq([5, 5])
      expect(rects_of(node).map(&:args)).to all(eq([8.0, 18.0, 4, 4]))
    end

    it 'gives each a heading within spread of direction, and a speed from its range' do
      particles = emitter(direction: -Math::PI / 2, spread: 0.5, speed: 20.0..40.0, rng: Random.new(3))
      node = mount(particles)
      particles.burst(200)
      node.update(0.5)

      moves = rects_of(node).map { |call| [call.args[0] + 1, call.args[1] + 1] }
      headings = moves.map { |x, y| Math.atan2(y, x) }
      speeds = moves.map { |x, y| Math.hypot(x, y) / 0.5 }

      expect(headings.minmax).to all(be_between((-Math::PI / 2) - 0.5, (-Math::PI / 2) + 0.5))
      expect(headings.max - headings.min).to be > 0.9
      expect(speeds.minmax).to all(be_between(20.0, 40.0))
    end

    it 'gives each a lifetime from its range' do
      particles = emitter(lifetime: 0.4..0.7, rng: Random.new(5))
      node = mount(particles)
      particles.burst(50)
      alive = [0.35, 0.4].map do |dt|
        node.update(dt)
        particles.live
      end

      expect(alive).to eq([50, 0])
    end
  end

  describe 'each update' do
    it 'moves a particle by its velocity, after adding gravity to its downward speed' do
      particles = emitter(speed: 10.0, gravity: 100.0, size: 2)
      node = mount(particles)
      particles.burst(1)
      node.update(0.25)
      node.update(0.25)

      expect(rects_of(node).first.args.first(2)).to eq([(5.0 - 1), (6.25 + 12.5) - 1])
    end

    it 'frees a particle once its age reaches its lifetime' do
      particles = emitter(lifetime: 0.5)
      node = mount(particles)
      particles.burst(3)
      node.update(0.25)
      halfway = particles.live
      node.update(0.25)

      expect([halfway, particles.live]).to eq([3, 0])
      expect(rects_of(node)).to be_empty
    end
  end

  describe 'drawing' do
    it 'draws each particle in its ramp\'s colour for its age, inside blended(blend)' do
      particles = emitter(lifetime: 1.0, blend: :add)
      node = mount(particles)
      particles.burst(1)
      node.update(0.5)
      rect = rects_of(node).first
      blended = rect.transforms.find { it.name == :blended }

      expect(rect.options[:color]).to eq(ramp.at(0.5))
      expect(blended.args).to eq([:add])
    end

    it 'opens no blend block when nothing is alive' do
      renderer = FakeRenderer.new
      mount(emitter).draw(renderer, screen_view)

      expect(renderer.drawn?(:blended)).to be(false)
    end
  end

  describe 'the limit' do
    it 'places what fits and drops the rest' do
      particles = emitter(limit: 4)
      mount(particles)

      expect([particles.burst(3), particles.burst(3), particles.burst(3)]).to eq([3, 1, 0])
      expect(particles.live).to eq(4)
    end

    it 'counts a freed particle as room again' do
      particles = emitter(limit: 2, lifetime: 0.5)
      node = mount(particles)
      particles.burst(2)
      node.update(0.5)

      expect(particles.burst(2)).to eq(2)
    end
  end

  describe '#rate' do
    def stream(particles, node, ticks)
      Array.new(ticks) do
        before = particles.live
        node.update(1.0 / 60)
        particles.live - before
      end
    end

    it 'streams from the node\'s origin' do
      particles = emitter(speed: 0.0, size: 2)
      node = mount(particles)
      particles.rate = 60
      node.update(1.0 / 60)

      expect(rects_of(node).map(&:args)).to eq([[-1.0, -1.0, 2, 2]])
    end

    it 'carries the fraction, so 40 a second is 2 in every 3 ticks and none is lost' do
      particles = emitter(lifetime: 10.0, limit: 1000)
      node = mount(particles)
      particles.rate = 40
      spawned = stream(particles, node, 600)

      expect(spawned.first(6)).to eq([0, 1, 1, 0, 1, 1])
      expect(spawned.sum).to eq(400)
    end

    it 'streams none at 0, and refuses a negative rate' do
      particles = emitter
      node = mount(particles)
      stream(particles, node, 60)

      expect(particles.live).to eq(0)
      expect { particles.rate = -1 }.to raise_error(ArgumentError, /0 or more/)
    end
  end

  it 'places every particle the same in two runs with the same seed' do
    runs = Array.new(2) do
      particles = emitter(spread: Math::PI, speed: 10.0..60.0, lifetime: 0.5..2.0, rng: Random.new(42))
      node = mount(particles)
      particles.rate = 30
      particles.burst(10, 5, 5)
      20.times { node.update(1.0 / 60) }
      rects_of(node).map { [it.args, it.options[:color]] }
    end

    expect(runs.first).to eq(runs.last)
    expect(runs.first.size).to eq(20)
  end

  describe 'leaving the tree' do
    it 'takes the particles with it, and the node enters again with none' do
      root = RGame::Engine::Node2D.new
      particles = emitter
      node = mount(particles, parent: root)
      particles.burst(5)
      root.remove_node(node)
      gone = particles.live
      root.add_node(node)

      expect([gone, particles.live]).to eq([0, 0])
    end
  end

  describe 'with two viewports' do
    def player(id) = RGame::Engine::Player.new(id:, device: RGame::Util::Controls.gamepad(id))

    it 'draws the same particles into each' do
      players = RGame::Engine::Players.new([player(0), player(1)])
      viewports = RGame::Engine::Viewports.new(players, width: 640, height: 480)
      root = RGame::Engine::Node2D.new
      root.add_component(players)
      root.add_component(viewports)
      world = root.add_node(RGame::Engine::WorldView.new)
      particles = emitter
      mount(particles, parent: world)
      root.enter_tree
      particles.burst(3, 50, 50)
      viewports.refresh
      renderer = FakeRenderer.new
      root.draw(renderer, viewports.screen)

      args = renderer.calls_to(:rect).map(&:args)
      expect(args.size).to eq(6)
      expect(args.first(3)).to eq(args.last(3))
      expect(renderer.calls_to(:blended).size).to eq(2)
    end
  end

  it 'holds still while its node is paused' do
    particles = emitter
    node = mount(particles)
    particles.rate = 60
    particles.burst(2)
    node.update(0.1)
    before = rects_of(node).map(&:args)
    node.paused = true
    3.times { node.update(0.1) }

    expect(rects_of(node).map(&:args)).to eq(before)
  end

  describe 'rng:' do
    let(:root) { RGame::Engine::Node2D.new }
    let(:source) { RGame::Engine::Components::RandomSource.new(seed: 9) }

    it "draws from the root's RandomSource when given none" do
      root.add_component(source)
      allow(source).to receive(:rand).and_call_original
      particles = emitter(rng: nil)
      mount(particles, parent: root)
      particles.burst(3)

      expect(source).to have_received(:rand).exactly(9).times
    end

    it 'raises at attach, naming RandomSource, when the root has none' do
      expect { mount(emitter(rng: nil), parent: root) }.to raise_error(KeyError, /RandomSource/)
    end

    it 'refuses to burst before its node is in the tree' do
      particles = emitter(rng: nil)
      RGame::Engine::Node2D.new.add_component(particles)

      expect { particles.burst(3) }.to raise_error(RuntimeError, /in the tree/)
    end

    it "draws from an rng: passed in, and leaves the root's source alone" do
      root.add_component(source)
      allow(source).to receive(:rand).and_call_original
      particles = emitter(rng: Random.new(9))
      mount(particles, parent: root)
      particles.burst(3)

      expect(source).not_to have_received(:rand)
    end
  end

  describe 'what it refuses' do
    {
      { limit: 0 } => /limit: must be a positive Integer/,
      { limit: 2.5 } => /limit: must be a positive Integer/,
      { lifetime: 0 } => /lifetime: must be/,
      { lifetime: 0.0..1.0 } => /lifetime: must be/,
      { speed: -1 } => /speed: must be/,
      { speed: 5..2 } => /speed: must be/,
      { size: 0 } => /size: must be a positive number/,
      { blend: :screen } => /unknown blend mode :screen/
    }.each do |options, message|
      it "refuses #{options.inspect}" do
        expect { emitter(**options) }.to raise_error(ArgumentError, message)
      end
    end

    it 'refuses a ramp that is not a ColorRamp' do
      expect { emitter(ramp: color::WHITE) }.to raise_error(TypeError, /ramp: must be/)
    end
  end

  describe 'the caller that uses both: a coin that sparkles as it is taken' do
    def coin(scene, sparkles, x, y)
      node = scene.add_node(RGame::Engine::Node2D.new(x:, y:))
      node.add_component(RGame::Engine::Components::CircleCollider.new(radius: 8, layer: :pickup))
      node.add_component(RGame::Engine::Components::Collectable.new(by: :hero))
          .on_collected { sparkles.burst(8, node.world_x, node.world_y) }
      node
    end

    it 'bursts where the coin stood, and the sparkles outlive the coin' do
      root = RGame::Engine::Node2D.new
      scene = root.add_node(RGame::Engine::Node2D.new).tap { it.scene = it }
      scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
      root.enter_tree
      sparkles = emitter(lifetime: 0.5, speed: 0.0, size: 2)
      mount(sparkles, parent: scene)
      taken = coin(scene, sparkles, 100, 60)
      hero = scene.add_node(RGame::Engine::Node2D.new(x: 100, y: 60))
      hero.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, layer: :hero))

      scene.update(1.0 / 60)
      root.sweep_freed
      after_pickup = [taken.in_tree?, sparkles.live]
      where = rects_of(sparkles.node).map { it.args.first(2) }.uniq
      scene.update(0.25)
      halfway = sparkles.live
      scene.update(0.25)

      expect(after_pickup).to eq([false, 8])
      expect(where).to eq([[99.0, 59.0]])
      expect(halfway).to eq(8)
      expect(sparkles.live).to eq(0)
    end
  end
end
