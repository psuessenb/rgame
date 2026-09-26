# frozen_string_literal: true

# The smith's conversation from the design, over the hammer quest from step 1:
# the first caller using a dialogue, a quest and the facts at once. A response
# waits on the quest, taking it moves the quest on, and the bribe waits on the
# hero's gold.
RSpec.describe RGame::Engine::Dialogue do
  let(:engine) { RGame::Engine }
  let(:hero) { hero_in_new_world }

  before do
    stub_const('Hero', Class.new(engine::Node2D) do
      const_set(:HAMMER, RGame::Engine::StateGraph.build(start: :not_started) do
        state(:not_started) { on :accepted, to: :searching }
        state(:searching) { on :hammer_found, to: :found }
        state(:found) { on :returned, to: :done, then: ->(m) { m.context.gold += 100 } }
        state :done
      end)

      const_set(:SMITH, RGame::Engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
        beat :greeting, speaker: :smith, line: 'greeting' do
          respond 'ask_work', to: :work, once: true
          respond 'hammer', to: :thanks, if: ->(m) { m.context.quests[:hammer].state == :found },
                            then: ->(m) { m.context.quests[:hammer].fire(:returned) }
          respond 'bribe', to: :bribed, if: :can_bribe?, then: :pay_bribe
          respond 'bye'
        end

        beat :work, speaker: :smith, line: 'work', to: :greeting,
                    enter: ->(m) { m.context.quests[:hammer].fire(:accepted) }
        beat :thanks, speaker: :smith, line: 'thanks', to: :greeting
        beat :bribed, speaker: :smith, line: 'bribed'
      end)

      attr_accessor :gold
      attr_reader :quests

      def initialize
        super
        @gold = 0
      end

      def _enter_tree
        @quests = { hammer: RGame::Engine::StateMachine.new(self.class::HAMMER, context: self, facts:, name: :hammer) }
      end

      def talk_to_smith = RGame::Engine::Dialogue.new(self.class::SMITH, context: self, facts:, name: :smith)

      def can_bribe? = gold >= 50
      def pay_bribe = self.gold -= 50

      private

      def facts = system(RGame::Engine::Components::FactsDatabase)
    end)
  end

  def hero_in_new_world
    root = engine::Node2D.new
    root.add_component(engine::Components::FactsDatabase.new)
    root.enter_tree
    root.add_node(Hero.new)
  end

  def response(talk, key) = talk.responses.find { it.data.label.key == key }

  def pick(talk, key) = talk.respond(response(talk, key))

  it 'moves the quest on from the conversation' do
    talk = hero.talk_to_smith
    pick(talk, 'ask_work')
    expect([talk.beat, hero.quests[:hammer].state]).to eq(%i[work searching])
  end

  it 'offers the hammer only once the quest has reached :found' do
    talk = hero.talk_to_smith
    expect(talk.available?(response(talk, 'hammer'))).to be(false)
    pick(talk, 'ask_work')
    talk.continue
    hero.quests[:hammer].fire(:hammer_found)
    expect(talk.available?(response(talk, 'hammer'))).to be(true)
  end

  it 'finishes the quest and pays when the hammer is handed over' do
    talk = hero.talk_to_smith
    pick(talk, 'ask_work')
    talk.continue
    hero.quests[:hammer].fire(:hammer_found)
    pick(talk, 'hammer')
    expect([talk.beat, hero.quests[:hammer].state, hero.gold]).to eq([:thanks, :done, 100])
  end

  it 'offers the bribe only with enough gold, and takes the gold' do
    talk = hero.talk_to_smith
    expect(talk.available?(response(talk, 'bribe'))).to be(false)
    hero.gold = 60
    expect(talk.available?(response(talk, 'bribe'))).to be(true)
    pick(talk, 'bribe')
    expect([talk.beat, hero.gold]).to eq([:bribed, 10])
  end

  it 'has a way out of every beat, with thanks and the bribe shut to a hero with no hammer and no gold' do
    poor = engine::Exploration.run { hero_in_new_world.talk_to_smith }
    expect([poor.problems, poor.unreached]).to eq([[], %i[thanks bribed]])
  end

  it 'keeps the work question answered in the next conversation' do
    talk = hero.talk_to_smith
    pick(talk, 'ask_work')
    talk.continue
    pick(talk, 'bye')
    again = hero.talk_to_smith
    expect([again.available?(response(again, 'ask_work')), hero.quests[:hammer].state]).to eq([false, :searching])
  end
end
