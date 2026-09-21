# frozen_string_literal: true

# Intro — a story told a page at a time, on a black screen.
#
# Run it:
#
#   ruby examples/intro/main.rb
#
# **Enter** turns the page, and the pages also turn on their own every six
# seconds. It exercises:
#   - UI::Label — a translated text drawn as lines that fit a width, a page at
#     a time;
#   - Engine::Paragraph — underneath the label, breaking the text and grouping
#     the lines into pages;
#   - Components::Timer — a one-shot that turns the page, re-armed with `reset`
#     after every turn but the last.
#
# ## The text is one line
#
# `intro.story` in locales/en.yml is a single long line, with no line break an
# author placed. The label breaks it where the words stop fitting 440 pixels
# at 24 pixels a line, and groups the lines three to a page. Run it in German
# (`LANG=de_DE.UTF-8`, or the commented-out line at the end of this file) and
# the same story takes ten lines and a fourth page, because German words are
# longer. Neither table says where a line ends, and neither has to.
#
# ## The label turns no pages itself
#
# A label reads no input. This root decides when a page turns: when the timer
# fires, or when the player presses Enter. Either way the root re-arms the
# timer, so a page turned by hand gets its full six seconds. The timer is a
# one-shot (`repeating: false`), so on the last page the root simply does not
# re-arm it, and stops drawing the hint. Nothing has to remove it.
#
# ## What it does not solve
#
# There is no typewriter reveal, no fade between pages, and nothing after the
# last page. Those belong to a dialogue system, which this is not. The block of
# text is placed for this window's fixed size, so a fullscreen switch would
# leave it where it was.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml and de.yml

PAGE_SECONDS = 6.0
TEXT_WIDTH = 440
LINES_PER_PAGE = 3

# The black screen, the story on it, and the hint beneath.
class Intro < RGame::Engine::Node2D
  BLACK = RGame::Util::Color.new(0, 0, 0)
  HINT_COLOR = RGame::Util::Color.new(120, 116, 128)
  FACE = RGame::Util::Typeface.default(24)

  def initialize
    super
    @story = add_node(RGame::Engine::UI::Label.new(
                        text: 'intro.story', x: (WIDTH - TEXT_WIDTH) / 2,
                        y: (HEIGHT - (LINES_PER_PAGE * FACE.height)) / 2, width: TEXT_WIDTH,
                        typeface: FACE, lines_per_page: LINES_PER_PAGE, align: :center
                      ))
    @hint = RGame::Engine::Text.new('hint.next')
    @turn = add_component(RGame::Engine::Components::Timer.new(PAGE_SECONDS, repeating: false))
    @turn.on_timeout { turn_page }
  end

  def on_control(actions)
    turn_page if actions.pressed?(:ui_confirm)
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BLACK)
    return if @story.last_page?

    renderer.text(@hint, (view.width - renderer.text_width(@hint)) / 2, view.height - 48, color: HINT_COLOR)
  end

  private

  def turn_page
    @story.page += 1
    @turn.reset unless @story.last_page?
  end
end

game = RGame::Game.new(
  root: Intro.new,
  caption: 'Intro',
  width: WIDTH,
  height: HEIGHT,
  locales: LOCALES
)

# The language follows the operating system. Un-comment the next line to see the
# intro in German whatever the system is set to; it must come after Game.new,
# which picks the language as it loads the tables.
# RGame::Engine::I18n.locale = :de

game.start
