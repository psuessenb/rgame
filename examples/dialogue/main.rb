# frozen_string_literal: true

# Dialogue — one branching conversation, shown in a dialogue box.
#
# Run it:
#
#   ruby examples/dialogue/main.rb
#
# **Enter** begins the dialogue. In the box, Enter shows the rest of a line
# still typing, then moves on. **Up** and **Down** choose a response, and
# Enter picks it. Once the dialogue ends, Enter begins it again. It exercises:
#   - Dialogue::Script — the conversation written as beats and responses;
#   - Engine::Dialogue — one conversation running that script;
#   - UI::DialogueBox — the speaker's name, the line typed out a page at a
#     time, and the responses to pick from.
#
# ## A script, a dialogue and a box
#
# `INN` below is the whole conversation. Each `beat` is the innkeeper saying a
# line. A beat with a `to:` moves on when the player presses Enter. A beat with
# responses waits until the player picks one, and each `respond` names the beat
# it leads to. A beat with neither ends the conversation. Every line and label
# is a key into locales/en.yml, under the script's `scope:`, and the speaker's
# name is `speakers.keeper`.
#
# The script is a recipe, built once. `Engine::Dialogue.new(INN)` is one
# conversation following it, and knows where that conversation has got to.
# `UI::DialogueBox` draws that conversation and moves it along when the player
# presses Enter. When it ends, the box removes itself and the dialogue says so
# through `on_ended`.
#
# ## Going back is a beat like any other
#
# The hub asks "What can I do for you?", and every question leads back to it.
# There is no undo: `to: :hub` is simply the next beat. The news branch asks one
# question of its own first, so the way back from it is one step or two.
#
# ## `unavailable:` is required
#
# A response may carry a condition, and a box has to know whether one the
# player cannot pick is left out (`:hide`) or shown greyed out (`:disable`). No
# response here has a condition, so the choice changes nothing. The box still
# asks, because it is the game's decision and no default could make it.
#
# ## What it does not show
#
# There is no world, no character to walk up to, no conditions and no saving.
# `examples/quests_and_dialogue` has all of those: a village where a
# conversation moves a quest on, a response that appears once the hero can pay
# for it, the box's log of what was said, and a save that remembers it all.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine`, `Util`, `UI` and `Components` inside it
# stand for rgame's namespaces of the same names, and every name the example
# defines stays off the top level. docs/api/README.md says why, under "A game's
# own module".
module DialogueExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  WIDTH  = 640
  HEIGHT = 480
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

  MARGIN = 20 # between the box and the window's edges

  # The conversation, from the first line to the last.
  INN = Engine::Dialogue::Script.build(start: :greeting, scope: 'inn') do
    beat :greeting, speaker: :keeper, line: 'greeting', to: :hub

    beat :hub, speaker: :keeper, line: 'hub' do
      respond 'ask_room', to: :room
      respond 'ask_road', to: :road
      respond 'ask_news', to: :news
      respond 'leave', to: :farewell
    end

    beat :room, speaker: :keeper, line: 'room', to: :hub
    beat :road, speaker: :keeper, line: 'road', to: :hub

    beat :news, speaker: :keeper, line: 'news' do
      respond 'news_more', to: :wolves
      respond 'news_enough', to: :hub
    end
    beat :wolves, speaker: :keeper, line: 'wolves', to: :hub

    beat :farewell, speaker: :keeper, line: 'farewell'
  end

  # A black screen with a prompt, and a dialogue box while a conversation runs.
  class Inn < Engine::Node2D
    BLACK = Util::Color.new(0, 0, 0)
    PROMPT_COLOR = Util::Color.new(200, 196, 208)

    def initialize
      super
      @prompt = Engine::Text.new('prompt.begin')
      @talk = nil
    end

    def _control(actions)
      return if @talk || !actions.pressed?(:ui_confirm)

      begin_dialogue
    end

    def _draw(renderer, view)
      renderer.rect(0, 0, view.width, view.height, color: BLACK)
      return if @talk

      renderer.text(@prompt, (view.width - renderer.text_width(@prompt)) / 2, view.height / 2, color: PROMPT_COLOR)
    end

    private

    # The Enter that began it is still held when the box arrives. The box's menu
    # takes no Enter until it has seen Enter let go, so the first line types out
    # rather than being skipped. The Enter that ends it cannot begin the next
    # one either: this node reads its input before the box does, so it has
    # already looked at that tick when `on_ended` clears `@talk`.
    def begin_dialogue
      @talk = Engine::Dialogue.new(INN)
      @talk.on_ended { @talk = nil }
      box = add_node(UI::DialogueBox.new(dialogue: @talk, unavailable: :hide,
                                         width: WIDTH - (2 * MARGIN), x: MARGIN))
      box.y = HEIGHT - box.height - MARGIN
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Inn.new,
      caption: 'Dialogue',
      width: WIDTH,
      height: HEIGHT,
      locales: LOCALES
    )

    game.start
  end
end

DialogueExample.start
