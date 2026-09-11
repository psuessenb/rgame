# frozen_string_literal: true

# Fullscreen — starting fullscreen, and switching while the game runs.
#
# Run it windowed or fullscreen, and start in any scale mode:
#
#   ruby examples/fullscreen/main.rb
#   RGAME_FULLSCREEN=1 ruby examples/fullscreen/main.rb
#   RGAME_SCALE=integer ruby examples/fullscreen/main.rb
#
# **F** (or Y on a pad) switches fullscreen. **Left and right** cycle through all
# four scale modes. Watch the circle: it is round in three of them and an ellipse
# in `:stretch`, which is the whole difference between uniform and per-axis
# scaling in one shape. It exercises:
#   - RGame::Game.new(fullscreen:) — the window opens that way;
#   - App#fullscreen? / #fullscreen= — switching at any time;
#   - RGame::Game#scale_mode= — switching that at any time too;
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
# ## Two answers to a bigger window, and this file shows both
#
# With no `scale_mode`, the view *is* the window: it grows, and the border below
# grows with it because it is drawn from `view.width`. Extra screen becomes
# extra room. That is what a HUD or a menu wants.
#
# With a `scale_mode`, `width` and `height` stop describing the window and start
# describing the game. The view stays 512x320 however big the window is, and the
# whole frame is scaled onto it — so the border stays exactly where it is and
# gets bigger. That is what a play area wants, and it is the only one of the two
# that saves a game whose layout is hardcoded.
#
# ## Why 512x320, which is nobody's screen
#
# The size is picked to make the four modes *differ*, which is the opposite of
# what a real game wants and exactly what an example about them needs.
#
# A logical size that shares its aspect ratio with the display makes `:stretch`
# and `:letterbox` compute the same numbers, and one that divides the display
# evenly makes `:integer` agree with both. Choose 640x360 on a 1920x1080 screen
# and all three land on 3.000x3.000 — four modes, three of them identical, and
# nothing to look at. **The prettiest resolution is the one that teaches least.**
#
# 8:5 matches no common display, so `:stretch` always distorts. And the fit is
# never a whole number on a 16:9 screen, so `:integer` always gives up some
# screen that `:letterbox` keeps. Measured, on the sizes people actually own:
#
#   screen       stretch        letterbox   integer
#   1920x1080    3.75 x 3.375   3.375       3
#   2560x1440    5.00 x 4.500   4.500       4
#   3840x2160    7.50 x 6.750   6.750       6
#
# A game would choose the other way round. Pick the logical size so that the
# scale on your players' screens is a whole number, and `:integer` costs nothing
# at all.
#
# Cycling through the four with left and right is the quickest way to see what
# each costs:
#
#   :disabled   the border grows to the window; nothing is scaled
#   :stretch    fills the window; the circle goes oval
#   :letterbox  uniform, centred, bars on two sides
#   :integer    the same but whole-number only, so usually wider bars
#
# `:integer` is what keeps pixel art crisp: at 1.875x some source pixels cover
# two screen pixels and some cover one, and the unevenness crawls as things
# move. It costs screen — see RGame::Engine::Presentation for the measurements
# against real screen sizes.
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

# Deliberately not a shape any display has — see the note above on why an
# example about scale modes wants a resolution that scales *badly*.
WIDTH  = 512
HEIGHT = 320
ASSETS = File.expand_path('../assets', __dir__)

# Set in the environment so one file can demonstrate both openings without being
# edited. A real game reads this from its settings file — see the plan's
# `examples/save_load`.
START_FULLSCREEN = ENV.fetch('RGAME_FULLSCREEN', '0') != '0'

# :disabled (the default), :stretch, :letterbox or :integer. A real game reads
# this from its settings the same way it reads the fullscreen flag.
SCALE_MODE = ENV.fetch('RGAME_SCALE', 'disabled').to_sym

class Scene < RGame::Engine::Node2D
  INSET  = 24
  MARK   = 40
  THICK  = 3
  EDGE   = RGame::Util::Color.new(120, 200, 255)
  CORNER = RGame::Util::Color.new(255, 210, 120)

  DISC = RGame::Util::Color.new(180, 160, 240)

  # Taken from the engine rather than written out, so this example cannot fall
  # behind the modes that actually exist.
  MODES = RGame::Engine::Presentation::MODES

  # One frozen string per state rather than one built per frame: a label made
  # with interpolation in a draw method allocates a String every frame, which is
  # what Game/NoInterpolationInHotPath refuses.
  STATE = { true => 'fullscreen — F returns to a window',
            false => 'windowed — F goes fullscreen' }.freeze
  MODE_LABEL = {
    disabled: 'left/right — scale_mode :disabled, the view is the window',
    stretch: 'left/right — scale_mode :stretch, fills and distorts',
    letterbox: 'left/right — scale_mode :letterbox, uniform with bars',
    integer: 'left/right — scale_mode :integer, whole-number scale only'
  }.freeze

  def initialize(**)
    super
    @mode_index = MODES.index(SCALE_MODE) || 0
  end

  def on_control(actions)
    # `context` is the Game, which is an App. A node may not *name* RGame::Core,
    # but it may call methods on an object it is handed — the same duck-typing a
    # node uses on the renderer.
    if actions.pressed?(:fullscreen)
      app = root.context
      app.fullscreen = !app.fullscreen?
    end

    # ui_left and ui_right come from the default map, so cycling needs no action
    # of its own.
    cycle_mode(-1) if actions.pressed?(:ui_left)
    cycle_mode(1) if actions.pressed?(:ui_right)
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

    # Round under every mode but :stretch, which scales the axes by different
    # factors and turns it into an ellipse. One shape says more about what a
    # mode does than the two lines of text below it.
    renderer.circle(view.width / 2, view.height / 2, view.height / 5, color: DISC)

    renderer.text(STATE.fetch(root.context.fullscreen?), INSET + 12, INSET + 12)
    renderer.text(MODE_LABEL.fetch(MODES[@mode_index]), INSET + 12, INSET + 34)
  end

  private

  def cycle_mode(step)
    @mode_index = (@mode_index + step) % MODES.length
    root.context.scale_mode = MODES[@mode_index]
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Fullscreen',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  fullscreen: START_FULLSCREEN,
  scale_mode: SCALE_MODE,
  # :fullscreen is this game's own action; everything else comes from the
  # default map. F is a convention players already know.
  input_map: RGame::Engine::InputMap.default.merge(
    fullscreen: { buttons: [Controls::KEY_F, Controls::PAD_Y] }
  )
)

game.start
