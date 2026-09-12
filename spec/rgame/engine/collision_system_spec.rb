# frozen_string_literal: true

RSpec.describe RGame::Engine::CollisionSystem do
  # Minimal actor: just what the system touches (x, y, collision_box).
  let(:actor_class) { Struct.new(:x, :y, :collision_box) }
  let(:box) { RGame::Engine::CollisionBox.new(offset_x: 8, offset_y: 16, width: 16, height: 16) }

  def actor(x, y)
    actor_class.new(x, y, box)
  end

  def system(solid:, world_width: 1000, world_height: 1000)
    described_class.new(
      blockers: RGame::Engine::TileBlockers.new(tile_width: 16, tile_height: 16, solid: solid),
      world_width: world_width, world_height: world_height
    )
  end

  it 'moves an actor freely when there are no solids' do
    a = actor(100.0, 100.0)
    system(solid: ->(_c, _r) { false }).move(a, 10, -5)
    expect(a.x).to eq(110.0)
    expect(a.y).to eq(95.0)
  end

  it 'resolves the collision box (not the sprite) against solids' do
    # Wall in column 8 (x 128..144). Origin (100, 0) → box at (108, 16, 16, 16),
    # right edge 124. Moving +10 would push the box into the wall; it snaps so the
    # box right edge rests at 128 → box_x 112 → actor.x 104.
    a = actor(100.0, 0.0)
    system(solid: ->(c, _r) { c == 8 }).move(a, 10, 0)
    expect(a.x).to eq(104.0)
  end

  it 'clamps the box within the world bounds' do
    a = actor(100.0, 100.0)
    system(solid: ->(_c, _r) { false }, world_width: 200, world_height: 200).move(a, 1000, 1000)
    expect(a.x).to eq(176.0) # box clamped to 184 (200-16) → actor 184-8
    expect(a.y).to eq(168.0) # box clamped to 184 → actor 184-16
  end

  # The system holds a list of sources and asks each one where the step lands, so these
  # drive resolve_x/resolve_y directly with sources that stop a step at a fixed edge —
  # no tiles, no broadphase, no world. A source that reports one wall in each direction
  # is all it takes to see whose answer wins.
  describe 'with several blocker sources' do
    # A blocker source that always stops a step at `edge`, whichever way it is going.
    # Instance methods only, so it satisfies the same protocol TileBlockers does and
    # allocates nothing when called (an RSpec double allocates per call, which the
    # allocation example below would measure).
    let(:fixed_blocker) do
      Class.new do
        def initialize(edge)
          @edge = edge
        end

        def resolve_x(_x, _y, _w, _h, _dx) = @edge
        def resolve_y(_x, _y, _w, _h, _dy) = @edge
      end
    end

    def fixed(edge) = fixed_blocker.new(edge)

    def resolver(*blockers)
      described_class.new(blockers: blockers, world_width: 1000, world_height: 1000)
    end

    it 'moves freely with no sources at all' do
      expect(resolver.resolve_x(100.0, 0.0, 16, 16, 10)).to eq(110.0)
      expect(resolver.resolve_y(0.0, 100.0, 16, 16, -10)).to eq(90.0)
    end

    it 'takes one source at its word on both axes' do
      expect(resolver(fixed(104.0)).resolve_x(100.0, 0.0, 16, 16, 10)).to eq(104.0)
      expect(resolver(fixed(104.0)).resolve_y(0.0, 100.0, 16, 16, 10)).to eq(104.0)
    end

    it 'takes the nearer of two sources moving right' do
      expect(resolver(fixed(108.0), fixed(104.0)).resolve_x(100.0, 0.0, 16, 16, 20)).to eq(104.0)
      expect(resolver(fixed(104.0), fixed(108.0)).resolve_x(100.0, 0.0, 16, 16, 20)).to eq(104.0)
    end

    it 'takes the nearer of two sources moving left' do
      expect(resolver(fixed(92.0), fixed(96.0)).resolve_x(100.0, 0.0, 16, 16, -20)).to eq(96.0)
      expect(resolver(fixed(96.0), fixed(92.0)).resolve_x(100.0, 0.0, 16, 16, -20)).to eq(96.0)
    end

    it 'takes the nearer of two sources moving down' do
      expect(resolver(fixed(108.0), fixed(104.0)).resolve_y(0.0, 100.0, 16, 16, 20)).to eq(104.0)
    end

    it 'takes the nearer of two sources moving up' do
      expect(resolver(fixed(92.0), fixed(96.0)).resolve_y(0.0, 100.0, 16, 16, -20)).to eq(96.0)
    end

    # A source may only ever restrict: one reporting an edge further away than the step
    # would reach is ignored rather than dragging the box along behind it.
    it 'ignores a source that would extend the step' do
      expect(resolver(fixed(200.0)).resolve_x(100.0, 0.0, 16, 16, 10)).to eq(110.0)
      expect(resolver(fixed(0.0)).resolve_x(100.0, 0.0, 16, 16, -10)).to eq(90.0)
    end

    # A standing actor asks nothing of anybody, which is what keeps a crowd of idle NPCs
    # free; and it is why a source is never called with a zero delta.
    it 'asks no source about a zero step' do
      # A strict verified double: reaching it at all fails the example.
      unasked = instance_double(RGame::Engine::TileBlockers)
      standing = described_class.new(blockers: unasked, world_width: 1000, world_height: 1000)
      expect(standing.resolve_x(100.0, 0.0, 16, 16, 0)).to eq(100.0)
      expect(standing.resolve_y(0.0, 100.0, 16, 16, 0)).to eq(100.0)
    end

    # move runs per actor per frame, and the loop over the sources is on that path.
    it 'allocates nothing per move with two sources registered' do
      a = actor(100.0, 100.0)
      resolve = resolver(fixed(104.0), fixed(108.0))
      expect { resolve.move(a, 1.0, 1.0) }.to allocate_nothing
    end
  end
end
