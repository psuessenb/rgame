# frozen_string_literal: true

# Menu navigation — more than one screen, and settings that are real.
#
# Run it:
#
#   ruby examples/menu_navigation/main.rb
#
# Up and down move the focus, Enter or A chooses, Escape goes back. On the
# settings screen **left and right change the value under the cursor**. Quit,
# run it again, and the settings are where you left them. It exercises:
#   - Scene::SceneStack — push, pop and replace, and the difference between them;
#   - UI::OptionItem — a menu row whose value is chosen from a list;
#   - Util::SaveFile holding settings rather than a saved game;
#   - RGame::Game's fullscreen, scale_mode and audio volume, driven from a menu.
#
# ## Push and replace are different questions, and this file asks both
#
# A SceneStack updates only its top scene but **draws all of them**, and that is
# what makes it a stack rather than a variable holding the current screen. So
# the choice between pushing and replacing is really one question: *should the
# thing underneath still be there?*
#
# Settings is **pushed** over the title, and the title keeps drawing behind the
# panel — that is why the settings screen needs a panel at all. Choosing Back
# **pops**, and the title is still exactly as it was, because it was never taken
# apart. Play **replaces** the title, because a title screen behind a running
# game is nothing but a thing to draw.
#
# ## Nothing switches scenes while the tree is being walked
#
# `Shell#go` records a request and `Shell#on_update` carries it out. A menu item
# activates during `control`, which is the middle of a traversal of the very
# subtree the switch is about to take apart, and unbuilding a tree while walking
# it is the sort of bug that shows up somewhere else entirely.
#
# Deferring costs one line and buys a second thing for free: two requests in one
# tick — the Back item and Escape both firing — collapse into one transition
# rather than two pops.
#
# ## Settings apply now and persist immediately
#
# Each row applies its change the moment it is made: the volume you hear is the
# volume shown, and the window changes as you move the cursor. That is what a
# settings screen is *for*, and it removes the whole apply/cancel/revert
# question this example has no business answering.
#
# The file is written on every change too. A settings screen changes a handful
# of values a handful of times, and `SaveFile` writes atomically, so there is
# nothing to be gained by batching it and one less rule about when a save
# happens.
#
# ## A settings file is untrusted input
#
# `Settings#load` checks every value against the list the menu actually offers
# and falls back to the default for anything else. That is not defensive habit.
# `Game#scale_mode=` raises on a mode it does not know, so a hand-edited file,
# a copy from a newer version of the game, or a `null` where a number should be
# is otherwise a game that cannot be started — and the player's only fix is to
# find and delete a file nobody told them about.
#
# `UI::OptionItem#value=` has the same shape for the same reason: a value the
# list no longer offers leaves the row where it is instead of raising.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

UI = RGame::Engine::UI

# The same 8:5 `examples/fullscreen` uses, and for the same reason: this screen
# offers a scale mode as a setting, so the four choices have to look like four
# different things. A logical size that matched the display's aspect ratio would
# make `:stretch` and `:letterbox` identical, and one that divided it evenly
# would bring `:integer` in with them.
WIDTH  = 512
HEIGHT = 320
ASSETS = File.expand_path('../assets', __dir__)

BLIP = 'blip.ogg'

