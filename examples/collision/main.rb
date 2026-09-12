# frozen_string_literal: true

# Collision — two shapes touching.
#
# Run it:
#
#   ruby examples/collision/main.rb
#
# Arrow keys or WASD walk the pale circle. The other circles need nobody. Drive
# into a crate and both of you light up; drive into another circle and neither
# of you does. It exercises:
#   - Components::CollisionWorld — the scene-scoped system that pairs shapes up
#     each step and tells them when they start and stop overlapping;
#   - Components::CircleCollider — a round shape on a node;
#   - Components::BoxCollider — the rectangular one, and the two mix freely;
#   - Components::Velocity — from `examples/velocity`, so that things move into
#     each other without anybody pressing a key;
#   - Engine::CachedLabel — a crate's counter, which changes only on a contact.
#
# The pale circle stays lit for as long as it is inside a crate, and the crate
# blinks once and adds one to its counter. Two readings of the same pair of
# signals: one brackets a contact, the other marks the moment it began.
#
# ## The system is on the scene, the shapes are on the nodes
#
# `CollisionWorld` is a component mounted on the scene node, so it is born with
# the scene and torn down with it, and it rides the ordinary update traversal
# rather than needing a step of its own. The shapes are components on the things
# that have shapes.
#
# Nothing connects the two by hand. A collider registers with
# `node.system(CollisionWorld)` when its node enters the tree and unregisters
# when it leaves, and the engine fires both hooks — so a spawned or despawned
# entity cannot leak a registration, and no game code is asked to remember.
#
# That is also why every component here is added in `initialize` rather than in
# `on_add`: a node assembled outside the tree collects all of its components
# before any of them attaches, so the order they go on in never matters.
#
# ## A contact is reported to both sides, and neither is asked what it means
#
# Each step, the system buckets every collider, finds the overlapping pairs, and
# tells both colliders of each pair about the other. It stops there. It does not
# know what a crate is, and it never looks at `layer`.
#
# `layer` is an opaque tag, and the whole of the rule in this example is one
# line in `Mover`:
#
#     collider.on_hit { |other| @touching += 1 unless other.layer == :mover }
#
# The two circles that drift through each other *are* reported, and that line is
# what makes it look like nothing happened. Pushing the test up into the system
# would mean the system deciding that same-layer things never interact — which is
# wrong the moment one kind of thing has to hurt another of its own kind.
#
# ## A contact is two edges, not a state
#
# `on_hit` fires on the step a pair starts overlapping. `on_separated` fires on
# the step it stops. Nothing fires on the steps in between, however long the two
# sit inside each other, and a pair is reported once however many broadphase
# cells it happens to span.
#
# That is what lets a handler do something that must happen exactly once —
# `@score += 100`, play a sound, spend a life — with nothing to remember and
# nothing to guard. `Crate` below counts arrivals in one line because of it.
#
# The two signals also come in balanced pairs, which is the other thing to see on
# screen. `Mover` keeps a count: up on `on_hit`, down on `on_separated`, lit
# while it is above zero. That count is right no matter how many crates the
# circle is inside at once, because the edges are **per pair** — a second crate
# is a second `on_hit`, not a louder version of the first.
#
# A contact also ends when the other side is destroyed or leaves the tree, and
# `on_separated` fires then too. Nothing here dies, but a shooter whose bullets
# vanish on impact depends on it: without it a ship could stay "in contact" with
# a rock that no longer exists.
#
# ## A box and a circle collide with each other
#
# `CircleCollider` and `BoxCollider` are not two separate worlds. Both answer the
# same broadphase question (the bounding box to bucket me in) and the same
# narrowphase one (`overlap?`), and the pair settles the actual test between
# themselves by handing each other their numbers. So one world holds both, and
# every circle here collides with every crate.
#
# ## An AABB does not turn with its node
#
# The drifting circles spin — the spoke is drawn so you can see it — and their
# collision shape is unaffected, because a circle is the same circle at every
# angle. The crates carry an axis-aligned box and do not spin, and that is a
# choice rather than a preference: a box that turned with its node would have to
# be recomputed into a wider box every frame, and the wider box is wrong in a
# different way. A thing that spins wants a circle.
#
# ## `cell_size` is the one number this system asks a game to pick
#
# The broadphase is a spatial hash: a lattice of square cells, each collider
# dropped into the cells its bounding box covers, and only colliders sharing a
# cell ever tested against each other. The faint grid on the backdrop is drawn at
# that size, so the number is visible rather than a constant at the top of a
# file.
#
# Pick it at about the size of the things being bucketed. Much smaller and one
# collider spans a block of cells and is tested from every one of them; much
# larger and everything lands in the same cell and the hash has quietly become
# the loop over all pairs it exists to avoid.
#
# ## What it does not solve
#
# Response. Nothing here is pushed out of anything: a contact is a notification,
# and these shapes overlap and carry on. Stopping a body at a wall is a different
# problem with different machinery, and `examples/collision_tiles` is where it
# lives.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

