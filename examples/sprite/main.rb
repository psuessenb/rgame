# frozen_string_literal: true

# Sprite — one frame, drawn at a node, with no animation behind it.
#
# Run it:
#
#   ruby examples/sprite/main.rb
#
# Left and right turn the middle sprite; up and down resize it. It exercises:
#   - Components::Sprite — a picture drawn at the node it is attached to,
#     centred on it with `anchor: :center`;
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
# The component draws against the node's origin, and only its `anchor:` moves
# the picture from there. These sprites pass `anchor: :center`, so the picture's
# centre is the origin and the draw comes down to:
#
#     renderer.image(@id, 0, 0, scale: @scale, z: @layer)
#
# `Node2D#draw` has already pushed this node's transform onto the renderer, so
# drawing at the origin *is* drawing at the node, turned by however much the node
# is turned. Hold left and watch: nothing inside Components::Sprite knows that an
# angle exists, and the sprite turns anyway. It turns about its centre because a
# node turns about its origin. The default anchor, `:bottom`, would swing the
# picture round its bottom edge instead.
#
# Writing `node.x` there would apply the position a second time, which is what
# `Game/DrawInLocalSpace` refuses — `world_x` included, and for the same reason.
#
# ## Two numbers called z, and the bottom row separates them
#
# A **node's** `z` orders it against its siblings: which of two nodes is drawn
# first. A **component's** `z:` is an offset inside that one node's own slot, so
# it can only ever settle the order of what a single node draws — against its own
# other components, and against its own `_draw`. It cannot reach the next node.
#
# The bottom node draws a panel from `_draw` and hangs a sprite on itself, and
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

# The example's own module. `Engine`, `Util`, `UI` and `Components` inside it
# stand for rgame's namespaces of the same names, and every name the example
# defines stays off the top level. docs/api/README.md says why, under "A game's
# own module".
module SpriteExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

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
  class Turntable < Engine::Node2D
    def initialize(**)
      super(width: FRAME_W, height: FRAME_H, **)
      @turn = 0.0
      @resize = 0.0
    end

    def _enter_tree
      @sprite = add_component(Components::Sprite.new(id: STILL, scale: START_SCALE, anchor: :center))
    end

    # Axes, not buttons: `move_x` and `move_y` come from the default map already
    # bound to the arrows, WASD and a left stick, so this example declares no input
    # of its own. Screen y grows downward, so up reads negative and is subtracted.
    def _control(actions)
      @turn = actions.axis(:move_x)
      @resize = actions.axis(:move_y)
    end

    def _update(dt)
      self.angle += @turn * TURN_SPEED * dt
      @sprite.scale = (@sprite.scale - (@resize * GROW_SPEED * dt)).clamp(MIN_SCALE, MAX_SCALE)
    end
  end

  # The bottom row: one node, two things drawn, and a z that decides which wins.
  class Layered < Engine::Node2D
    PANEL = Util::Color.new(196, 92, 64)
    PANEL_W = 132
    PANEL_H = 78
    SCALE = 3.0
    # Above the 50 a shape is drawn at, inside this node's slot. Drop it to 0 and
    # the sprite disappears behind the panel; nothing else about the frame changes.
    ABOVE_PANEL = 60

    def initialize(**)
      super(width: FRAME_W, height: FRAME_H, **)
    end

    def _enter_tree
      add_component(Components::Sprite.new(id: STILL, scale: SCALE, z: ABOVE_PANEL, anchor: :center))
    end

    # Centred on this node's own origin, which is where the traversal has already
    # put the renderer — the same reason the component draws at (0, 0).
    def _draw(renderer, _view)
      renderer.rect(-PANEL_W / 2, -PANEL_H / 2, PANEL_W, PANEL_H, color: PANEL)
    end
  end

  class Scene < Engine::Node2D
    BACKDROP = Util::Color.new(38, 42, 52)
    SHEET_X = 24
    SHEET_Y = 60

    def initialize
      super
      @help = Engine::Text.new('help.keys')
      @whole = Engine::Text.new('captions.whole')
      @frame = Engine::Text.new('captions.frame')
      @above = Engine::Text.new('captions.above')
    end

    def _enter_tree
      add_node(Turntable.new(x: WIDTH / 2, y: 230))
      add_node(Layered.new(x: WIDTH / 2, y: 400))
    end

    def _draw(renderer, view)
      renderer.rect(0, 0, view.width, view.height, color: BACKDROP)

      # A String is a path, resolved through the asset manager on first use and
      # remembered. Drawn at its natural size, so this is the file itself — six
      # columns of walk frames over three rows, and the frame below is the first
      # cell of it.
      renderer.image_at(SHEET, SHEET_X, SHEET_Y)

      renderer.text(@help, 12, 12)
      renderer.text(@whole, SHEET_X, SHEET_Y - 18)
      renderer.text(@frame, SHEET_X, 170)
      renderer.text(@above, SHEET_X, 330)
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Scene.new,
      caption: 'Sprite',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      locales: LOCALES
    )

    # The other id space. A Symbol is a name this game chose, so nothing can resolve
    # it and it has to be bound — and what it is bound to here is not a file at all
    # but a *view* into one. `subimage` shares the uploaded texture rather than
    # decoding the PNG again, so slicing a sheet into frames costs nothing.
    game.renderer.register_image(STILL, game.assets.image(SHEET).subimage(0, 0, FRAME_W, FRAME_H))

    game.start
  end
end

SpriteExample.start
