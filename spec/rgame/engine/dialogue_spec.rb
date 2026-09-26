# frozen_string_literal: true

require 'tmpdir'

RSpec.describe RGame::Engine::Dialogue do
  def script(start: :greeting, &) = RGame::Engine::Dialogue::Script.build(start:, scope: 'smith', &)

  def respond_to_label(talk, key) = talk.respond(talk.responses.find { it.data.label.key == key })

  let(:engine) { RGame::Engine }

  let(:smith) do
    script do
      beat :greeting, speaker: :smith, line: 'greeting' do
        respond 'ask_work', to: :work, once: true
        respond 'secret', to: :secret, if: ->(m) { m.facts && m.facts[:trusted] }
        respond 'bye'
      end
      beat :work, speaker: :smith, line: 'work', to: :greeting
      beat :secret, speaker: :smith, line: 'secret', to: :greeting
    end
  end

  describe 'a conversation' do
    it 'runs from greeting to goodbye' do
      talk = described_class.new(smith)
      expect([talk.beat, talk.speaker, talk.speaker_name.key,
              talk.line.key]).to eq([:greeting, :smith, 'speakers.smith', 'greeting'])
      respond_to_label(talk, 'ask_work')
      expect([talk.beat, talk.line.key, talk.waiting_for_response?]).to eq([:work, 'work', false])
      talk.continue
      respond_to_label(talk, 'bye')
      expect([talk.ended?, talk.beat, talk.speaker, talk.speaker_name, talk.line,
              talk.responses]).to eq([true, nil, nil, nil, nil, []])
    end

    it 'lists a response whose condition fails, with available? false' do
      talk = described_class.new(smith)
      secret = talk.responses[1]
      expect([talk.responses.size, talk.available?(secret)]).to eq([3, false])
    end

    it 'makes that response available when its condition holds' do
      facts = engine::Components::FactsDatabase.new
      facts[:trusted] = true
      talk = described_class.new(smith, facts:)
      expect(talk.available?(talk.responses[1])).to be(true)
    end

    it 'drops a once: question after its answer' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'ask_work')
      talk.continue
      expect(talk.responses.map { talk.available?(it) }).to eq([false, false, true])
    end

    it 'goes back to an earlier beat, counting the visit' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'ask_work')
      talk.continue
      expect([talk.beat, talk.visits(:greeting), talk.visits(:work)]).to eq([:greeting, 2, 1])
    end

    it 'emits on_beat_entered for each beat reached and on_ended at the end' do
      talk = described_class.new(smith)
      heard = []
      talk.on_beat_entered { heard << it }
      talk.on_ended { heard << :ended }
      respond_to_label(talk, 'ask_work')
      talk.continue
      respond_to_label(talk, 'bye')
      expect(heard).to eq(%i[work greeting ended])
    end

    it 'returns the same line and name Text each time the beat is the same' do
      talk = described_class.new(smith)
      expect([talk.line, talk.speaker_name]).to contain_exactly(equal(talk.line), equal(talk.speaker_name))
    end

    it 'allocates nothing reading responses, the beat or the line' do
      talk = described_class.new(smith)
      talk.line
      expect do
        talk.responses
        talk.beat
        talk.line
        talk.waiting_for_response?
      end.to allocate_nothing
    end
  end

  describe 'misuse' do
    it 'refuses respond on a beat that continues' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'ask_work')
      expect { talk.respond(smith.graph.transitions(:greeting).first) }.to raise_error(RuntimeError, /call continue/)
    end

    it 'refuses continue on a beat that waits' do
      expect { described_class.new(smith).continue }.to raise_error(RuntimeError, /waits for a response; call respond/)
    end

    it 'refuses a response from another beat' do
      two = script do
        beat(:greeting, speaker: :smith, line: 'greeting') { respond 'more', to: :more }
        beat(:more, speaker: :smith, line: 'more') { respond 'bye' }
      end
      talk = described_class.new(two)
      expect { talk.respond(two.graph.transitions(:more).first) }.to raise_error(ArgumentError, /not listed/)
    end

    it 'refuses an unavailable response' do
      talk = described_class.new(smith)
      expect { talk.respond(talk.responses[1]) }.to raise_error(ArgumentError, /not available/)
    end

    it 'refuses both once ended' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'bye')
      expect { talk.continue }.to raise_error(RuntimeError, /has ended/)
      expect { talk.respond(smith.graph.transitions(:greeting).last) }.to raise_error(RuntimeError, /has ended/)
    end
  end

  describe 'vars:' do
    let(:purse) do
      line = engine::Text.new('gold', :gold, scope: 'smith')
      script do
        beat :greeting, speaker: :smith, line:, vars: ->(m) { { gold: m.context.gold } } do
          respond 'again', to: :greeting
        end
      end
    end

    let(:hero_class) { Struct.new(:gold) }

    before { engine::I18n.load("en:\n  smith:\n    gold: \"You have %{gold}.\"\n") }

    it 'fills the line on entering the beat' do
      expect(described_class.new(purse, context: hero_class.new(5)).line.to_s).to eq('You have 5.')
    end

    it 'keeps the values shown until the beat is entered again' do
      hero = hero_class.new(5)
      talk = described_class.new(purse, context: hero)
      hero.gold = 9
      expect(talk.line.to_s).to eq('You have 5.')
      talk.respond(talk.responses.first)
      expect(talk.line.to_s).to eq('You have 9.')
    end

    it 'keeps one line per conversation, so two on one script show their own values' do
      rich = described_class.new(purse, context: hero_class.new(100))
      poor = described_class.new(purse, context: hero_class.new(1))
      expect([rich.line.to_s, poor.line.to_s]).to eq(['You have 100.', 'You have 1.'])
    end

    it 'sends a Symbol to the context' do
      line = engine::Text.new('gold', :gold, scope: 'smith')
      named = script { beat :greeting, speaker: :smith, line:, vars: :purse }
      hero = Class.new { def purse = { gold: 3 } }.new
      expect(described_class.new(named, context: hero).line.to_s).to eq('You have 3.')
    end

    it 'checks a vars: Symbol against the context at construction' do
      line = engine::Text.new('gold', :gold, scope: 'smith')
      named = script { beat :greeting, speaker: :smith, line:, vars: :purse }
      expect do
        described_class.new(named, context: Object.new)
      end.to raise_error(NoMethodError, /Object does not answer :purse/)
    end
  end

  describe 'a state with no line' do
    it 'is passed through within the same move' do
      branchy = script(start: :branch) do
        state :branch do
          go to: :rich, if: ->(m) { m.context == :rich }
          go to: :poor
        end
        beat :rich, speaker: :smith, line: 'rich'
        beat :poor, speaker: :smith, line: 'poor'
      end
      expect(described_class.new(branchy, context: :poor).beat).to eq(:poor)
    end

    it 'raises, naming it, when it offers no way on' do
      stuck = script(start: :branch) do
        state(:branch) { go to: :rich, if: ->(_) { false } }
        beat :rich, speaker: :smith, line: 'rich'
      end
      expect do
        described_class.new(stuck)
      end.to raise_error(RuntimeError, /:branch has no line and no available transition/)
    end

    it 'raises when states with no line loop without reaching a beat' do
      looping = script(start: :a) do
        state(:a) { go to: :b }
        state(:b) { go to: :a }
      end
      expect { described_class.new(looping) }.to raise_error(RuntimeError, /reached :a twice without a line/)
    end
  end

  it 'raises on arriving at a beat that waits with no response available' do
    dead = script do
      beat :greeting, speaker: :smith, line: 'greeting', to: :shut
      beat(:shut, speaker: :smith, line: 'shut') { respond 'bye', if: ->(_) { false } }
    end
    talk = described_class.new(dead)
    expect { talk.continue }.to raise_error(RuntimeError, /beat :shut waits for a response and none is available/)
  end

  describe '#finish' do
    let(:paid) { [] }
    let(:bribe) do
      paid = self.paid
      script do
        beat :greeting, speaker: :smith, line: 'greeting' do
          respond 'bribe', to: :work, then: ->(_) { paid << :bribe }
        end
        beat :work, speaker: :smith, line: 'work'
      end
    end

    it 'ends where it stands, running no response, and hands on_ended the transcript so far' do
      talk = described_class.new(bribe)
      heard = []
      talk.on_ended { heard << it }
      talk.finish.finish
      expect([talk.ended?, paid, heard.size, heard.first.frozen?,
              heard.first.map(&:beat)]).to eq([true, [], 1, true, [:greeting]])
    end

    it 'starts a saved conversation again at its first beat' do
      facts = engine::Components::FactsDatabase.new
      talk = described_class.new(smith, facts:, name: :smith)
      respond_to_label(talk, 'ask_work')
      talk.finish
      expect(described_class.new(smith, facts:, name: :smith).beat).to eq(:greeting)
    end
  end

  describe 'the transcript' do
    it 'hands on_ended the frozen transcript' do
      talk = described_class.new(smith)
      heard = nil
      talk.on_ended { heard = it }
      respond_to_label(talk, 'bye')
      expect([heard.equal?(talk.transcript), heard.frozen?,
              heard.map(&:beat)]).to eq([true, true, %i[greeting greeting]])
    end

    it 'starts a new transcript for a resumed conversation, holding the beat it resumes at' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'ask_work')
      resumed = described_class.new(smith, from: talk.to_h)
      expect(resumed.transcript.map { [it.beat, it.text.key] }).to eq([[:work, 'work']])
    end

    it 'continues a transcript handed in with transcript:, without recording the beat twice' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'ask_work')
      resumed = described_class.new(smith, from: talk.to_h, transcript: talk.transcript)
      resumed.continue
      expect(resumed.transcript.map(&:beat)).to eq(%i[greeting greeting work greeting])
    end

    it 'copies a frozen transcript handed in, and records into the copy' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'bye')
      again = described_class.new(smith, transcript: talk.transcript)
      expect([again.transcript.equal?(talk.transcript), again.transcript.size,
              talk.transcript.size]).to eq([false, 3, 2])
    end

    it 'refuses a transcript of another script' do
      other = script { beat :greeting, speaker: :smith, line: 'greeting' }
      expect do
        described_class.new(smith, transcript: engine::Dialogue::Transcript.new(other))
      end.to raise_error(ArgumentError, /another script/)
    end
  end

  describe 'saving' do
    def save_and_read(value)
      Dir.mktmpdir do |dir|
        save = RGame::Util::SaveFile.new('slot1.json', dir:)
        save.write(talk: value)
        save.read[:talk]
      end
    end

    it 'resumes mid-conversation from a save' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'ask_work')
      resumed = described_class.new(smith, from: save_and_read(talk.to_h))
      expect([resumed.beat, resumed.visits(:greeting), resumed.visits(:work)]).to eq([:work, 1, 1])
    end

    it 'starts a saved ended conversation again at its first beat, keeping its visits' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'ask_work')
      talk.continue
      respond_to_label(talk, 'bye')
      again = described_class.new(smith, from: save_and_read(talk.to_h))
      expect([again.beat, again.visits(:greeting),
              again.available?(again.responses.first)]).to eq([:greeting, 3, false])
    end

    it 'keeps a once: question hidden when a named dialogue is talked to twice' do
      facts = engine::Components::FactsDatabase.new
      first = described_class.new(smith, facts:, name: :smith)
      respond_to_label(first, 'ask_work')
      first.continue
      respond_to_label(first, 'bye')
      second = described_class.new(smith, facts:, name: :smith)
      expect([second.beat, second.available?(second.responses.first)]).to eq([:greeting, false])
    end

    it 'keeps it hidden across a save of the facts' do
      facts = engine::Components::FactsDatabase.new
      talk = described_class.new(smith, facts:, name: :smith)
      respond_to_label(talk, 'ask_work')
      talk.continue
      respond_to_label(talk, 'bye')
      loaded = engine::Components::FactsDatabase.new
      loaded.restore(save_and_read(facts.to_h))
      again = described_class.new(smith, facts: loaded, name: :smith)
      expect(again.available?(again.responses.first)).to be(false)
    end

    it 'lets once: last one conversation for an unnamed dialogue' do
      talk = described_class.new(smith)
      respond_to_label(talk, 'ask_work')
      talk.continue
      respond_to_label(talk, 'bye')
      fresh = described_class.new(smith)
      expect(fresh.available?(fresh.responses.first)).to be(true)
    end
  end
end
