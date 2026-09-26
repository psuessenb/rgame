# frozen_string_literal: true

# Skill bar — a row of tools, stepped through like a menu and fired by hotkey.
#
# Run it:
#
#   ruby examples/skill_bar/main.rb
#
# Left and right (or the d-pad) move along the bar, and Enter or Space (or A)
# uses the focused tool. The number keys 1 to 5 use a tool directly, wherever the
# focus is. Every use clicks. It exercises:
#   - UI::Row — a UI::Menu layout that lines its buttons up side by side;
#   - UI::Stepping — the default navigation, which takes its axis from the
#     layout, so a Row steps with left and right with nothing else said;
#   - UI::Button's `hotkey:` — an action that presses one button, focused or not;
#   - `activate_on: :press` — a use happens on the way down, as a skill should;
#   - UI::IconButton with a caption, on a disc UI::ShapeStyle — a picture with
#     its name underneath;
#   - InputMap.default.merge — declaring the five hotkey actions;
#   - a UI atlas's `images` — the five tools, cut from one strip by name.
#
# ## Two ways to press one button
#
# A farming sim's tool bar and a combat game's arts are the same menu: a row of
# buttons, one of them focused. What makes it a *bar* is that each button can
# also be reached without moving the focus at all. Press 5 with the Torch
# focused and the Watering can is used, drawn pressed for a moment, and the
# focus stays on the Torch — a hotkey is a second way to press a button, not a
# way to move to it.
#
# The two ways do not add up. Holding a number key uses the tool once, not once a
# frame; pressing a tool's number while Enter is already pressing it uses it
# once. The button remembers which of them started the press, so neither can end
# the other's.
#
# `activate_on: :press` is what a skill wants: the tool is used the frame the key
# goes down. A settings menu keeps the default, `:release`, where a player can
# still move away before letting go. Pressed stays visible for
# `UI::Button::PRESS_FEEDBACK` after a tap, because a single pressed frame is
# too short to see.
#
# ## The caption sits under the disc
#
# A captioned IconButton draws its style only in the space above the caption, so
# "Watering can", wider than the disc, reads on the background in every state.
#
# ## What this example does not solve
#
# Cooldowns — a sweep over a used tool needs an arc the renderer does not have —
# and a glyph on each button saying which key uses it. `examples/input_glyphs`
# draws the glyph for an action, if a bar wants one. The bar is also at a fixed
# position rather than centred on the view: its buttons are placed when they are
# added, and the view's size exists only at draw time.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine`, `Util`, `UI` and `Components` inside it
# stand for rgame's namespaces of the same names, and every name the example
# defines stays off the top level. docs/api/README.md says why, under "A game's
# own module".
module SkillBarExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml
  Controls = Util::Controls

  # The bar, and what was last used from it.
  class SkillBar < Engine::Node2D
    SLOT_WIDTH = 100
    SLOT_HEIGHT = 104

    # Left to right, with the action that uses each without moving focus. Each
    # image names an entry of skills.json's `images`.
    SKILLS = [
      %i[wand wand skill1],
      %i[wrench wrench skill2],
      %i[torch torch skill3],
      %i[hammer hammer skill4],
      %i[watering_can watering_can skill5]
    ].freeze

    DISC = UI::ShapeStyle.new(shape: :disc)
    CLICK = 'blip.ogg'

    attr_reader :menu, :used

    def initialize(**)
      super
      @used = nil
      @menu = add_node(UI::Menu.new(layout: UI::Row.new(item_width: SLOT_WIDTH, item_height: SLOT_HEIGHT),
                                    scope: 'skills'))
      SKILLS.each { |key, image, hotkey| add_skill(key, image, hotkey) }
    end

    # The name of the focused tool, as its button draws it.
    def focused_name = @menu.focused.label

    private

    def add_skill(key, image, hotkey)
      button = UI::IconButton.new(image: image, label: key, hotkey: hotkey, activate_on: :press, style: DISC)
      @menu.add(button).on_activated do
        @used = button.label
        system!(Engine::AudioOut).play_sound(CLICK)
      end
    end
  end

  # The captions. Added after the bar, so its last line is the last text of every
  # frame — which is what the drive script reads. Each sentence is one key with the
  # tool's name as a variable, and the name is the button's own label, so a
  # translator writes each name once and drawing an unchanged caption allocates
  # nothing.
  class Caption < Engine::Node2D
    def initialize(bar:, **)
      super(**)
      @bar = bar
      @help = Engine::Text.new('help.bar')
      @focused = Engine::Text.new('status.focused', :skill)
      @used = Engine::Text.new('status.used', :skill)
      @nothing_used = Engine::Text.new('status.nothing_used')
    end

    def _draw(renderer, _view)
      renderer.text(@help, 12, 12)
      renderer.text(@focused.with(skill: @bar.focused_name.to_s), 12, HEIGHT - 52)
      used = @bar.used
      renderer.text(used ? @used.with(skill: used.to_s) : @nothing_used, 12, HEIGHT - 30)
    end
  end

  class Scene < Engine::Node2D
    def _enter_tree
      bar = add_node(SkillBar.new(y: 300))
      bar.x = (WIDTH - bar.menu.bounds_width) / 2
      add_node(Caption.new(bar: bar))
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Scene.new,
      caption: 'Skill bar',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      locales: LOCALES,
      input_map: Engine::InputMap.default.merge(
        skill1: { buttons: [Controls::KEY_1] },
        skill2: { buttons: [Controls::KEY_2] },
        skill3: { buttons: [Controls::KEY_3] },
        skill4: { buttons: [Controls::KEY_4] },
        skill5: { buttons: [Controls::KEY_5] }
      )
    )

    # An image id that is a Symbol is a name rather than a path, so the tools are
    # registered once: the atlas cuts each from the strip and registers it by name.
    game.renderer.register_ui_atlas(game.assets.ui_atlas('skills.json'))

    game.start
  end
end

SkillBarExample.start