# The broadphase cell, and the grid drawn on the backdrop. Everything bucketed
# here is 32 to 96 pixels across, so the cell is one of those.
CELL_SIZE = 64

WALK_SPEED = 150.0

# How long a crate stays lit after a circle arrives. Long enough to see at a
# glance, short enough that two arrivals read as two.
FLASH_TIME = 0.3

# A round thing that lights up while it is inside a crate. Its two subclasses
# differ only in what moves them — the shape, the layer and the rule are the same
# for both.
#
# `@touching` is the balanced pair of edges, kept as a count rather than a flag
# because a circle can be inside two crates at once: the two in the middle of the
# field overlap, and driving into the pair is two `on_hit` calls before either
# `on_separated` arrives. A flag would go dark on leaving the first of them.
class Mover < RGame::Engine::Node2D
  RADIUS = 16
  BODY  = RGame::Util::Color.new(236, 233, 220)
  HIT   = RGame::Util::Color.new(255, 214, 92)
  SPOKE = RGame::Util::Color.new(60, 66, 82)

  def initialize(**)
    super(width: RADIUS * 2, height: RADIUS * 2, **)
    @touching = 0
    collider = add_component(RGame::Engine::Components::CircleCollider.new(radius: RADIUS, layer: :mover))
    # Both edges are reported to both colliders, each handed the other, so this is
    # written entirely from this node's side. The guard is the example's subject:
    # same-layer pairs are reported and these lines drop them. It has to be the
    # same guard on both, or the count would not come back to zero.
    collider.on_hit { |other| @touching += 1 unless other.layer == :mover }
    collider.on_separated { |other| @touching -= 1 unless other.layer == :mover }
  end

  # The centre is where the traversal has already put the renderer, and the
  # circle's collision centre is the node's origin — the same point.
  def on_draw(renderer, _view)
    renderer.circle(0, 0, RADIUS, color: @touching.positive? ? HIT : BODY)
    # Drawn at the node's own angle, which is what makes the spin visible at all:
    # a spinning circle looks like a still one without a mark on it.
    renderer.line(0, 0, RADIUS, 0, thickness: 3, color: SPOKE)
  end
end

# Moves because it was given a velocity, and for no other reason.
class Drifter < Mover
  def initialize(vx:, vy:, spin: 0.0, **)
    super(**)
    add_component(RGame::Engine::Components::Velocity.new(vx: vx, vy: vy, spin: spin))
    add_component(RGame::Engine::Components::ScreenWrap.new(margin: RADIUS))
  end
end

# The one with a hand on it. Same shape, same layer, same rule.
class Walker < Mover
  def initialize(**)
    super
    add_component(RGame::Engine::Components::CharacterBody.new(speed: WALK_SPEED))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::ScreenWrap.new(margin: RADIUS))
  end
end

