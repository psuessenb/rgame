# frozen_string_literal: true

# A look that writes down each call its Fall makes on it, into a log the
# signals write into too, so one log shows the order of both.
class RecordedLook < RGame::Engine::Components::FallLook
  def initialize(log)
    super()
    @log = log
  end

  def start = @log << :start
  def show(progress) = @log << progress
  def finish = @log << :finish
end

# A fall started by hand, on a node standing on ground. Its Fall lasts a quarter
# of a second, which is 15 or 16 ticks of 1/60.
RSpec.describe RGame::Engine::Components::Fall do
  # A gap tile at x 64..80 in row 1, and ground everywhere else.
  let(:root) do
    engine::Node2D.new.tap do |scene|
      scene.scene = scene
      map = WalledTileMap.build(['............', '....~.......', '............'])
      scene.add_component(parts::TileWorld.new(map: map, tilemap_id: :map))
    end
  end
  let(:world) { root.add_node(engine::Node2D.new) }

  def engine = RGame::Engine
  def parts = RGame::Engine::Components
  def dt = 1.0 / 60

  # A node at (40, 27) with a Fall, and each of `others` after it.
  def faller(*others, x: 40.0)
    node = engine::Node2D.new(x: x, y: 27.0)
    node.add_component(described_class.new(duration: 0.25))
    others.each { node.add_component(it) }
    world.add_node(node)
    root.enter_tree
    node
  end

  def fall(node) = node.get_component(described_class)

  def tick
    root.update(dt)
    root.sweep_freed
  end

  def ticks(count) = count.times { tick }

  # Ticks until the fall is over, and answers how many that took.
  def to_the_end(node) = (1..40).find { tick.then { !fall(node).falling? } }

  describe '.new' do
    it 'lasts 0.4 seconds unless told otherwise' do
      expect(described_class.new.duration).to eq(0.4)
    end

    [0, -0.25, nil, '0.25'].each do |duration|
      it "refuses a duration of #{duration.inspect}" do
        expect { described_class.new(duration: duration) }.to raise_error(ArgumentError, /duration/)
      end
    end
  end

  describe '#start' do
    it 'suspends the node, and answers the Fall' do
      node = faller
      started = fall(node).start

      expect([started, node.suspended?, fall(node).falling?]).to eq([fall(node), true, true])
    end

    it 'does nothing during a fall, and answers the Fall' do
      node = faller
      fell = 0
      fall(node).on_fell { fell += 1 }
      fall(node).start
      ticks(10)
      started = fall(node).start

      expect([started, fell, to_the_end(node)]).to match([fall(node), 1, be_between(5, 6)])
    end

    it 'raises for a node outside the tree, and leaves it as it was' do
      node = engine::Node2D.new
      outside = node.add_component(described_class.new)

      expect { outside.start }.to raise_error(RuntimeError, /in the tree/)
      expect([node.suspended?, outside.falling?]).to eq([false, false])
    end

    it 'raises for a Fall on no node' do
      expect { described_class.new.start }.to raise_error(RuntimeError, /in the tree/)
    end
  end

  describe 'its end' do
    it 'brings a node with a Respawn back on its point once the duration has run, resumed' do
      node = faller(parts::Respawn.new)
      node.x = 50.0
      fall(node).start
      took = to_the_end(node)

      expect([took, node.world_x, node.suspended?, world.children]).to match([be_between(15, 16), 40.0, false, [node]])
    end

    it 'frees a node with no Respawn, resumed' do
      node = faller
      fall(node).start
      to_the_end(node)

      expect([world.children, node.suspended?]).to eq([[], false])
    end

    it 'takes a node over a gap as it takes one on ground' do
      node = faller(x: 70.0)
      fall(node).start
      took = to_the_end(node)

      expect([took, world.children]).to match([be_between(15, 16), []])
    end

    it 'frees a node whose Respawn was removed in on_fell' do
      node = faller(parts::Respawn.new)
      fall(node).on_fell { node.remove_component(parts::Respawn) }
      fall(node).start
      to_the_end(node)

      expect(world.children).to eq([])
    end
  end

  describe '#finish' do
    it 'ends a fall under way as its end would' do
      node = faller(parts::Respawn.new)
      finished = 0
      fall(node).on_finished { finished += 1 }
      node.x = 50.0
      fall(node).start
      ticks(3)
      fall(node).finish
      state = [node.world_x, node.suspended?, fall(node).falling?]
      ticks(20)

      expect([state, finished]).to eq([[40.0, false, false], 1])
    end

    it 'does nothing with no fall under way, and answers the Fall' do
      node = faller(parts::Respawn.new)
      finished = 0
      fall(node).on_finished { finished += 1 }

      expect([fall(node).finish, finished, node.suspended?]).to eq([fall(node), 0, false])
    end
  end

  describe 'its signals' do
    it 'fires on_fell before the look starts, and on_finished once, after the respawn' do
      log = []
      node = faller(RecordedLook.new(log), parts::Respawn.new)
      fall(node).on_fell { log << :fell }
      fall(node).on_finished { log << :finished }
      node.get_component(parts::Respawn).on_respawned { log << :respawned }
      fall(node).start
      ticks(30)

      expect([log.first(3), log.last(4)]).to eq([[:fell, :start, log[2]], [1.0, :finish, :respawned, :finished]])
    end

    it 'fires on_finished after the node is marked free' do
      node = faller
      freed = nil
      fall(node).on_finished { freed = node.freed? }
      fall(node).start
      to_the_end(node)

      expect(freed).to be(true)
    end
  end

  describe 'its look' do
    it 'starts it, shows it each tick with the progress rising to 1, and finishes it, once each' do
      log = []
      node = faller(RecordedLook.new(log))
      fall(node).start
      took = to_the_end(node)
      shown = log[1..-2]

      expect([log.first, log.last, shown.size]).to eq([:start, :finish, took])
      expect([shown.first, shown.each_cons(2).all? { |a, b| b > a }, shown.last]).to eq([dt / 0.25, true, 1.0])
    end

    it 'changes nothing drawn without one: the node holds still at its scale, then comes back' do
      node = faller(parts::Respawn.new)
      node.scale = 2
      node.opacity = 0.5
      fall(node).start
      seen = Array.new(20) { tick.then { [node.scale, node.opacity, node.world_x] } }

      expect(seen.uniq).to eq([[2, 0.5, 40.0]])
    end

    it 'raises as the fall starts on a node with two' do
      node = faller(RecordedLook.new([]), parts::Shrink.new)

      expect { fall(node).start }.to raise_error(ArgumentError, /two FallLooks, .*RecordedLook and .*Shrink/)
    end

    it 'shows a look added in on_fell' do
      node = faller
      fall(node).on_fell { node.add_component(parts::Shrink.new) }
      fall(node).start
      ticks(5)

      expect(node.scale).to be < 1
    end

    it 'starts no look for a fall finished in on_fell' do
      log = []
      node = faller(RecordedLook.new(log), parts::Respawn.new)
      fall(node).on_fell { fall(node).finish }
      fall(node).start
      ticks(20)

      expect([log, node.suspended?]).to eq([[], false])
    end

    it 'shows a look that leaves its node mid-fall no more, and ends the fall all the same' do
      log = []
      node = faller(RecordedLook.new(log), parts::Respawn.new)
      fall(node).start
      ticks(5)
      node.remove_component(RecordedLook)
      took = to_the_end(node)

      expect([log.size, log.last, took]).to match([6, be_within(1e-9).of(5 * dt / 0.25), be_between(10, 11)])
    end
  end

  describe 'leaving the tree mid-fall' do
    def footed_faller(order)
      node = engine::Node2D.new(x: 40.0, y: 27.0)
      node.add_component(parts::FeetCollider.new(width: 12, height: 6))
      built = { footing: parts::Footing.new, fall: described_class.new(duration: 0.25), shrink: parts::Shrink.new }
      order.each { node.add_component(built[it]) }
      node.scale = 2
      world.add_node(node)
      root.enter_tree
      node
    end

    %i[footing fall shrink].permutation.each do |order|
      it "comes out resumed, at the scale its look found, with no on_finished, added as #{order.join(', ')}" do
        node = footed_faller(order)
        finished = 0
        fall(node).on_finished { finished += 1 }
        fall(node).start
        ticks(5)
        world.remove_node(node)

        expect([node.scale, node.suspended?, fall(node).falling?, finished]).to eq([2, false, false, 0])
      end
    end

    it 'ends as the Fall leaves its node, and gives the look its finish' do
      log = []
      node = faller(RecordedLook.new(log))
      fall(node).start
      ticks(5)
      node.remove_component(described_class)

      expect([node.suspended?, log.last]).to eq([false, :finish])
    end

    it 'leaves the old parent with no trace once the tick is swept' do
      node = faller
      fall(node).start
      ticks(5)
      root.add_node(node)
      tick

      expect(world.children).to eq([])
    end
  end

  # The fall a Footing starts, on a walker that heads east at a pixel a tick and
  # steps off the floor at 64. The Footing drops it on the step off.
  describe 'from a Footing' do
    def walker(order: %i[body hop footing fall shrink])
      node = engine::Node2D.new(x: 40.0, y: 27.0)
      node.add_component(parts::FeetCollider.new(width: 12, height: 6))
      built = { body: parts::CharacterBody.new(speed: 60),
                hop: parts::Hop.new(peak: 10, duration: 0.5, action: nil),
                footing: parts::Footing.new(coyote: 0),
                fall: described_class.new(duration: 0.5),
                shrink: parts::Shrink.new,
                respawn: parts::Respawn.new,
                blink: parts::Blink.new }
      built[:respawn].on_respawned { built[:blink].start(0.5) } if order.include?(:blink)
      order.each { node.add_component(built[it]) }
      world.add_node(node)
      root.enter_tree
      node
    end

    def walk_off(node)
      node.get_component(parts::CharacterBody).set_intent(1, 0)
      (1..200).find { tick.then { !node.get_component(parts::Footing).standing? } }
    end

    it 'stops the node where it fell and says so once' do
      node = walker
      fell = 0
      fall(node).on_fell { fell += 1 }
      walk_off(node)
      ticks(10)

      expect([node.suspended?, node.world_x, fell]).to eq([true, 64.0, 1])
    end

    # The fall began on the step off, so 29 of its 30 ticks have run at the end.
    it 'shrinks the node from 1 toward 0 over the fall' do
      node = walker
      walk_off(node)
      scales = Array.new(28) { tick.then { node.scale } }

      expect(scales.first).to be > 0.99
      expect(scales.each_cons(2).all? { |a, b| b < a }).to be(true)
      expect(scales.last).to be < 0.1
    end

    it 'frees a node with no Respawn at the end, unscaled and resumed' do
      node = walker
      walk_off(node)
      ticks(30)

      expect([world.children, node.scale, node.suspended?, fall(node).falling?]).to eq([[], 1, false, false])
    end

    [%i[body hop footing fall shrink respawn blink], %i[blink respawn shrink fall footing hop body]].each do |order|
      it "brings a node with a Respawn back on its point, blinking and walking, added as #{order.join(', ')}" do
        node = walker(order: order)
        walk_off(node)
        took = (1..40).find { tick.then { !fall(node).falling? } }
        state = [node.world_x, node.world_y, node.scale, node.suspended?, world.children]
        ticks(1)

        expect([took, state]).to match([be_between(29, 31), [40.0, 27.0, 1, false, [node]]])
        expect([node.get_component(parts::Blink).blinking?, node.world_x]).to eq([true, 41.0])
      end

      # The game's choice at each fall: it takes a life in on_fell, and removes the
      # Respawn with the last one.
      it "brings a node back from its first fall and frees it after its second, added as #{order.join(', ')}" do
        node = walker(order: order)
        lives = 2
        respawns = 0
        node.get_component(parts::Respawn).on_respawned { respawns += 1 }
        fall(node).on_fell do
          lives -= 1
          node.remove_component(parts::Respawn) if lives.zero?
        end
        walk_off(node)
        ticks(40)
        back = world.children.include?(node)
        walk_off(node)
        ticks(40)

        expect([back, respawns, world.children.empty?, lives]).to eq([true, 1, true, 0])
      end
    end

    it 'holds mid-shrink while the world around it is paused' do
      node = walker
      walk_off(node)
      ticks(10)
      world.paused = true
      scale = node.scale
      ticks(60)

      expect([node.scale, fall(node).falling?]).to eq([scale, true])
    end

    it 'ends at once, unscaled and resumed, when the node is taken from its parent' do
      node = walker
      walk_off(node)
      ticks(10)
      world.remove_node(node)

      expect([node.scale, node.suspended?, fall(node).falling?]).to eq([1, false, false])
    end

    it 'leaves the parent with no trace of the fall once it has ended' do
      node = walker
      walk_off(node)
      ticks(10)
      root.add_node(node)
      tick

      expect(world.children).to eq([])
    end
  end

  describe 'around it' do
    it 'holds mid-fall while the world around the node is paused' do
      node = faller(parts::Shrink.new)
      fall(node).start
      ticks(5)
      world.paused = true
      scale = node.scale
      ticks(60)

      expect([node.scale, fall(node).falling?]).to eq([scale, true])
    end

    it 'leaves the parent with no trace once it ends' do
      node = faller(parts::Respawn.new)
      fall(node).start
      to_the_end(node)

      expect(world.children).to eq([node])
    end

    # The first fall's clock is still the parent's child, marked free, when the
    # second starts.
    it 'falls again from on_finished, on the tick the last fall ended' do
      node = faller(parts::Respawn.new)
      falls = 0
      fall(node).on_finished { fall(node).start if (falls += 1) == 1 }
      fall(node).start
      took = to_the_end(node)

      expect([falls, took, world.children]).to match([2, be_between(30, 32), [node]])
    end

    # Finished between ticks, the first fall's clock is still the parent's child
    # at the next update, and must not move the second fall on.
    it 'moves a fall started again after #finish on by one tick a tick' do
      log = []
      node = faller(RecordedLook.new(log), parts::Respawn.new)
      falls = 0
      fall(node).on_finished { fall(node).start if (falls += 1) == 1 }
      fall(node).start
      ticks(3)
      fall(node).finish
      log.clear
      tick

      expect(log).to eq([dt / 0.25])
    end
  end
end
