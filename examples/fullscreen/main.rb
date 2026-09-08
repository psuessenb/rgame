# frozen_string_literal: true

# Fullscreen — starting fullscreen, and switching while the game runs.
#
# Run it two ways:
#
#   ruby examples/fullscreen/main.rb                    # opens windowed
#   RGAME_FULLSCREEN=1 ruby examples/fullscreen/main.rb # opens fullscreen
#
# F (or Y on a pad) switches either way. The border tracks the window, so the
# size change is visible without reading a number. It exercises:
#   - RGame::Game.new(fullscreen:) — the window opens that way;
#   - App#fullscreen? / #fullscreen= — switching at any time;
#   - the `view` a node is drawn with — where its size comes from;
#   - InputMap.default.merge — declaring one action of your own.
#
# ## Two ways in, because games need both
#
# **Opening fullscreen is a constructor argument, not a switch afterwards.**
# Both end up fullscreen, but a switch made after the window is up shows one
# windowed frame first — the flash that reads as a broken startup. Passing
# `fullscreen: true` creates the window fullscreen and there is no first frame
# to see. A game whose settings file says fullscreen should pass the setting
# here, not apply it on the first tick.
#
# **A game need not offer a way back.** Nothing here is required: leave the
# toggle out and the game runs fullscreen for its whole life, which is a
# perfectly ordinary choice.
#
# ## Desktop fullscreen, not a mode change
#
# The window takes the whole screen at the screen's own resolution. Nothing asks
# the display to switch mode, so the change is instant, costs no mode list to
# choose from, and leaves every other window where it was. What a game gets is a
# bigger view rather than a different one.
#
# ## Layout comes from the view, not from a constant
#
# `WIDTH` and `HEIGHT` below are what the *window* opens at and returns to. They
# are not what to draw against: fullscreen makes the view the size of the
# screen. Every `draw` is handed the `view` it is being drawn into, and
# `view.width` / `view.height` are the only honest source for "how big is the
# thing I am drawing in" — which is why the border below follows the switch with
# nothing listening for it.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

Controls = RGame::Util::Controls

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

# Set in the environment so one file can demonstrate both openings without being
# edited. A real game reads this from its settings file — see the plan's
# `examples/save_load`.
START_FULLSCREEN = ENV.fetch('RGAME_FULLSCREEN', '0') != '0'

class Scene < RGame::Engine::Node2D
  INSET  = 24
  MARK   = 40
  THICK  = 3
  EDGE   = RGame::Util::Color.new(120, 200, 255)
  CORNER = RGame::Util::Color.new(255, 210, 120)

  # One frozen string per state rather than one built per frame: a label made
  # with interpolation in a draw method allocates a String every frame, which is
  # what Game/NoInterpolationInHotPath refuses.
  STATE = { true => 'fullscreen — F returns to a window',
            false => 'windowed — F goes fullscreen' }.freeze

  def on_control(actions)
    return unless actions.pressed?(:fullscreen)

    # `context` is the Game, which is an App. A node may not *name* RGame::Core,
    # but it may call methods on an object it is handed — the same duck-typing a
    # node uses on the renderer.
    app = root.context
    app.fullscreen = !app.fullscreen?
  end

  # `view` is the region being drawn into. Under fullscreen it is the screen;
  # windowed it is the window. Reading it rather than WIDTH/HEIGHT is the whole
  # reason the border below keeps up.
  def on_draw(renderer, view)
    right = view.width - INSET
    bottom = view.height - INSET

    renderer.line(INSET, INSET, right, INSET, thickness: THICK, color: EDGE)
    renderer.line(INSET, bottom, right, bottom, thickness: THICK, color: EDGE)
    renderer.line(INSET, INSET, INSET, bottom, thickness: THICK, color: EDGE)
    renderer.line(right, INSET, right, bottom, thickness: THICK, color: EDGE)

    # Corner marks, so the border is not just a rectangle of unknown size: they
    # stay put while the edges between them move.
    renderer.rect(INSET, INSET, MARK, THICK, color: CORNER)
    renderer.rect(INSET, INSET, THICK, MARK, color: CORNER)
    renderer.rect(right - MARK, bottom - THICK, MARK, THICK, color: CORNER)
    renderer.rect(right - THICK, bottom - MARK, THICK, MARK, color: CORNER)

    renderer.text(STATE.fetch(root.context.fullscreen?), INSET + 12, INSET + 12)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Fullscreen',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  fullscreen: START_FULLSCREEN,
  # :fullscreen is this game's own action; everything else comes from the
  # default map. F is a convention players already know.
  input_map: RGame::Engine::InputMap.default.merge(
    fullscreen: { buttons: [Controls::KEY_F, Controls::PAD_Y] }
  )
)

game.start
