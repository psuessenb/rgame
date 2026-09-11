# frozen_string_literal: true

# Input glyphs — the prompt matches the thing in your hand.
#
# Run it:
#
#   ruby examples/input_glyphs/main.rb
#
# Arrow keys, WASD or a stick walk the hero. Press **A** on a controller and the
# panel switches to controller prompts; press **Enter** or **Space** on the
# keyboard and it switches back. It exercises:
#   - Controls.gamepad? — is the device in the player's hands a controller;
#   - InputMap#button_for — which of an action's ids that device can press;
#   - Engine::Players with one seat — `on_unassigned_input` defaulting to
#     `:takeover`, which is what keyboard-to-controller switching *is*;
#   - renderer.sprite — a glyph sheet indexed by button id.
#
# ## Nothing here listens for a controller being plugged in
#
# A game with one seat treats an unassigned device that somebody uses as *that
# player* picking it up, rather than as a second player arriving. So plugging a
# pad in does nothing at all, and pressing A on it hands the seat over: the
# player's `device` changes, and every prompt below follows it on the next frame.
#
# That is the engine's `:takeover` policy, and a one-seat game gets it without
# asking. `examples/split_screen` is the other setting of the same dial.
#
# **It switches back, through `ui_confirm` and nothing else.** Once the pad has
# the seat the keyboard is unassigned, so Enter or Space hands it back — but W
# does not, and neither does any other key. One action rather than "any input" is
# deliberate: a stick resting a little off centre must never count as somebody
# picking up a controller, and the rule is the same rule in both directions. A
# game that genuinely wants any key to return to the keyboard sets
# `players.on_unassigned_input = :ignore` and calls `players.seat(device)` on its
# own terms.
#
# ## One entry lists both, and a prompt has to undo that
#
# An `InputMap` entry names the key *and* the pad button for one action:
#
#     fire: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
#
# That is right for reading input — a device only answers for its own kind of id,
# so polling needs no branch — and exactly wrong for showing it. A prompt saying
# "press Space or A" tells the player about hardware they are not holding.
#
# `InputMap#button_for(action, device)` is the question the other way round: of
# the ids bound to this action, which one can *this* device press? It compares
# `Controls.pad_button?(id)` against `Controls.gamepad?(device)` — two id spaces
# that were made disjoint for exactly this — and gives back the first that
# matches, or nil.
#
# The first match is not arbitrary: `ui_confirm` lists Return before Space, so
# the panel says Return. The order an entry is written in is the order a prompt
# prefers.
#
# ## A glyph is a button id rendered as a picture
#
# Which makes the whole of it a lookup keyed by that id:
#
#     GLYPH_COLUMN = { Controls::KEY_SPACE => 0, ... }.freeze
#
# The sheet is one row of 64x64 frames, drawn with `renderer.sprite`, and the
# table says which column belongs to which id. There is no cleverness to it, and
# that is the point — the hard part was deciding *which* id to draw, and that
# happened above.
#
# The table covers the five ids this example's three actions can produce. A game
# with a rebinding screen needs one entry per id it lets a player bind, or a text
# fallback for the ones it has no art for; here a missing glyph draws nothing and
# leaves the label to speak for itself.
#
# ## What it does not solve
#
# **Axes.** Walking is bound to `move_x`/`move_y`, which are a stick and pairs of
# keys rather than buttons, so `button_for` gives nil for them and the panel does
# not try: the picture for "the left stick" or "the arrow keys" is one image
# standing for several ids, which is a different question with a different
# answer. The three prompts here are all single buttons.
#
# **Which controller.** The pad glyphs are Xbox-shaped because SDL's button names
# are (`PAD_A`, `PAD_B`), and a PlayStation pad reports the same ids under
# different labels. Shipping a second sheet and choosing between them by
# controller name is a real thing games do, and it is another table keyed by the
# same ids.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

SPEED = 90.0

# The glyph sheet: one row of 64x64 frames, in the order examples/assets/README.md
# lists them.
SHEET  = 'glyphs.json'
GLYPH  = 64

# A prompt is a picture of a button, so the table is keyed by button id. These
# five are what this example's three actions resolve to on the two kinds of
# device.
GLYPH_COLUMN = {
  RGame::Util::Controls::KEY_SPACE => 0,
  RGame::Util::Controls::KEY_RETURN => 1,
  RGame::Util::Controls::KEY_ESCAPE => 2,
  RGame::Util::Controls::PAD_A => 3,
  RGame::Util::Controls::PAD_B => 4
}.freeze

# The panel: three actions, and the button each one is on for the device the
# player is holding right now.
class Prompts < RGame::Engine::Node2D
  PANEL = RGame::Util::Color.new(18, 22, 30, 220)
  INK   = RGame::Util::Color.new(228, 232, 240)
  DIM   = RGame::Util::Color.new(150, 158, 172)

  # The action to ask about, and what this game calls it. Both fixed: the label
  # is the game's word for the action, and the button is what changes.
  ROWS = [[:ui_confirm, 'Confirm'], [:ui_cancel, 'Cancel'], [:fire, 'Wave']].freeze

  # A constant string chosen by state rather than a string built from it — there
  # is nothing here to cache, and a CachedLabel whose block returns a constant is
  # strictly worse to read.
  DEVICE_NAME = { false => 'Keyboard', true => 'Controller' }.freeze

  WIDTH_PX = 300
  ROW_H    = 72
  PAD      = 14
  HEADER_H = 34

  def on_add
    # One seat, so the player is the primary one. Held rather than looked up per
    # frame: which player this is cannot change, while the device they hold can.
    @player = system(RGame::Engine::Players).primary
  end

  def on_draw(renderer, _view)
    device = @player.device
    renderer.rect(0, 0, WIDTH_PX, HEADER_H + (ROWS.size * ROW_H), color: PANEL)
    renderer.text(DEVICE_NAME.fetch(RGame::Util::Controls.gamepad?(device)), PAD, PAD, color: INK)

    ROWS.each_with_index do |(action, label), index|
      draw_row(renderer, action, label, device, HEADER_H + (index * ROW_H))
    end
  end

  private

  # hot-path
  def draw_row(renderer, action, label, device, y)
    id = @player.input_map.button_for(action, device)
    column = GLYPH_COLUMN[id]
    renderer.sprite(SHEET, 0, column, PAD, y) unless column.nil?
    renderer.text(label, PAD + GLYPH + PAD, y + ((GLYPH - 16) / 2), color: id.nil? ? DIM : INK)
  end
end

# Something to walk, so that picking up a controller has a reason to happen.
# `examples/walk`'s hero, kept inside the window.
class Hero < RGame::Engine::Node2D
  def initialize(**)
    super
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED))
    add_component(RGame::Engine::Components::PlayerController.new)
  end

  def on_update(_dt)
    self.x = x.clamp(0, WIDTH - width)
    self.y = y.clamp(0, HEIGHT - height)
  end
end

class Scene < RGame::Engine::Node2D
  BACKDROP = RGame::Util::Color.new(30, 36, 46)
  MARGIN   = 16

  # The hero first, so the panel is drawn over them rather than under: a node
  # draws before its later siblings, and the two do overlap once the hero is
  # walked into the corner.
  def on_add
    add_node(Hero.new(x: 470, y: 300))
    add_node(Prompts.new(x: MARGIN, y: MARGIN))
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BACKDROP)
    renderer.text('Press A on a controller to hand it the seat', MARGIN, view.height - 52)
    renderer.text('Enter or Space on the keyboard takes it back', MARGIN, view.height - 30)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Input glyphs',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
