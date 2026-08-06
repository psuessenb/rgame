# frozen_string_literal: true

RSpec.describe Engine::Animator do
  let(:set) do
    Engine::AnimationSet.new(
      stand: { row: 0, frames: 1, fps: 1 },
      walk_right: { row: 1, frames: 4, fps: 8 }
    )
  end

  it 'starts on the initial animation at frame 0' do
    animator = described_class.new(set)
    expect(animator.current).to eq(:stand)
    expect(animator.frame).to eq([0, 0, false])
  end

  it 'advances the frame as elapsed time accrues' do
    animator = described_class.new(set, initial: :walk_right)
    animator.update(1.0 / 8)
    expect(animator.frame).to eq([1, 1, false])
  end

  it 'switches animation and restarts elapsed time' do
    animator = described_class.new(set, initial: :walk_right)
    animator.update(1.0 / 8)
    animator.play(:stand)
    expect(animator.current).to eq(:stand)
    expect(animator.elapsed).to eq(0.0)
  end

  it 'keeps cycling when replaying the current animation (no reset)' do
    animator = described_class.new(set, initial: :walk_right)
    animator.update(1.0 / 8)
    animator.play(:walk_right)
    expect(animator.elapsed).to be_within(1e-9).of(1.0 / 8)
  end
end