# The game's settings, backed by one JSON file.
#
# Plain Ruby and no node: settings are a value a scene reads, not a thing in the
# tree. It is handed to the scenes that need it rather than reached for through
# a global, which is also what lets a spec build one over a temporary directory.
class Settings
  # Everything about a setting in one place: what it is called, what it may be,
  # what each value is written as, and what it falls back to. The menu builds
  # its rows from this and `load` validates the file against it, so a row can
  # never offer a value the file would reject, or the other way round.
  #
  # The captions are made by `display` once per value, when a row is built,
  # rather than inside a draw method — see UI::OptionItem, and
  # Game/NoInterpolationInHotPath for why a label built while drawing is a bug
  # rather than a style.
  #
  # **These live in a class rather than at the top of the file, and a proc is
  # why.** A block written at the top level of a script captures that script's
  # local variables — `game`, down at the bottom, among them — and a constant
  # holding that block keeps them for the life of the process. The window is
  # then never released, which shows up not as a leak but as a crash on the way
  # out. Inside a class body there is no such scope to capture.
  ROWS = {
    fullscreen: { label: 'Fullscreen', default: false,
                  values: [false, true].freeze,
                  display: ->(on) { on ? 'on' : 'off' } },
    scale: { label: 'Scale mode', default: :letterbox,
             values: RGame::Engine::Presentation::MODES,
             display: :to_s.to_proc },
    volume: { label: 'Volume', default: 75,
              values: [0, 25, 50, 75, 100].freeze,
              display: ->(percent) { "#{percent}%" } }
  }.freeze

  def initialize(save)
    @save = save
    @values = load
  end

  def [](key) = @values.fetch(key)

  # Writes the whole file on every change. See the note at the top of this file.
  def []=(key, value)
    @values[key] = value
    @save.write(@values)
  end

  # Volume reaches the device as a gain, where 1.0 is unchanged.
  def volume_gain = @values.fetch(:volume) / 100.0

  private

  # Anything the menu does not offer becomes the default. See "A settings file
  # is untrusted input".
  def load
    stored = @save.read
    ROWS.to_h do |key, row|
      value = coerce(key, stored[key])
      [key, row.fetch(:values).include?(value) ? value : row.fetch(:default)]
    end
  end

  # JSON has no Symbol, so `:letterbox` comes back as `"letterbox"`. Converting
  # here rather than at the call site keeps the rest of the file working in the
  # values the game actually uses.
  def coerce(key, value) = key == :scale && value.is_a?(String) ? value.to_sym : value
end

# The root: scene navigation, and the settings every screen shares.
class Shell < RGame::Engine::Node2D
  def initialize(settings:)
    super()
    @settings = settings
    @stack = add_component(RGame::Engine::Scene::SceneStack.new)
    @pending = nil
  end

  def on_add = show(:title)

  # `push` keeps what is under it; `replace` does not; `pop` returns to it. Each
  # one records the request and returns, for the reason at the top of this file.
  def show(name) = @pending = [:push, name]
  def swap(name) = @pending = [:replace, name]
  def back = @pending = [:pop, nil]

  # Runs after the active scene's own update has unwound, so the tree being
  # rebuilt is not one the traversal is standing in.
  def on_update(_dt)
    return unless @pending

    action, name = @pending
    @pending = nil
    case action
    when :push then @stack.push(build(name))
    when :replace then @stack.replace(build(name))
    when :pop then @stack.pop
    end
  end

  private

  def build(name)
    case name
    when :title then TitleScene.new
    when :settings then SettingsScene.new(settings: @settings)
    when :play then PlayScene.new
    end
  end
end

# The title: a heading and three choices.
#
# The menu sits at a fixed inset rather than centred, which is the same
# limitation `examples/game_menu` runs into — centring needs the region's size
# and that only arrives at draw time. See docs/api/ui.md, "What this is not".
class TitleScene < RGame::Engine::Node2D
  MENU_X = 56
  MENU_Y = 104
  ITEM_WIDTH = 240
  ITEM_HEIGHT = 34

  def on_add
    menu = add_node(UI::Menu.new(x: MENU_X, y: MENU_Y,
                                 item_width: ITEM_WIDTH, item_height: ITEM_HEIGHT))
    menu.add_item('Play').on_activated { root.swap(:play) }
    menu.add_item('Settings').on_activated { root.show(:settings) }
    menu.add_item('Quit').on_activated { root.context.close }
  end

  def on_draw(renderer, _view)
    renderer.text('Menu navigation', MENU_X, 44)
    renderer.text('Up and down to move, Enter to choose', MENU_X, 68)
  end
end