# A rectangle that never moves and counts the circles that have arrived.
#
# Two of them overlap on purpose, in the middle of the field. That pair is in
# contact from the first step to the last, the system reports it exactly once,
# and neither counter moves — which is the same one-line rule `Mover` uses, seen
# from the other side.
#
# A visit is one circle arriving, and it is counted by adding one in the handler,
# because `on_hit` is the arrival rather than the overlap. Two circles standing
# in this crate at once is two visits: the edges are per pair, so each of them
# announced itself.
class Crate < RGame::Engine::Node2D
  BODY = RGame::Util::Color.new(88, 104, 136)
  HIT  = RGame::Util::Color.new(150, 196, 255)
  INK  = RGame::Util::Color.new(180, 190, 210)

  def initialize(width:, height:, **)
    super
    @flash = 0.0
    @touches = 0
    @label = RGame::Engine::CachedLabel.new { |count| "visits: #{count}" }
    # The box is offset to sit around the node's origin, which is where a circle's
    # centre already is — so both shapes here are drawn and collide about the
    # same point. A sprite that wants a small box at its feet moves the offset
    # instead; nothing says the box has to be centred.
    collider = add_component(RGame::Engine::Components::BoxCollider.new(
                               width: width, height: height,
                               offset_x: -width / 2, offset_y: -height / 2, layer: :wall
                             ))
    collider.on_hit do |other|
      next if other.layer == :wall

      @touches += 1
      @flash = FLASH_TIME
    end
  end

  # Only the flash, which is a cosmetic timer and the one thing here that has to
  # be advanced rather than announced. The counter is not touched: it moves on the
  # edge, in the handler above.
  def on_update(dt) = @flash -= dt

  def on_draw(renderer, _view)
    renderer.rect(-width / 2, -height / 2, width, height, color: @flash.positive? ? HIT : BODY)
    renderer.text(@label[@touches], -width / 2, (-height / 2) - 22, color: INK)
  end
end

class Scene < RGame::Engine::Node2D
  BACKDROP = RGame::Util::Color.new(26, 30, 38)
  GRID     = RGame::Util::Color.new(38, 44, 56)

  # Centre x, centre y, width, height. The first two overlap.
  CRATES = [
    [300, 200, 96, 40],
    [336, 244, 40, 96],
    [520, 140, 72, 56],
    [150, 340, 64, 64]
  ].freeze

  # Centre x, centre y, vx, vy, spin in degrees per second. Fixed rather than
  # random, so two runs of this example can be compared without a seed.
  DRIFTERS = [
    [40, 200, 120.0, 0.0, 90.0],
    [600, 140, -95.0, 0.0, -140.0],
    [150, 104, 0.0, 105.0, 0.0]
  ].freeze

  # Both systems are mounted here rather than in `on_add`, so they exist before
  # any child's collider attaches and goes looking for them.
  def initialize
    super
    add_component(RGame::Engine::Components::World.new(width: WIDTH, height: HEIGHT))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: CELL_SIZE))
  end

  def on_add
    CRATES.each { |x, y, w, h| add_node(Crate.new(x: x, y: y, width: w, height: h)) }
    DRIFTERS.each do |x, y, vx, vy, spin|
      add_node(Drifter.new(x: x, y: y, vx: vx, vy: vy, spin: spin))
    end
    add_node(Walker.new(x: 80, y: 430))
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BACKDROP)
    draw_cells(renderer, view)

    renderer.text('Arrows / WASD walk the pale circle — the other two need nobody', 12, 12)
    renderer.text('Enter a crate: it blinks once and counts you, you stay lit inside', 12, 34)
    renderer.text('Circle into circle does nothing — same layer, one line ignoring it', 12, 56)
  end

  private

  # The broadphase's own lattice, so `cell_size` is something you can look at.
  # A while loop rather than a Range: this runs every frame, and a fresh Range
  # every frame is the allocation the hot-path cops exist to refuse.
  #
  # hot-path
  def draw_cells(renderer, view)
    x = CELL_SIZE
    while x < view.width
      renderer.rect(x, 0, 1, view.height, color: GRID)
      x += CELL_SIZE
    end

    y = CELL_SIZE
    while y < view.height
      renderer.rect(0, y, view.width, 1, color: GRID)
      y += CELL_SIZE
    end
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Collision',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
