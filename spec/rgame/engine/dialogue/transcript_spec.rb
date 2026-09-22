# frozen_string_literal: true

RSpec.describe RGame::Engine::Dialogue::Transcript do
  def script(start: :greeting, &) = RGame::Engine::Dialogue::Script.build(start:, scope: 'smith', &)

  def respond_to_label(talk, key) = talk.respond(talk.responses.find { it.data.label.key == key })

  def summary(transcript) = transcript.map { [it.beat, it.response ? :response : :line, it.text.key] }

  let(:engine) { RGame::Engine }
  let(:hero_class) { Struct.new(:gold) }

  let(:smith) do
    gold = engine::Text.new('gold', :gold, scope: 'smith')
    script do
      beat :greeting, speaker: :smith, line: 'greeting' do
        respond 'ask_work', to: :work
        respond 'ask_gold', to: :purse
        respond 'bye'
      end
      beat :work, speaker: :smith, line: 'work', to: :greeting
      beat :purse, speaker: :smith, line: gold, vars: ->(m) { { gold: m.context.gold } }, to: :greeting
    end
  end

  before do
    engine::I18n.load(<<~YAML)
      en:
        smith:
          gold: "You have %{gold}."
    YAML
  end

  describe 'recording' do
    it 'records each line on arrival and each response picked, in order' do
      talk = engine::Dialogue.new(smith, context: hero_class.new(5))
      respond_to_label(talk, 'ask_work')
      talk.continue
      respond_to_label(talk, 'bye')
      expect(summary(talk.transcript)).to eq([[:greeting, :line, 'greeting'], [:greeting, :response, 'ask_work'],
                                              [:work, :line, 'work'], [:greeting, :line, 'greeting'],
                                              [:greeting, :response, 'bye']])
    end

    it 'records a cycle back to the greeting twice' do
      talk = engine::Dialogue.new(smith, context: hero_class.new(5))
      respond_to_label(talk, 'ask_work')
      talk.continue
      expect(talk.transcript.count { it.beat == :greeting && it.response.nil? }).to eq(2)
    end

    it 'names the speaker of a line, and nothing of a response' do
      talk = engine::Dialogue.new(smith, context: hero_class.new(5))
      respond_to_label(talk, 'ask_work')
      line, response = talk.transcript.to_a
      expect([line.speaker, line.speaker_name.key, line.vars, line.response,
              response.speaker, response.speaker_name, response.vars]).to eq([:smith, 'speakers.smith', nil, nil,
                                                                              nil, nil, nil])
    end

    it 'holds the picked transition on a response entry' do
      talk = engine::Dialogue.new(smith, context: hero_class.new(5))
      picked = respond_to_label(talk, 'ask_work')
      expect(talk.transcript[1].response).to equal(picked)
    end

    it 'records nothing for a continue' do
      talk = engine::Dialogue.new(smith, context: hero_class.new(5))
      respond_to_label(talk, 'ask_work')
      expect { talk.continue }.to change { talk.transcript.size }.by(1)
      expect(talk.transcript.last.beat).to eq(:greeting)
    end

    it 'records nothing for a state with no line' do
      branchy = script(start: :gate) do
        state(:gate) { go to: :greeting }
        beat :greeting, speaker: :smith, line: 'greeting'
      end
      expect(summary(engine::Dialogue.new(branchy).transcript)).to eq([[:greeting, :line, 'greeting']])
    end

    it 'shares the script\'s Text for a line without variables' do
      talk = engine::Dialogue.new(smith, context: hero_class.new(5))
      expect(talk.transcript.first.text).to equal(smith.graph.state(:greeting).data.line)
    end
  end

  describe 'a line with variables' do
    it 'keeps the values it was shown with after a later visit with others' do
      hero = hero_class.new(5)
      talk = engine::Dialogue.new(smith, context: hero)
      respond_to_label(talk, 'ask_gold')
      talk.continue
      hero.gold = 80
      respond_to_label(talk, 'ask_gold')
      first, second = talk.transcript.select(&:vars)
      expect([first.vars, first.text.to_s, second.vars, second.text.to_s, talk.line.to_s])
        .to eq([{ gold: 5 }, 'You have 5.', { gold: 80 }, 'You have 80.', 'You have 80.'])
    end

    it 'holds its values frozen, in a Text of its own' do
      talk = engine::Dialogue.new(smith, context: hero_class.new(5))
      respond_to_label(talk, 'ask_gold')
      entry = talk.transcript.last
      expect([entry.vars.frozen?, entry.text.equal?(talk.line)]).to eq([true, false])
    end
  end

  describe 'once frozen' do
    it 'refuses to record into a frozen transcript' do
      transcript = described_class.new(smith).freeze
      expect do
        transcript.record_line(:greeting, smith.graph.state(:greeting).data, nil)
      end.to raise_error(FrozenError)
    end
  end

  describe 'reading' do
    it 'allocates nothing reading each, size and []' do
      talk = engine::Dialogue.new(smith, context: hero_class.new(5))
      respond_to_label(talk, 'ask_work')
      count = 0
      reader = ->(_entry) { count += 1 }
      expect do
        talk.transcript.each(&reader)
        talk.transcript.size
        talk.transcript[1]
        talk.transcript.empty?
      end.to allocate_nothing
    end
  end
end