# The settings screen, pushed over the title.
#
# It draws a panel because the title is still drawing behind it — that is the
# visible half of what pushing rather than replacing means.
class SettingsScene < RGame::Engine::Node2D
  PANEL_X = 28
  PANEL_Y = 28
  PANEL_WIDTH = WIDTH - (PANEL_X * 2)
  PANEL_HEIGHT = HEIGHT - (PANEL_Y * 2)
  PADDING = 18
  ITEM_WIDTH = PANEL_WIDTH - (PADDING * 2)
  ITEM_HEIGHT = 34

  def initialize(settings:, **)
    super(**)
    @settings = settings
  end

  def on_add
    @menu = add_node(UI::Menu.new(x: PANEL_X + PADDING, y: PANEL_Y + PADDING + 30,
                                  item_width: ITEM_WIDTH, item_height: ITEM_HEIGHT))
    Settings::ROWS.each { |key, row| option(key, row) }
    @menu.add_item('Back').on_activated { root.back }
  end

  # Escape does what Back does, because that is what every player will try
  # first. Both go through the same deferred request, so pressing one on the
  # same tick as the other is still one pop.
  def on_control(actions)
    root.back if actions.pressed?(:ui_cancel)
  end

  def on_draw(renderer, _view)
    renderer.nine_slice(:panel, PANEL_X, PANEL_Y, PANEL_WIDTH, PANEL_HEIGHT)
    renderer.text('Settings — left and right change a value', PANEL_X + PADDING,
                  PANEL_Y + PADDING, z: 1)
  end

  private

  # One row per setting, built from the same table the file is validated
  # against, and starting on whatever is currently in force.
  def option(key, row)
    values = row.fetch(:values)
    item = @menu.add_option(row.fetch(:label), values: values, display: row.fetch(:display),
                                               index: values.index(@settings[key]) || 0)
    item.on_changed { |value| change(key, value) }
  end

  def change(key, value)
    @settings[key] = value
    apply(key, value)
  end

  # `root.context` is the Game. A node may not *name* RGame::Core, but it may
  # call methods on an object it is handed — the same duck-typing it uses on a
  # renderer, and what `examples/fullscreen` does with the same object.
  def apply(key, value)
    game = root.context
    case key
    when :fullscreen then game.fullscreen = value
    when :scale then game.scale_mode = value
    when :volume then game.audio.volume = value / 100.0
    end
  end
end

# Somewhere for the settings to be true: a marker sweeping the view, and a sound
# on demand so the volume is something you can hear rather than read.
class PlayScene < RGame::Engine::Node2D
  MARGIN = 34
  RADIUS = 16
  SPEED = 0.6 # sweeps per second
  DISC = RGame::Util::Color.new(180, 160, 240)
  EDGE = RGame::Util::Color.new(120, 200, 255)
  THICK = 3

  def initialize(**)
    super
    @phase = 0.0
  end

  def on_control(actions)
    RGame::Engine::AudioBus.play_sound(BLIP) if actions.pressed?(:ui_confirm)
    root.swap(:title) if actions.pressed?(:ui_cancel)
  end

  # The sweep is state advanced by dt, and where it lands on screen is worked
  # out from the view at draw time — so it follows a window that grew without
  # anything here listening for the change.
  def on_update(dt)
    @phase = (@phase + (dt * SPEED)) % 2.0
  end

  def on_draw(renderer, view)
    right = view.width - MARGIN
    bottom = view.height - MARGIN
    renderer.line(MARGIN, MARGIN, right, MARGIN, thickness: THICK, color: EDGE)
    renderer.line(MARGIN, bottom, right, bottom, thickness: THICK, color: EDGE)

    travelled = @phase > 1.0 ? 2.0 - @phase : @phase # there, then back
    renderer.circle(MARGIN + (travelled * (right - MARGIN)), view.height / 2,
                    RADIUS, color: DISC)

    renderer.text('Enter makes a noise — Escape returns to the title', MARGIN, 16)
  end
end

# `dir:` is normally left out and the file lands in the platform's own data
# directory. It is overridable so a driven run writes somewhere disposable
# instead of into the home directory of whoever is running it.
settings = Settings.new(
  RGame::Util::SaveFile.new('settings.json', game: 'rgame-examples',
                                             dir: ENV.fetch('RGAME_SAVE_DIR', nil))
)

# Fullscreen and the scale mode are **constructor arguments**, not something
# applied on the first tick: a window switched after it is up shows one windowed
# frame first, and that flash reads as a broken startup. See
# `examples/fullscreen`. Volume has no such problem — there is no first frame of
# sound — so it is set on the device below.
game = RGame::Game.new(
  root: Shell.new(settings: settings),
  caption: 'Menu navigation',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  fullscreen: settings[:fullscreen],
  scale_mode: settings[:scale]
)

game.audio.volume = settings.volume_gain

# A nine-slice id names an *element of an atlas* rather than a file, so there is
# nothing for the asset manager to resolve `:panel` to on demand. Registering
# the atlas binds every element in it, which is what the menu rows draw
# themselves from as well.
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui.json'))

game.start
