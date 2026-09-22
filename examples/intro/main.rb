# frozen_string_literal: true

# Intro — a story told a page at a time, on a black screen.
#
# Run it:
#
#   ruby examples/intro/main.rb
#
# Each page types itself out. **Enter** shows the rest of the page at once,
# and on a page already shown turns it. A page also turns on its own once it
# has been fully shown for a second, plus a little for every character on it.
# It exercises:
#   - UI::Label — a translated text drawn as lines that fit a width, a page at
#     a time, and revealed at 40 characters a second with `reveal:`;
#   - Engine::Paragraph — underneath the label, breaking the text and grouping
#     the lines into pages;
#   - Components::Timer — a one-shot that turns the page, held back while the
#     page is still typing, its interval set for each page.
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
# ## The label reveals, and its owner decides
#
# A label reads no input. It types a page out in its own `update`, and says
# whether the page is fully shown with `revealed?`. This root decides what
# Enter means from that: `reveal_all` while the page is typing, a page turn
# once it is shown. A page turned starts typing again from nothing.
#
# The hold counts from the moment a page is fully shown, and grows with the
# page: one second, plus 20 milliseconds for each character `page_length`
# counts. A full page stays up about three and a half seconds after it is
# shown, and a short last line under two. The reader has read along while the
# page typed, so the hold is only the time to finish. While the page is still
# typing, the root resets the timer every tick, so the one-shot never gets near
# firing. On the last page it fires once and the turn does nothing, and the
# root stops drawing the hint.
#
# ## What it does not solve
#
# There is no fade between pages and nothing after the last page. The block of
# text is placed for this window's fixed size, so a fullscreen switch would
# leave it where it was.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml and de.yml

HOLD_SECONDS = 1.0 # how long a page stays up once shown, before its characters are counted
HOLD_PER_CHARACTER = 0.02
REVEAL = 40 # characters a second
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
                        typeface: FACE, lines_per_page: LINES_PER_PAGE, align: :center, reveal: REVEAL
                      ))
    @hint = RGame::Engine::Text.new('hint.next')
    @turn = add_component(RGame::Engine::Components::Timer.new(HOLD_SECONDS, repeating: false))
    @turn.on_elapsed { turn_page }
  end

  def on_add = hold_for_page

  def on_control(actions)
    return unless actions.pressed?(:ui_confirm)

    @story.revealed? ? turn_page : @story.reveal_all
  end

  def on_update(_dt)
    @turn.reset unless @story.revealed?
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BLACK)
    return if @story.last_page?

    renderer.text(@hint, (view.width - renderer.text_width(@hint)) / 2, view.height - 48, color: HINT_COLOR)
  end

  private

  def turn_page
    @story.page += 1
    hold_for_page
  end

  def hold_for_page
    @turn.interval = HOLD_SECONDS + (HOLD_PER_CHARACTER * @story.page_length)
    @turn.reset
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
