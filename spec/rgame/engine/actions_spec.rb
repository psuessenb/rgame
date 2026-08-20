# frozen_string_literal: true

RSpec.describe RGame::Engine::Actions do
  describe 'reading declared actions' do
    subject(:actions) do
      described_class.new(held: { fire: true, jump: false },
                          axes: { move_x: 0.5 },
                          prev_held: { fire: false, jump: true })
    end

    it 'reports a held action' do
      expect(actions.held?(:fire)).to be(true)
    end

    it 'reports an unheld action as false rather than raising' do
      expect(actions.held?(:jump)).to be(false)
    end

    it 'reports the up→down edge' do
      expect(actions.pressed?(:fire)).to be(true)
    end

    it 'reports the down→up edge' do
      expect(actions.released?(:jump)).to be(true)
    end

    it 'reports an axis value' do
      expect(actions.axis(:move_x)).to eq(0.5)
    end

    it 'lists what it can answer for' do
      expect(actions.declared).to contain_exactly(:fire, :jump, :move_x)
    end
  end

  # The failure this replaces is silent and remote: a misspelled action reads as
  # "never pressed", and what a player sees is a button that does nothing —
  # somewhere far from the typo. RGame::Core::Input used to raise KeyError for an
  # unbound action and no longer can, because binding moved to InputMap; this is
  # where that guarantee went.
  describe 'reading an action nobody declared' do
    subject(:actions) { described_class.new(held: { fire: false }, axes: { move_x: 0.0 }) }

    it 'raises from held?' do
      expect { actions.held?(:fyre) }.to raise_error(KeyError, /no such action :fyre/)
    end

    it 'raises from pressed?' do
      expect { actions.pressed?(:fyre) }.to raise_error(KeyError, /:fyre/)
    end

    it 'raises from released?' do
      expect { actions.released?(:fyre) }.to raise_error(KeyError, /:fyre/)
    end

    it 'raises from axis' do
      expect { actions.axis(:move_z) }.to raise_error(KeyError, /:move_z/)
    end

    it 'says what it does know, so the typo is visible in the message' do
      expect { actions.held?(:fyre) }.to raise_error(KeyError, /:fire/)
    end

    it 'points at where the action should have been declared' do
      expect { actions.held?(:fyre) }.to raise_error(KeyError, /InputMap/)
    end
  end

  # The hashes are the declaration, so a button action and an axis action are
  # separate answers: a snapshot given only axes cannot say whether one is held.
  describe 'the hashes are the declaration' do
    it 'does not answer held? for an action it was given only as an axis' do
      actions = described_class.new(axes: { move_x: 1.0 })
      expect { actions.held?(:move_x) }.to raise_error(KeyError)
    end

    # ActionMapper seeds all three hashes from its map, so through the normal
    # path every declared action answers every query.
    it 'answers both for a snapshot built the way ActionMapper builds one' do
      map = RGame::Engine::InputMap.new(fire: { buttons: [RGame::Util::Controls::KEY_SPACE] })
      actions = RGame::Engine::ActionMapper.new(map).poll(FakeInputBackend.new)
      expect([actions.held?(:fire), actions.axis(:fire)]).to eq([false, 0.0])
    end
  end

  # prev_held is one frame behind, so on the first poll after an action is added
  # it legitimately has no entry. "Was not held before" is the right answer
  # there; the current-frame lookup is what catches a typo.
  describe 'the previous frame' do
    it 'treats a missing previous entry as not-held rather than an error' do
      actions = described_class.new(held: { fire: true }, prev_held: {})
      expect(actions.pressed?(:fire)).to be(true)
    end
  end
end
