# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Tween do
  subject(:tween) { described_class.new(1.0, from: 0.0, to: 10.0) }

  let(:node) { RGame::Engine::Node2D.new }

  before do
    node.add_component(tween)
    node.enter_tree
  end

  def finishes
    count = 0
    tween.on_finished { count += 1 }
    yield
    count
  end

  it 'runs from the moment the node enters the tree' do
    node.update(0.5)
    expect([tween.running?, tween.value, tween.progress]).to eq([true, 5.0, 0.5])
  end

  it 'emits on_finished once, when it reaches the end' do
    count = finishes do
      node.update(0.6)
      node.update(0.6)
      node.update(5.0)
    end
    expect([count, tween.done?, tween.running?]).to eq([1, true, false])
  end

  it 'emits once even when one long step crosses the duration several times' do
    expect(finishes { node.update(3.0) }).to eq(1)
  end

  it 'holds while its node is paused' do
    node.update(0.25)
    node.paused = true
    expect { node.update(1.0) }.not_to(change(tween, :value))
  end

  describe '#start' do
    it 'runs it again from the start' do
      count = finishes do
        node.update(1.0)
        tween.start
        node.update(1.0)
      end
      expect(count).to eq(2)
    end

    it 'may be called from its own on_finished handler' do
      count = 0
      tween.on_finished do
        count += 1
        tween.start
      end
      5.times { node.update(1.0) }
      expect(count).to eq(5)
    end
  end

  describe '#stop' do
    it 'holds it at the start, emitting nothing, until start' do
      count = finishes do
        node.update(0.5)
        tween.stop
        node.update(5.0)
      end
      expect([count, tween.value, tween.stopped?]).to eq([0, 0.0, true])
    end

    it 'is neither running nor done' do
      tween.stop
      expect([tween.running?, tween.done?]).to eq([false, false])
    end
  end

  describe '#finish' do
    it 'jumps to the end and emits on_finished' do
      count = finishes { tween.finish }
      expect([count, tween.value]).to eq([1, 10.0])
    end

    it 'does nothing once it has finished' do
      count = finishes do
        node.update(1.0)
        tween.finish
      end
      expect(count).to eq(1)
    end

    it 'does nothing while stopped' do
      tween.stop
      expect(finishes { tween.finish }).to eq(0)
    end
  end

  describe '#duration=' do
    it 'changes when it finishes' do
      tween.duration = 2.0
      count = finishes { node.update(1.5) }
      expect([count, tween.duration]).to eq([0, 2.0])
    end
  end

  describe 'recycling' do
    it 'starts again when its node enters the tree again' do
      node.update(0.6)
      node.exit_tree
      node.enter_tree
      expect(tween.progress).to eq(0.0)
    end

    it 'runs a finished one again when its node enters the tree again' do
      count = finishes do
        node.update(1.0)
        node.exit_tree
        node.enter_tree
        node.update(1.0)
      end
      expect(count).to eq(2)
    end
  end

  it 'refuses loop:, since a tween that loops never finishes' do
    expect { described_class.new(1.0, loop: true) }.to raise_error(ArgumentError, /loop/)
  end

  it 'does not allocate per frame, running or finished' do
    tween.on_finished { tween.start }
    dt = 1.0 / 60.0
    expect { tween._update(dt) }.to allocate_nothing.after_warmup(120)
  end
end
