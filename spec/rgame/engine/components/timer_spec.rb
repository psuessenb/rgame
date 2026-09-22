# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Timer do
  subject(:timer) { described_class.new(1.0) }

  let(:node) { RGame::Engine::Node2D.new }

  before { node.add_component(timer) }

  def fired
    count = 0
    timer.on_elapsed { count += 1 }
    yield
    count
  end

  it 'does not emit before a whole interval elapses' do
    fires = fired { timer._update(0.6) }
    expect(fires).to eq(0)
  end

  it 'emits on_elapsed once a whole interval has accumulated' do
    fires = fired do
      timer._update(0.6)
      timer._update(0.6)
    end
    expect(fires).to eq(1)
  end

  it 'carries the remainder forward so the cadence does not drift' do
    fires = fired do
      timer._update(1.2) # fires once, 0.2 overshoot survives
      timer._update(0.8) # 0.2 + 0.8 = 1.0, fires again exactly on time
    end
    expect(fires).to eq(2)
  end

  it 'emits once per whole interval crossed in a single long step (catch-up)' do
    fires = fired { timer._update(3.0) } # three whole intervals at once
    expect(fires).to eq(3)
  end

  it 'reflects a retuned interval' do
    fires = fired do
      timer.interval = 0.5
      timer._update(0.6)
    end
    expect(fires).to eq(1)
  end

  describe '#reset' do
    it 'drops accumulated time' do
      fires = fired do
        timer._update(0.9)
        timer.reset
        timer._update(0.5)
      end
      expect(fires).to eq(0)
    end
  end

  describe '_attach reset (recycling)' do
    it 'restarts the countdown when the node re-enters the tree' do
      count = 0
      timer.on_elapsed { count += 1 }
      node.enter_tree
      node.update(0.6) # 0.6 toward 1.0

      node.exit_tree
      node.enter_tree # _attach drops the accumulated 0.6

      node.update(0.6) # only 0.6 of a fresh interval → no fire
      expect(count).to eq(0)
    end
  end

  describe 'on a node' do
    it 'advances on the node update tick, so the owner need not drive it' do
      count = 0
      timer.on_elapsed { count += 1 }
      node.enter_tree
      6.times { node.update(0.2) } # 1.2s total → one whole interval
      expect(count).to eq(1)
    end

    it 'can sit alongside a second timer under a different name' do
      host = RGame::Engine::Node2D.new
      spawn = described_class.new(1.0)
      wave = described_class.new(2.0)
      host.add_component(spawn, as: :spawn)
      host.add_component(wave, as: :wave)
      expect([host.get_component(:spawn), host.get_component(:wave)]).to eq([spawn, wave])
    end
  end
end
