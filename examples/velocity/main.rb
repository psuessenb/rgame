# frozen_string_literal: true

# Velocity — movement with nobody driving.
#
# Run it:
#
#   ruby examples/velocity/main.rb
#
# Arrow keys, WASD or a stick walk the pale circle. The rectangles are not
# waiting for you. It exercises:
#   - Components::Velocity — a velocity integrated into the node each step;
#   - Components::ScreenWrap — leaving one edge and arriving at the opposite one;
#   - Components::World — how big the world is, as a service the scene mounts;
#   - Components::WorldBounds — the contract that lets one wrap fit two worlds.
#
# ## Two ways to move, and the difference is who decides
#
# Every example before this one moved things with `CharacterBody`, which takes an
# *intent* — each axis in -1..1 — and turns it into a step at a fixed speed. Let
# go of the key and the intent is zero and the node stops. That is what a walking
# character wants, and it is why the circle here behaves the way you expect.
#
# A rock has no intent. It has a velocity, and something integrates it:
#
#     node.x += vx * dt
#     node.y += vy * dt
#     node.angle += spin * dt
#
# That is the whole of Components::Velocity. Nothing writes to it after the
# rectangles are built, nothing reads input, and they drift for as long as the
# program runs. The two components are siblings rather than rivals —
# `ThrustController` is the third of the family, and it *accelerates* a velocity
# rather than setting one, which is how a ship differs from both.
#
# ## `spin` is an angle, and the shape does not know
#
# Two of the rectangles turn as they drift, and the drawing code is the same
# single `renderer.rect` the still ones use, at the same coordinates. `Node2D#draw`
# has already pushed the node's rotation, so a component that adds to `angle` is
# enough to make a shape spin — the same reason the sprite in `examples/sprite`
# turns without Components::Sprite knowing that angles exist.
#
# ## The outline is the world, and the world is not the window
#
# The rectangles wrap at the outline rather than at the edge of the screen, and
# that gap is the whole point of `Components::World` being a thing at all. The two
# sizes coincide in a single-screen game, which is exactly what makes binding
# them together an easy mistake and a hard one to see: a world tied to the
# viewport changes shape when the window is resized, and changes again the moment
# the screen is split and each half becomes its own viewport.
#
# So there are two questions with two answers. Ask the `view` a draw is handed
# how big the **window** is. Ask `node.system(WorldBounds)` how big the **world**
# is.
#
# ## Why the wrap asks for a contract rather than a class
#
# `ScreenWrap` never mentions `World`. It calls `WorldBounds.resolve`, and what
# answers is whichever system the scene mounted — the plain rectangle here, or a
# `TileWorld` that works its bounds out from a parsed map. `Node2D#get_component`
# matches with `is_a?`, which matches an included module as readily as a class,
# and that is the whole mechanism.
#
# It resolves in `on_attach` rather than `initialize`, because a node has no
# scene to ask until it is in the tree — and it resolves again on every entry, so
# an entity pooled out of one scene and into a smaller one wraps against the
# smaller one.
#
# ## What it does not solve
#
# Collision. These pass straight through each other, because a velocity is only
# a position changing over time and nothing here is watching for overlaps.
# `examples/collision` is where that is the subject.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

# Deliberately smaller than the window, and offset inside it, so that "the world"
# and "the window" cannot be confused for one number wearing two names.
WORLD_W = 460
WORLD_H = 330
WORLD_X = 90
WORLD_Y = 110

# How far past the edge a shape travels before it is put back on the other side.
# Without it a rectangle jumps while half of it is still showing.
WRAP_MARGIN = 40.0

WALK_SPEED = 140.0

# A rectangle that moves because it was given a velocity, and for no other
# reason. Everything that makes it move is a component; this class is a shape.
class Drifter < RGame::Engine::Node2D
  BOX_W = 38
  BOX_H = 20

  def initialize(color:, vx:, vy:, spin: 0.0, **)
    super(width: BOX_W, height: BOX_H, **)
    @color = color
    @vx = vx
    @vy = vy
    @spin = spin
  end

  def on_add
    add_component(RGame::Engine::Components::Velocity.new(vx: @vx, vy: @vy, spin: @spin))
    add_component(RGame::Engine::Components::ScreenWrap.new(margin: WRAP_MARGIN))
  end

  # Centred on the node's own origin, which is where the traversal has already
  # put the renderer — so a spinning node turns this rectangle about its middle
  # and this method never learns of it.
  def on_draw(renderer, _view)
    renderer.rect(-BOX_W / 2, -BOX_H / 2, BOX_W, BOX_H, color: @color)
  end
