# frozen_string_literal: true

require 'tmpdir'

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

  describe 'saving' do
    def save_and_read(value)
      Dir.mktmpdir do |dir|
        save = RGame::Util::SaveFile.new('slot1.json', dir:)
        save.write(log: value)
        save.read[:log]
      end
    end

    def talked(gold: 5)
      talk = engine::Dialogue.new(smith, context: hero_class.new(gold))
      respond_to_label(talk, 'ask_gold')
      talk.continue
      respond_to_label(talk, 'ask_work')
      talk.continue
      respond_to_label(talk, 'bye')
      talk
    end

    it 'saves each line\'s beat and variables, and each response\'s index among its beat\'s' do
      expect(talked.transcript.to_h).to eq(entries: [{ beat: :greeting }, { beat: :greeting, response: 1 },
                                                     { beat: :purse, vars: { gold: 5 } }, { beat: :greeting },
                                                     { beat: :greeting, response: 0 }, { beat: :work },
                                                     { beat: :greeting }, { beat: :greeting, response: 2 }])
    end

    it 'returns a frozen Hash' do
      saved = talked.transcript.to_h
      expect([saved.frozen?, saved[:entries].frozen?, saved[:entries].all?(&:frozen?)]).to eq([true, true, true])
    end

    it 'comes back through a SaveFile as the same conversation' do
      original = talked.transcript
      restored = described_class.from(save_and_read(original.to_h), smith)
      expect([summary(restored), restored.map(&:vars), restored.map(&:response)])
        .to eq([summary(original), original.map(&:vars), original.map(&:response)])
    end

    it 'fills a restored line with its saved values' do
      restored = described_class.from(save_and_read(talked(gold: 42).transcript.to_h), smith)
      expect(restored[2].text.to_s).to eq('You have 42.')
    end

    it 'reads a restored transcript in the language chosen since' do
      saved = save_and_read(talked.transcript.to_h)
      engine::I18n.load(<<~YAML)
        de:
          smith:
            gold: "Du hast %{gold}."
      YAML
      engine::I18n.locale = :de
      expect(described_class.from(saved, smith)[2].text.to_s).to eq('Du hast 5.')
    end

    it 'gives Dialogue.new a restored transcript to record on' do
      talk = engine::Dialogue.new(smith, context: hero_class.new(5))
      respond_to_label(talk, 'ask_work')
      saved = save_and_read(talk.transcript.to_h)
      resumed = engine::Dialogue.new(smith, context: hero_class.new(5), from: save_and_read(talk.to_h),
                                            transcript: described_class.from(saved, smith))
      resumed.continue
      expect(summary(resumed.transcript)).to eq(summary(talk.transcript) + [[:greeting, :line, 'greeting']])
    end

    describe 'what to_h refuses' do
      let(:shouting) do
        line = engine::Text.new('gold', :gold, scope: 'smith')
        script { beat :greeting, speaker: :smith, line:, vars: ->(m) { { gold: m.context.gold } } }
      end

      it 'refuses a Symbol value, naming the entry and the variable' do
        transcript = engine::Dialogue.new(shouting, context: hero_class.new(:lots)).transcript
        expect { transcript.to_h }
          .to raise_error(TypeError, /variable :gold of transcript entry 0 \(:greeting\) cannot hold the Symbol :lots/)
      end

      it 'refuses a value a save cannot hold' do
        transcript = engine::Dialogue.new(shouting, context: hero_class.new(1..3)).transcript
        expect { transcript.to_h }.to raise_error(TypeError, /variable :gold .* got a Range/)
      end

      it 'records such a value without complaint, since only saving checks' do
        expect(engine::Dialogue.new(shouting, context: hero_class.new(:lots)).transcript.size).to eq(1)
      end
    end

    describe 'what from refuses' do
      it 'refuses a beat the script lacks' do
        expect { described_class.from({ entries: [{ beat: 'forge' }] }, smith) }
          .to raise_error(ArgumentError, /entry 0 names "forge", which is not a beat/)
      end

      it 'refuses a state with no line' do
        branchy = script(start: :gate) do
          state(:gate) { go to: :greeting }
          beat :greeting, speaker: :smith, line: 'greeting'
        end
        expect { described_class.from({ entries: [{ beat: 'gate' }] }, branchy) }
          .to raise_error(ArgumentError, /not a beat/)
      end

      it 'refuses a response index past the beat\'s responses' do
        expect { described_class.from({ entries: [{ beat: 'greeting', response: 3 }] }, smith) }
          .to raise_error(ArgumentError, /picks response 3 at :greeting, which lists 3/)
      end

      it 'refuses a response at a beat that continues' do
        expect { described_class.from({ entries: [{ beat: 'work', response: 0 }] }, smith) }
          .to raise_error(ArgumentError, /picks response 0 at :work, which lists 0/)
      end

      it 'refuses variables that do not match the line\'s names' do
        expect { described_class.from({ entries: [{ beat: 'purse', vars: { coins: 5 } }] }, smith) }
          .to raise_error(ArgumentError, /gives :purse's line .* it needs gold:/)
      end

      it 'refuses a line with variables saved without them' do
        expect { described_class.from({ entries: [{ beat: 'purse' }] }, smith) }
          .to raise_error(ArgumentError, /it needs gold:/)
      end

      it 'refuses variables on a line without names' do
        expect { described_class.from({ entries: [{ beat: 'work', vars: { gold: 5 } }] }, smith) }
          .to raise_error(ArgumentError, /it needs no variables/)
      end
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
