# frozen_string_literal: true

# Localization — the same screen in two languages.
#
# Run it:
#
#   ruby examples/localization/main.rb
#
# Left and right change the number of apples. Up and down move through the
# language menu, and Enter picks one. Quit and run it again: the language you
# picked is still the one on screen. It exercises:
#   - Engine::I18n — tables in locales/, a fallback to English, CLDR plurals;
#   - Engine::Text — a key built once, with a `count` and with a variable;
#   - UI::Menu's `scope:`, and `Text.literal` for text that is never translated;
#   - RGame::Game's `locales:`, and the language it picks from the OS;
#   - Util::SaveFile, holding the language a player picked.
#
# ## Nothing is looked up while drawing
#
# Every string on screen is an Engine::Text built in `initialize`. Reading one
# compares its variables and `I18n.generation` with what it last rendered, and
# returns the same String while nothing changed. Picking a language moves the
# generation, so every Text and every button renders again on its next read,
# and nothing here tells them to.
#
# ## The tables sit beside this file
#
# `Game.new(locales: File.join(__dir__, 'locales'))` loads `en.yml` and `de.yml`
# from here. Every example shares `examples/assets/` as its media root, so a
# table there would be loaded into every example.
#
# ## German lacks a key, on purpose
#
# `de.yml` has no `hud.hint`. In German the hint shows the English text, because
# German's fallback chain ends at the default locale, English. A player reads a
# sentence in a language the game ships rather than `hud.hint`. That is the right
# failure for a game, and the wrong one to ship on purpose: a project from
# `rgame new` has a locales spec that fails until German has the key.
#
# German also has no `zero:` for the apples. English says "No apples", German
# says "0 Äpfel": an explicit `zero:` belongs to the table that has it.
#
# ## Language names are literals
#
# "English" and "Deutsch" are `Text.literal`, not keys. A language is named in
# its own language whichever one is current, so its name must not translate.
# The third button is a key, and the menu's `scope: 'language'` makes `system`
# read `language.system`. A literal has no key, so the scope does not touch it.
#
# ## What this does not solve
#
# Buttons are not sized to their text, so these are a fixed width, chosen wide
# enough for the longer label in either language: "Use the system language". A
# third language with longer words would need a wider slot. A paragraph that
# breaks per language is examples/intro's subject.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

UI = RGame::Engine::UI
I18n = RGame::Engine::I18n
Text = RGame::Engine::Text

WIDTH  = 640
HEIGHT = 360
ASSETS = File.expand_path('../assets', __dir__)
LOCALES = File.expand_path('locales', __dir__)

# The language on screen, and the file that remembers a player's choice.
#
# `RGame::Game` picks a language from the OS before `start`. A choice saved
# here wins over that, and "use the system language" forgets the choice again.
class Language
  def initialize(save, preferred)
    @save = save
    @preferred = preferred
  end

  # Called between `Game.new`, which loaded the tables, and `start`. `choose`
  # takes the saved locale if a table covers it, and the OS's otherwise, so a
  # hand-edited file holding a language this game lacks changes nothing.
  def restore
    saved = @save.read[:language]
    I18n.locale = I18n.choose([saved, *@preferred]) if saved.is_a?(String) && !saved.empty?
  end

  def pick(locale)
    I18n.locale = locale
    @save.write(language: locale.name)
  end

  def follow_system
    @save.delete
    I18n.locale = I18n.choose(@preferred)
  end
end

# The whole screen: a heading, three lines of text and the language menu.
class Screen < RGame::Engine::Node2D
  MARGIN = 40
  MENU_Y = 196
  ITEM_WIDTH = 280
  ITEM_HEIGHT = 34

  def initialize(language:, **)
    super(**)
    @language = language
    @apples_held = 3
    @title = Text.new('title')
    @apples = Text.new('hud.apples', :count)
    @locale = Text.new('hud.locale', :locale)
    @hint = Text.new('hud.hint')
    @heading = Text.new('language.title')
  end

  def on_add
    menu = add_node(UI::Menu.new(x: MARGIN, y: MENU_Y, scope: 'language',
                                 layout: UI::Column.new(item_width: ITEM_WIDTH, item_height: ITEM_HEIGHT)))
    menu.add(UI::PanelButton.new(label: Text.literal('English'))).on_activated { @language.pick(:en) }
    menu.add(UI::PanelButton.new(label: Text.literal('Deutsch'))).on_activated { @language.pick(:de) }
    menu.add(UI::PanelButton.new(label: 'system')).on_activated { @language.follow_system }
  end

  def on_control(actions)
    @apples_held += 1 if actions.pressed?(:ui_right)
    @apples_held -= 1 if actions.pressed?(:ui_left) && @apples_held.positive?
  end

  def on_draw(renderer, _view)
    renderer.text(@title, MARGIN, 24)
    renderer.text(@apples.with(count: @apples_held), MARGIN, 72)
    renderer.text(@locale.with(locale: I18n.locale.name), MARGIN, 96)
    renderer.text(@hint, MARGIN, 120)
    renderer.text(@heading, MARGIN, MENU_Y - 30)
  end
end

# `dir:` is normally left out and the file lands in the platform's own data
# directory. It is overridable so a driven run writes somewhere disposable.
save = RGame::Util::SaveFile.new('language.json', game: 'rgame-examples',
                                                  dir: ENV.fetch('RGAME_SAVE_DIR', nil))
language = Language.new(save, RGame::Core.preferred_locales)

game = RGame::Game.new(
  root: Screen.new(language: language),
  caption: 'Localization',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  locales: LOCALES
)

language.restore

# The buttons draw nine-slices, which name elements of an atlas rather than
# files, so the atlas is registered before the first frame.
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui.json'))

game.start
