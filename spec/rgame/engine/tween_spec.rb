# frozen_string_literal: true

RSpec.describe RGame::Engine::Tween do
  subject(:tween) { described_class.new(2.0, from: 10.0, to: 30.0) }

  describe '.new' do
    it 'goes from 0 to 1 by default' do
      tween = described_class.new(1.0).update(0.25)
      expect(tween.value).to eq(0.25)
    end

    it 'refuses a duration that is not positive' do
      expect { described_class.new(0) }.to raise_error(ArgumentError, /duration/)
    end

    it 'refuses a duration that is not a number' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /duration/)
    end

    it 'refuses an ease it does not know' do
      expect { described_class.new(1.0, ease: :bounce) }.to raise_error(ArgumentError, /bounce/)
    end
  end

  it 'starts at from, with no progress' do
    expect([tween.value, tween.progress, tween.done?]).to eq([10.0, 0.0, false])
  end

  it 'moves the value in proportion to the time passed' do
    tween.update(0.5)
    expect([tween.progress, tween.value]).to eq([0.25, 15.0])
  end

  it 'stops at to and is done once the duration has passed' do
    tween.update(1.5).update(1.5)
    expect([tween.value, tween.progress, tween.done?]).to eq([30.0, 1.0, true])
  end

  it 'goes down as well as up' do
    tween = described_class.new(1.0, from: 1.0, to: 0.0).update(0.25)
    expect(tween.value).to eq(0.75)
  end

  it 'follows a to changed mid-way' do
    tween.update(1.0)
    tween.to = 50.0
    expect(tween.value).to eq(30.0)
  end

  describe '#finish' do
    it 'jumps to the end' do
      tween.finish
      expect([tween.value, tween.done?]).to eq([30.0, true])
    end
  end

  describe '#restart' do
    it 'goes back to the start, to run again' do
      tween.update(5.0).restart.update(0.5)
      expect([tween.value, tween.done?]).to eq([15.0, false])
    end
  end

  describe '#duration=' do
    it 'keeps the time passed, so a longer duration runs a finished tween again' do
      tween.update(2.0)
      tween.duration = 4.0
      expect([tween.progress, tween.done?]).to eq([0.5, false])
    end

    it 'refuses a duration that is not positive' do
      expect { tween.duration = -1 }.to raise_error(ArgumentError, /duration/)
    end
  end

  describe 'ease:' do
    def at(ease, progress) = described_class.new(1.0, ease:).update(progress).value

    it 'is linear by default' do
      expect(described_class.new(1.0).ease).to eq(:linear)
    end

    it 'starts slow with :in and fast with :out' do
      expect([at(:in, 0.5), at(:out, 0.5)]).to eq([0.25, 0.75])
    end

    it 'is symmetric about the middle with :in_out' do
      expect([at(:in_out, 0.25) + at(:in_out, 0.75), at(:in_out, 0.5)]).to eq([1.0, 0.5])
    end

    it 'reaches to halfway and comes back with :arc' do
      expect([at(:arc, 0.5), at(:arc, 1.0)]).to eq([1.0, 0.0])
    end

    it 'begins at from and ends at to for every ease but :arc' do
      ends = (described_class::EASES.keys - [:arc]).map { [at(it, 0.0), at(it, 1.0)] }
      expect(ends.uniq).to eq([[0.0, 1.0]])
    end

    it 'takes anything answering call' do
      expect(at(->(t) { t / 2 }, 0.5)).to eq(0.25)
    end
  end

  describe 'loop: true' do
    subject(:tween) { described_class.new(1.0, loop: true) }

    it 'starts again at the end, carrying the overshoot' do
      tween.update(0.75).update(0.5)
      expect(tween.progress).to be_within(1e-9).of(0.25)
    end

    it 'is never done' do
      tween.update(3.0)
      expect([tween.done?, tween.loop?]).to eq([false, true])
    end
  end

  it 'does not allocate per frame' do
    dt = 1.0 / 60.0
    eased = described_class.new(0.5, from: 0, to: 255, ease: :in_out)
    expect do
      eased.update(dt)
      eased.value
      eased.restart if eased.done?
    end.to allocate_nothing.after_warmup(120)
  end
end
