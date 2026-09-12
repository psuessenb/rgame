# frozen_string_literal: true

RSpec.describe RGame::Engine::CollisionSystem do
  # Minimal actor: just what the system touches (x, y, collision_box).
  let(:actor_class) { Struct.new(:x, :y, :collision_box) }
  let(:box) { RGame::Engine::CollisionBox.new(offset_x: 8, offset_y: 16, width: 16, height: 16) }

  def actor(x, y)
    actor_class.new(x, y, box)
  end

  def system(solid:)
    described_class.new(
      blockers: RGame::Engine::TileBlockers.new(tile_width: 16, tile_height: 16, solid: solid)
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

  # There is no clamp here any more. The edge of the world is Engine::BoundsBlockers, an
  # ordinary source a body declares, so nothing holds an actor anywhere it did not ask
  # to be held.
  it 'does not hold the actor inside any region of its own' do
    a = actor(100.0, 100.0)
    system(solid: ->(_c, _r) { false }).move(a, 1000, 1000)
    expect([a.x, a.y]).to eq([1100.0, 1100.0])
  end

  # The system holds a list of sources and asks each one where the step lands, so these
  # drive resolve_x/resolve_y directly with sources that stop a step at a fixed edge —
  # no tiles, no broadphase, no world. A source that reports one wall in each direction
  # is all it takes to see whose answer wins.
  describe 'with several blocker sources' do
    # A blocker source that always stops a step at `edge`, whichever way it is going.
    # Instance methods only, so it satisfies the same protocol TileBlockers does and
    # allocates nothing when called (an RSpec double allocates per call, which the
    # allocation example below would measure). `name` is what it reports as the blocker,
    # so an example can say which source won an axis; `moved` records that it was told.
    let(:fixed_blocker) do
      Class.new do
        attr_reader :blocker, :move_count, :from_box

        def initialize(edge, name)
          @edge = edge
          @blocker = name
          @move_count = 0
          # Four slots rather than an Array per call: the allocation example below drives
          # this too, and a recording fake that allocates would be the only thing it saw.
          @from_box = [nil, nil, nil, nil]
        end

        def resolve_x(_x, _y, _w, _h, _dx) = @edge
        def resolve_y(_x, _y, _w, _h, _dy) = @edge

        def moved(_actor, from_x, from_y, w, h)
          @move_count += 1
          @from_box[0] = from_x
          @from_box[1] = from_y
          @from_box[2] = w
          @from_box[3] = h
        end
      end
    end

    def fixed(edge, name = :fixed) = fixed_blocker.new(edge, name)

    def resolver(*blockers) = described_class.new(blockers: blockers)

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
      standing = described_class.new(blockers: unasked)
      expect(standing.resolve_x(100.0, 0.0, 16, 16, 0)).to eq(100.0)
      expect(standing.resolve_y(0.0, 100.0, 16, 16, 0)).to eq(100.0)
    end

    # move runs per actor per frame, and the loop over the sources is on that path.
    it 'allocates nothing per move with two sources registered' do
      a = actor(100.0, 100.0)
      resolve = resolver(fixed(104.0), fixed(108.0))
      resolve.move(a, 1.0, 1.0) # warm the recording arrays the fake sources keep
      expect { resolve.move(a, 1.0, 1.0) }.to allocate_nothing
    end

    # What stopped the step, per axis, taken from whichever source won it. A body reads
    # these to report the edges of being blocked; the system asks each winner rather than
    # remembering an answer, because a source's own is overwritten by the next axis.
    describe '#blocked_x / #blocked_y' do
      it 'names what the winning source reports' do
        resolve = resolver(fixed(108.0, :far), fixed(104.0, :near))
        resolve.resolve_x(100.0, 0.0, 16, 16, 20)
        expect(resolve.blocked_x).to eq(:near)
      end

      it 'is nil on an axis nothing restricted' do
        resolve = resolver(fixed(200.0, :far))
        resolve.resolve_x(100.0, 0.0, 16, 16, 10)
        expect(resolve.blocked_x).to be_nil
      end

      it 'is nil on an axis that was not moved at all' do
        resolve = resolver(fixed(104.0, :near))
        resolve.resolve_x(100.0, 0.0, 16, 16, 0)
        expect(resolve.blocked_x).to be_nil
      end

      # A step stopped on X and free on Y, which is wall-sliding: the two axes report
      # separately because they were resolved separately.
      it 'is set per axis by a move' do
        a = actor(100.0, 100.0)
        resolve = described_class.new(blockers: fixed(104.0, :wall))
        resolve.move(a, 20.0, 0.0)
        expect([resolve.blocked_x, resolve.blocked_y]).to eq([:wall, nil])
      end
    end

    # The last thing #move does, so a source over a moving index can re-bucket the mover.
    # The box passed is the one the step *started* from, which is what makes that exact.
    describe 'telling the sources the step happened' do
      it 'tells every source, with the box the step started from' do
        a = actor(100.0, 100.0)
        one = fixed(104.0)
        two = fixed(108.0)
        described_class.new(blockers: [one, two]).move(a, 20.0, 20.0)
        # The actor's box is offset (8, 16) from its origin at (100, 100).
        expect([one.from_box, two.from_box]).to eq([[108.0, 116.0, 16, 16]] * 2)
      end

      it 'tells them even when nothing moved' do
        a = actor(100.0, 100.0)
        one = fixed(104.0)
        described_class.new(blockers: one).move(a, 0.0, 0.0)
        expect(one.move_count).to eq(1)
      end
    end
  end
end