end

# The one with an intent. Same wrap, same world, different reason to move.
class Walker < RGame::Engine::Node2D
  BODY = RGame::Util::Color.new(236, 233, 220)
  RADIUS = 13

  def initialize(**)
    super(width: RADIUS * 2, height: RADIUS * 2, **)
  end

  # CharacterBody first: PlayerController drives a sibling body and asks for it
  # by class when it attaches, and a component added from `on_add` can only see
  # the ones already there.
  def on_add
    add_component(RGame::Engine::Components::CharacterBody.new(speed: WALK_SPEED))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::ScreenWrap.new(margin: RADIUS))
  end

  def on_draw(renderer, _view) = renderer.circle(0, 0, RADIUS, color: BODY)
end

class Scene < RGame::Engine::Node2D
  BACKDROP = RGame::Util::Color.new(28, 32, 42)
  FLOOR    = RGame::Util::Color.new(44, 50, 64)
  EDGE     = RGame::Util::Color.new(120, 200, 255)
  THICK    = 2

  # vx, vy, spin (degrees per second), colour. Fixed rather than random: two runs
  # of this example should be able to be compared without a seed.
  DRIFTERS = [
    [90.0, 34.0, 0.0, [235, 145, 90]],
    [-70.0, 58.0, 110.0, [130, 210, 150]],
    [48.0, -76.0, 0.0, [225, 205, 110]],
    [-104.0, -26.0, -150.0, [190, 150, 235]],
    [62.0, 90.0, 0.0, [120, 200, 255]]
  ].freeze

  # Mounted here rather than in `on_add` for a reason worth knowing: a node
  # assembled outside the tree collects every component before any of them
  # attaches, so nothing depends on the order. Added from `on_add` the node is
  # already live, each component attaches as it arrives, and the wraps below
  # would resolve their bounds before this existed.
  def initialize
    super
    add_component(RGame::Engine::Components::World.new(width: WORLD_W, height: WORLD_H))
  end

  # Everything that wraps lives under one node, offset to put the world inside
  # the window. A child's x and y are its place in its parent, so a drifter at
  # world (0, 0) is drawn at the outline's corner and wraps at the outline's
  # edges — without the wrap, the drifters or the outline knowing about the
  # offset at all.
  def on_add
    field = add_node(RGame::Engine::Node2D.new(x: WORLD_X, y: WORLD_Y))

    DRIFTERS.each_with_index do |(vx, vy, spin, rgb), index|
      field.add_node(Drifter.new(color: RGame::Util::Color.new(*rgb), vx: vx, vy: vy, spin: spin,
                                 x: 60 + (index * 78), y: 40 + (index * 52)))
    end

    field.add_node(Walker.new(x: WORLD_W / 2, y: WORLD_H / 2))
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BACKDROP)
    renderer.rect(WORLD_X, WORLD_Y, WORLD_W, WORLD_H, color: FLOOR)

    renderer.rect(WORLD_X, WORLD_Y, WORLD_W, THICK, color: EDGE)
    renderer.rect(WORLD_X, WORLD_Y + WORLD_H - THICK, WORLD_W, THICK, color: EDGE)
    renderer.rect(WORLD_X, WORLD_Y, THICK, WORLD_H, color: EDGE)
    renderer.rect(WORLD_X + WORLD_W - THICK, WORLD_Y, THICK, WORLD_H, color: EDGE)

    renderer.text('Arrows / WASD walk the pale circle — the rectangles need nobody', 12, 12)
    renderer.text('They wrap at the outline, which is the world and not the window', 12, 34)
    renderer.text('Two of them spin: one component adding to angle, no shape the wiser', 12, 56)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Velocity',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
