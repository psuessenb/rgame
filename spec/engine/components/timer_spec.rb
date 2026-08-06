# frozen_string_literal: true

RSpec.describe Engine::Components::Timer do
  subject(:timer) { described_class.new(1.0) }

  let(:node) { Engine::Node2D.new }

  before { node.add_component(timer) }

  def fired
    count = 0
    timer.on_timeout { count += 1 }
    yield
    count
  end

  it 'does not emit before a whole interval elapses' do
    fires = fired { timer.update(0.6) }
    expect(fires).to eq(0)
  end

  it 'emits on_timeout once a whole interval has accumulated' do
    fires = fired do
      timer.update(0.6)
      timer.update(0.6)
    end
    expect(fires).to eq(1)
  end

  it 'carries the remainder forward so the cadence does not drift' do
    fires = fired do
      timer.update(1.2) # fires once, 0.2 overshoot survives
      timer.update(0.8) # 0.2 + 0.8 = 1.0, fires again exactly on time
    end
    expect(fires).to eq(2)
  end

  it 'emits once per whole interval crossed in a single long step (catch-up)' do
    fires = fired { timer.update(3.0) } # three whole intervals at once
    expect(fires).to eq(3)
  end

  it 'reflects a retuned interval' do
    fires = fired do
      timer.interval = 0.5
      timer.update(0.6)
    end
    expect(fires).to eq(1)
  end

  describe '#reset' do
    it 'drops accumulated time' do
      fires = fired do
        timer.update(0.9)
        timer.reset
        timer.update(0.5)
      end
      expect(fires).to eq(0)
    end
  end

  describe 'repeating: false (one-shot)' do
    subject(:timer) { described_class.new(1.0, repeating: false) }

    it 'fires on_timeout exactly once when the interval elapses' do
      fires = fired do
        timer.update(0.6)
        timer.update(0.6) # crosses 1.0 → fires
      end
      expect(fires).to eq(1)
    end

    it 'does not fire again after it has fired' do
      fires = fired do
        timer.update(1.0) # fires
        timer.update(5.0) # stays inert
      end
      expect(fires).to eq(1)
    end

    it 'fires only once even when a single long step crosses several intervals' do
      fires = fired { timer.update(3.0) }
      expect(fires).to eq(1)
    end

    it 'is re-armed by reset' do
      fires = fired do
        timer.update(1.0) # fires
        timer.reset
        timer.update(1.0) # fires again
      end
      expect(fires).to eq(2)
    end
  end

  describe 'on_attach reset (recycling)' do
    it 'restarts the countdown when the node re-enters the tree' do
      count = 0
      timer.on_timeout { count += 1 }
      node.enter_tree
      node.update(0.6) # 0.6 toward 1.0

      node.exit_tree
      node.enter_tree # on_attach drops the accumulated 0.6

      node.update(0.6) # only 0.6 of a fresh interval → no fire
      expect(count).to eq(0)
    end

    it 're-arms a spent one-shot when the node re-enters the tree' do
      host = Engine::Node2D.new
      oneshot = described_class.new(1.0, repeating: false)
      host.add_component(oneshot)
      count = 0
      oneshot.on_timeout { count += 1 }

      host.enter_tree
      host.update(1.0) # fires once
      host.exit_tree
      host.enter_tree # on_attach re-arms it

      host.update(1.0) # fires again
      expect(count).to eq(2)
    end
  end

  describe 'on a node' do
    it 'advances on the node update tick, so the owner need not drive it' do
      count = 0
      timer.on_timeout { count += 1 }
      node.enter_tree
      6.times { node.update(0.2) } # 1.2s total → one whole interval
      expect(count).to eq(1)
    end

    it 'can sit alongside a second timer under a different name' do
      host = Engine::Node2D.new
      spawn = described_class.new(1.0)
      wave = described_class.new(2.0)
      host.add_component(spawn, as: :spawn)
      host.add_component(wave, as: :wave)
      expect([host.get_component(:spawn), host.get_component(:wave)]).to eq([spawn, wave])
    end
  end
end
