# frozen_string_literal: true

# Sprite — one frame, drawn at a node, with no animation behind it.
#
# Run it:
#
#   ruby examples/sprite/main.rb
#
# Left and right turn the middle sprite; up and down resize it. It exercises:
#   - Components::Sprite — a picture drawn at the node it is attached to;
#   - Image#subimage — one cell of a sheet, as a view costing no second decode;
#   - renderer.register_image — binding a Symbol to an image the game chose;
#   - the two id spaces, a String path and a registered Symbol, in one file.
#
# ## Most things in a game are this
#
# `examples/walk` uses Components::AnimatedSprite, which carries an AnimationSet,
# a current animation name and an elapsed time. Take all of that away and what is
# left is this: a picture, at a node. A crate, a pickup, a rock and a tree want
# exactly that and nothing more.
#
# ## It passes no position and no angle, and that is the whole trick
#
# The component's draw is one line, and both coordinates in it are zero:
#
#     renderer.image(@id, 0, 0, scale: @scale, z: @layer)
#
# `Node2D#draw` has already pushed this node's transform onto the renderer, so
# drawing at the origin *is* drawing at the node, turned by however much the node
# is turned. Hold left and watch: nothing inside Components::Sprite knows that an
# angle exists, and the sprite turns anyway.
#
# Writing `node.x` there would apply the position a second time, which is what
# `Game/DrawInLocalSpace` refuses — `world_x` included, and for the same reason.
#
# ## Two numbers called z, and the bottom row separates them
#
# A **node's** `z` orders it against its siblings: which of two nodes is drawn
# first. A **component's** `z:` is an offset inside that one node's own slot, so
# it can only ever settle the order of what a single node draws — against its own
# other components, and against its own `on_draw`. It cannot reach the next node.
#
# The bottom node draws a panel from `on_draw` and hangs a sprite on itself, and
# they land in one slot together. The default offsets are not equal: a shape is
# drawn at 50 and an image at 0, so the panel covers the sprite unless the sprite
# asks for more. `z: ABOVE_PANEL` is that ask, and the node did not move.
#
# ## What this does not show
#
# Culling, though Components::Sprite does it. It skips a draw whose footprint is
# outside the view — but this scene is screen space with everything well inside
# the window, so the check answers "draw" every frame. `examples/scroll_map` has
# the camera that makes the other answer visible.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

SHEET = 'hero.png'
# The grid examples/assets/hero.json describes, which is what makes cell (0, 0)
# the standing frame. Written out rather than parsed: this example is about the
# image, and reading the descriptor would be borrowing AnimatedSprite's job.
FRAME_W = 16
FRAME_H = 22

STILL = :hero_still # the Symbol the frame is registered under, below

TURN_SPEED = 120.0 # degrees per second
GROW_SPEED = 3.0   # scale steps per second
MIN_SCALE  = 1.0
MAX_SCALE  = 9.0
START_SCALE = 4.0

# The one you can play with. It holds an angle and a scale, and hands neither to
# the renderer — the component draws at the origin and the transform does the
# rest.
class Turntable < RGame::Engine::Node2D
  def initialize(**)
    super(width: FRAME_W, height: FRAME_H, **)
    @turn = 0.0
    @resize = 0.0
  end

  def on_add
    @sprite = add_component(RGame::Engine::Components::Sprite.new(id: STILL, scale: START_SCALE))
  end

  # Axes, not buttons: `move_x` and `move_y` come from the default map already
  # bound to the arrows, WASD and a left stick, so this example declares no input
  # of its own. Screen y grows downward, so up reads negative and is subtracted.
  def on_control(actions)
    @turn = actions.axis(:move_x)
    @resize = actions.axis(:move_y)
  end

  def on_update(dt)
    self.angle += @turn * TURN_SPEED * dt
    @sprite.scale = (@sprite.scale - (@resize * GROW_SPEED * dt)).clamp(MIN_SCALE, MAX_SCALE)
  end
end

# The bottom row: one node, two things drawn, and a z that decides which wins.
class Layered < RGame::Engine::Node2D
  PANEL = RGame::Util::Color.new(196, 92, 64)
  PANEL_W = 132
  PANEL_H = 78
  SCALE = 3.0
  # Above the 50 a shape is drawn at, inside this node's slot. Drop it to 0 and
  # the sprite disappears behind the panel; nothing else about the frame changes.
  ABOVE_PANEL = 60

  def initialize(**)
    super(width: FRAME_W, height: FRAME_H, **)
  end

  def on_add
    add_component(RGame::Engine::Components::Sprite.new(id: STILL, scale: SCALE, z: ABOVE_PANEL))
  end

  # Centred on this node's own origin, which is where the traversal has already
  # put the renderer — the same reason the component draws at (0, 0).
  def on_draw(renderer, _view)
    renderer.rect(-PANEL_W / 2, -PANEL_H / 2, PANEL_W, PANEL_H, color: PANEL)
  end
end

class Scene < RGame::Engine::Node2D
  BACKDROP = RGame::Util::Color.new(38, 42, 52)
  SHEET_X = 24
  SHEET_Y = 60

  def on_add
    add_node(Turntable.new(x: WIDTH / 2, y: 230))
    add_node(Layered.new(x: WIDTH / 2, y: 400))
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BACKDROP)

    # A String is a path, resolved through the asset manager on first use and
    # remembered. Drawn at its natural size, so this is the file itself — six
    # columns of walk frames over three rows, and the frame below is the first
    # cell of it.
    renderer.image_at(SHEET, SHEET_X, SHEET_Y)

    renderer.text('Left / right turn it — up / down resize it', 12, 12)
    renderer.text('hero.png whole: a String id is a path', SHEET_X, SHEET_Y - 18)
    renderer.text('one registered frame — the node holds the angle and the scale',
                  SHEET_X, 170)
    renderer.text('the sprite asks for a z above the panel its own node draws',
                  SHEET_X, 330)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Sprite',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

# The other id space. A Symbol is a name this game chose, so nothing can resolve
# it and it has to be bound — and what it is bound to here is not a file at all
# but a *view* into one. `subimage` shares the uploaded texture rather than
# decoding the PNG again, so slicing a sheet into frames costs nothing.
game.renderer.register_image(STILL, game.assets.image(SHEET).subimage(0, 0, FRAME_W, FRAME_H))

game.start
