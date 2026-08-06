# frozen_string_literal: true

RSpec.describe Engine::Timer do
  subject(:timer) { described_class.new(1.0) }

  it 'is not ready before a whole interval has elapsed' do
    timer.update(0.6)
    expect(timer).not_to be_ready
  end

  it 'becomes ready once a whole interval has accumulated' do
    timer.update(0.6)
    timer.update(0.6)
    expect(timer).to be_ready
  end

  describe '#consume' do
    it 'clears readiness after deducting one interval' do
      timer.update(1.2)
      timer.consume
      expect(timer).not_to be_ready
    end

    it 'carries the remainder forward so cadence does not drift' do
      timer.update(1.2) # 0.2 of overshoot should survive the consume
      timer.consume
      timer.update(0.8) # 0.2 + 0.8 = 1.0, ready again exactly on time
      expect(timer).to be_ready
    end
  end

  it 'stays ready until consumed (a tower with no target keeps its shot)' do
    timer.update(1.0)
    expect(timer).to be_ready
    timer.update(0.0)
    expect(timer).to be_ready # still loaded; nothing consumed it
  end

  describe '#reset' do
    it 'drops accumulated time' do
      timer.update(0.9)
      timer.reset
      timer.update(0.5)
      expect(timer).not_to be_ready
    end
  end

  it 'reflects a retuned interval' do
    timer.interval = 0.5
    timer.update(0.6)
    expect(timer).to be_ready
  end
end
