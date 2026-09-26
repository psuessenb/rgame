# frozen_string_literal: true

# Quests and dialogue — a village where talking moves a quest, and a save
# remembers both.
#
# Run it:
#
#   ruby examples/quests_and_dialogue/main.rb
#
# Arrows or WASD walk the hero, the blue square. **Enter** next to the smith,
# in front of the forge, talks to them. Walking into the signpost on the left
# reads it. In a conversation, Enter moves on, Up and Down choose a response,
# and **L** opens the log of what was said, Up and Down turning its pages. **F5**
# saves and **F9** loads. It exercises:
#   - StateGraph and StateMachine — the hammer quest, its stages and events;
#   - Components::Facts — flags that belong to no object, and the one save
#     entry holding every flag and every named machine;
#   - Dialogue::Script and Engine::Dialogue — the smith's conversation, with
#     conditions, effects, `once:` and a line with a variable;
#   - UI::DialogueBox — the box, with a portrait drawn in `_draw_portrait` and
#     the log;
#   - CollisionWorld#nearest and BoxCollider#on_hit — the two ways a
#     conversation starts.
#
# Read `examples/dialogue` first. It shows the script, the dialogue and the box
# with nothing else on screen. This example is what they do in a game.
#
# ## The quest
#
# The smith has lost a hammer. Ask for work, and the quest starts: the hammer
# appears by the well. Walk over it to pick it up, bring it back, and the smith
# pays 40 gold. The hero starts with 20, and a lantern costs 50, so "Buy a
# lantern" appears among the responses only once the quest is done. Nothing
# connects the two but the gold.
#
# `HAMMER` is a state machine of four stages. `SMITH` is a conversation, which
# is a state machine too, with a line on each state. They never name each
# other. The conversation asks its context, the `Village`, and the village
# fires the quest's events: `accept_work` when the smith hands out the work,
# `hand_over_hammer` when the player gives it back. The quest pays the hero in
# its own last transition.
#
# ## Conditions decide what the player may say
#
# Each response in `SMITH` may carry a condition. "I found your hammer" needs
# the hammer in hand, and "Buy a lantern" needs 50 gold. The box is built with
# `unavailable: :hide`, so a response whose condition fails is left out. With
# `:disable` it would be shown greyed out, and the player would see "I found
# your hammer" before they had heard of one.
#
# `once: true` hides a response once the beat it leads to has been visited.
# "Any work?" is asked once, and a lantern bought once. The conversation is
# built with `name: :smith`, so it keeps its visits in the facts: "once" means
# once in the game, not once each conversation, and it survives a save.
#
# ## The hammer follows a fact
#
# The quest writes `hammer_on_ground` as it moves: true when the work is
# accepted, false when the hammer is picked up. The hammer draws itself while
# the fact is true, and learns it from `Facts#watch`. A watch calls its block at
# once and again on every change, a restored save included, so after F9 the
# hammer is where the loaded quest says without anyone telling it.
#
# ## One save entry for the whole world
#
# F5 writes `world: facts.to_h`, the hero's gold and the hero's position. The
# first entry holds every flag and every machine built with a `name:`: the
# quest, the smith's conversation and its visits. F9 hands it to
# `Facts#restore`. The gold is the hero's own, so the game saves it, as it
# would save anything else a node owns.
#
# ## Two ways to start a conversation
#
# Enter asks the collision world for the nearest `:npc` collider within 56
# pixels of the hero, which is how talking to the smith works. The signpost
# needs no button: its collider's `on_hit` fires the step the hero walks into
# it. `on_hit` is an edge, so standing on the post does not start the sign's
# conversation again; walking off and back on does.
#
# While a conversation runs the hero is paused. The arrows then move the box's
# focus without walking the hero, and neither Enter nor the signpost can start
# a second conversation over the first.
#
# ## What it does not solve
#
# A save made during a conversation would have to save the box, so F5 and F9
# do nothing while one runs. The log shows the conversation on screen, not the
# ones before it; a game that wants a journal of every conversation collects
# the transcripts `Dialogue#on_ended` hands over. The village is drawn in
# rectangles and fits the window, so there is no camera.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine` and `Util` inside it are short for
# `RGame::Engine` and `RGame::Util`, and every name the example defines stays off
# the top level. docs/api/README.md says why, under "A game's own module".
module QuestsAndDialogueExample
  Engine = RGame::Engine
  Util = RGame::Util

  Controls = Util::Controls
  Components = Engine::Components

  WIDTH  = 640
  HEIGHT = 480
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

  CELL_SIZE = 64
  WALK_SPEED = 150.0
  TALK_RANGE = 56 # pixels from the hero's centre to the smith's
  START_GOLD = 20
  REWARD = 40
  LANTERN_PRICE = 50
  MARGIN = 20 # between the dialogue box and the window's edges

  # A square with a collider round its centre, the shape of everything here.
  class Thing < Engine::Node2D
    def initialize(size:, layer:, color:, **)
      super(width: size, height: size, **)
      @color = color
      @collider = add_component(Components::BoxCollider.new(width: size, height: size, offset_x: -size / 2,
                                                            offset_y: -size / 2, layer:))
    end

    attr_reader :collider

    def _draw(renderer, _view) = renderer.rect(-width / 2, -height / 2, width, height, color: @color)
  end

  # The one the player walks. Its gold is what the smith's conditions read.
  class Hero < Thing
    BODY = Util::Color.new(90, 140, 230)
    LANTERN = Util::Color.new(255, 214, 92)

    attr_accessor :gold

    def initialize(**)
      super(size: 24, layer: :hero, color: BODY, **)
      @gold = START_GOLD
      add_component(Components::CharacterBody.new(speed: WALK_SPEED, blocked_by: %i[npc wall]))
      add_component(Components::PlayerController.new)
    end

    def _enter_tree = @facts = system(Components::Facts)

    def _update(_dt)
      self.x = x.clamp(12, WIDTH - 12)
      self.y = y.clamp(12, HEIGHT - 12)
    end

    def _draw(renderer, view)
      super
      renderer.circle(16, -12, 5, color: LANTERN) if @facts[:lantern]
    end
  end

  # Lies by the well while the quest says it does.
  class Hammer < Thing
    IRON = Util::Color.new(70, 70, 80)

    def initialize(**)
      super(size: 16, layer: :item, color: IRON, **)
      @on_ground = false
    end

    def _enter_tree
      @facts = system(Components::Facts)
      @watch = @facts.watch(:hammer_on_ground) { |on_ground| @on_ground = on_ground == true }
    end

    def _exit_tree = @facts.unwatch(@watch)

    def _draw(renderer, view)
      super if @on_ground
    end
  end

  # The dialogue box, with a square of the speaker's colour as a portrait.
  class PortraitBox < Engine::UI::DialogueBox
    PADDING = 12
    SIZE = 48
    PORTRAITS = { smith: Util::Color.new(200, 90, 50),
                  sign: Util::Color.new(150, 110, 60) }.freeze

    def initialize(**) = super(padding: PADDING, portrait_width: SIZE, **)

    def _draw_portrait(renderer, speaker)
      renderer.rect(PADDING, PADDING, SIZE, SIZE, color: PORTRAITS.fetch(speaker))
    end
  end

  # The village: the ground, the people and things on it, the quest, and the
  # conversations. It is also the context both conversations ask.
  class Village < Engine::Node2D
    GRASS = Util::Color.new(96, 140, 84)
    FORGE = Util::Color.new(110, 100, 96)
    STONE = Util::Color.new(150, 150, 160)
    SMITH_COLOR = Util::Color.new(200, 90, 50)
    POST = Util::Color.new(150, 110, 60)
    INK = Util::Color.new(20, 30, 20)

    HAMMER = Engine::StateGraph.build(start: :not_started) do
      state(:not_started) { on :accepted, to: :searching, then: ->(m) { m.facts[:hammer_on_ground] = true } }
      state(:searching) { on :picked_up, to: :carried, then: ->(m) { m.facts[:hammer_on_ground] = false } }
      state(:carried) { on :returned, to: :done, then: ->(m) { m.context.gold += REWARD } }
      state :done
    end

    SMITH = Engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
      beat :greeting, speaker: :smith, line: 'greeting' do
        respond 'ask_work', to: :work, once: true
        respond 'hammer', to: :thanks, if: :hammer_in_hand?, then: :hand_over_hammer
        respond 'buy', to: :sold, if: :can_buy_lantern?, then: :buy_lantern, once: true
        respond 'bye'
      end

      beat :work, speaker: :smith, line: 'work', to: :greeting, enter: :accept_work
      beat :thanks, speaker: :smith, line: Engine::Text.new('smith.thanks', :reward), vars: :reward_vars,
                    to: :greeting
      beat :sold, speaker: :smith, line: 'sold', to: :greeting
    end

    SIGN = Engine::Dialogue::Script.build(start: :read, scope: 'sign') do
      beat :read, speaker: :sign, line: 'read'
    end

    STAGE = { not_started: Engine::Text.new('quest.not_started'),
              searching: Engine::Text.new('quest.searching'),
              carried: Engine::Text.new('quest.carried'),
              done: Engine::Text.new('quest.done') }.freeze

    STATUS = { ready: Engine::Text.new('status.ready'),
               saved: Engine::Text.new('status.saved'),
               loaded: Engine::Text.new('status.loaded'),
               empty: Engine::Text.new('status.empty') }.freeze

    def initialize(save:)
      super()
      @save = save
      @collision = add_component(Components::CollisionWorld.new(cell_size: CELL_SIZE))
      @gold = Engine::Text.new('hud.gold', :gold)
      @help_walk = Engine::Text.new('help.walk')
      @help_talk = Engine::Text.new('help.talk')
      @help_save = Engine::Text.new('help.save')
      @status = :ready
      @talk = nil
    end

    def _enter_tree
      @facts = system(Components::Facts)
      build_village
      @hero = add_node(Hero.new(x: 320, y: 400))
      @quest = Engine::StateMachine.new(HAMMER, context: @hero, facts: @facts, name: :hammer)
    end

    def _control(actions)
      return if @talk

      talk_to_smith if actions.pressed?(:ui_confirm) && @collision.nearest(@hero.x, @hero.y, TALK_RANGE, layer: :npc)
      save_game if actions.pressed?(:save)
      load_game if actions.pressed?(:load)
    end

    def _draw(renderer, view)
      renderer.rect(0, 0, view.width, view.height, color: GRASS)
      renderer.text(@gold.with(gold: @hero.gold), 12, 12, color: INK)
      renderer.text(STAGE.fetch(@quest.state), 12, 34, color: INK)
      renderer.text(STATUS.fetch(@status), 452, 12, color: INK)
      renderer.text(@help_walk, 12, view.height - 66, color: INK)
      renderer.text(@help_talk, 12, view.height - 44, color: INK)
      renderer.text(@help_save, 12, view.height - 22, color: INK)
    end

    # What the smith's conversation asks and does. The script names each of
    # these as a Symbol, and the dialogue sends it here.

    def hammer_in_hand? = @quest.state == :carried
    def hand_over_hammer = @quest.fire(:returned)
    def accept_work = @quest.fire(:accepted)
    def can_buy_lantern? = @hero.gold >= LANTERN_PRICE
    def reward_vars = { reward: REWARD }

    def buy_lantern
      @hero.gold -= LANTERN_PRICE
      @facts[:lantern] = true
    end

    private

    def build_village
      add_node(Thing.new(size: 80, layer: :wall, color: FORGE, x: 320, y: 80))
      add_node(Thing.new(size: 40, layer: :wall, color: STONE, x: 530, y: 250))
      add_node(Thing.new(size: 24, layer: :npc, color: SMITH_COLOR, x: 320, y: 150))
      post = add_node(Thing.new(size: 20, layer: :sign, color: POST, x: 110, y: 310))
      post.collider.on_hit { |other| read_sign if other.layer == :hero }
      hammer = add_node(Hammer.new(x: 530, y: 310))
      hammer.collider.on_hit { |other| @quest.fire(:picked_up) if other.layer == :hero }
    end

    def talk_to_smith
      converse(Engine::Dialogue.new(SMITH, context: self, facts: @facts, name: :smith))
    end

    def read_sign
      converse(Engine::Dialogue.new(SIGN)) unless @talk
    end

    def converse(dialogue)
      @talk = dialogue
      @hero.paused = true
      dialogue.on_ended do
        @talk = nil
        @hero.paused = false
      end
      box = add_node(PortraitBox.new(dialogue:, unavailable: :hide, width: WIDTH - (2 * MARGIN), x: MARGIN, log: :log))
      box.y = HEIGHT - box.height - MARGIN
    end

    def save_game
      @save.write(world: @facts.to_h, gold: @hero.gold, hero: [@hero.x, @hero.y])
      @status = :saved
    end

    def load_game
      saved = @save.read
      return @status = :empty if saved.empty?

      @facts.restore(saved[:world])
      @hero.gold = saved.fetch(:gold)
      @hero.x, @hero.y = saved.fetch(:hero)
      @status = :loaded
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    save = Util::SaveFile.new('village.json', game: 'rgame-examples', dir: ENV.fetch('RGAME_SAVE_DIR', nil))

    game = RGame::Game.new(
      root: Village.new(save:),
      caption: 'Quests and dialogue',
      width: WIDTH,
      height: HEIGHT,
      locales: LOCALES,
      # L and F5/F9 are free in the default map. The arrows are not: they walk the
      # hero and move a menu's focus both, which is why the hero pauses while a
      # conversation runs.
      input_map: Engine::InputMap.default.merge(
        log: { buttons: [Controls::KEY_L, Controls::PAD_Y] },
        save: { buttons: [Controls::KEY_F5] },
        load: { buttons: [Controls::KEY_F9] }
      )
    )

    game.start
  end
end

QuestsAndDialogueExample.start
