# frozen_string_literal: true

RSpec.describe FakeRenderer do
  # Half of why this file exists: the fake is run against the same contract as
  # the real renderer, so it cannot quietly fall behind it. The other half is
  # the recording itself, which engine specs assert against.
  subject(:renderer) { described_class.new }

  # The contract's hook. The fake needs no frame to draw into, so this just
  # yields; the real renderer's version opens a window and runs one. The fake
  # accepts anything as an image, because it never looks at one.
  def render = yield(renderer, :hero)

  it_behaves_like 'a renderer'

  describe 'recording' do
    it 'keeps each call with its positional arguments' do
      renderer.rect(10, 20, 30, 40)

      expect(renderer.calls_to(:rect).map(&:args)).to eq([[10, 20, 30, 40]])
    end

    it 'keeps the keywords, including the defaults the caller did not pass' do
      renderer.circle(1, 2, 3)

      expect(renderer.calls_to(:circle).first.options)
        .to eq(z: 50, color: nil, segments: 64)
    end

    it 'answers whether something was drawn at all' do
      renderer.line(0, 0, 1, 1)

      expect(renderer.drawn?(:line)).to be(true)
      expect(renderer.drawn?(:rect)).to be(false)
    end

    it 'records calls in the order they were made' do
      renderer.rect(0, 0, 1, 1)
      renderer.circle(0, 0, 1)
      renderer.rect(0, 0, 2, 2)

      expect(renderer.calls.map(&:name)).to eq(%i[rect circle rect])
    end

    it 'forgets everything on #clear, so one spec can drive several frames' do
      renderer.rect(0, 0, 1, 1)

      expect(renderer.clear.calls).to be_empty
    end
  end

  describe 'transform depth' do
    it 'records what was drawn inside a block, and how deep' do
      renderer.rotated(45, 0, 0) { renderer.rect(0, 0, 1, 1) }

      inner = renderer.calls_to(:rect).first
      expect(inner.depth).to eq(1)
      expect(inner.transforms.map(&:name)).to eq([:rotated])
    end

    it 'nests, outermost first' do
      renderer.translated(5, 5) do
        renderer.clipped(0, 0, 10, 10) { renderer.rect(0, 0, 1, 1) }
      end

      expect(renderer.calls_to(:rect).first.transforms.map(&:name))
        .to eq(%i[translated clipped])
    end

    it 'closes the block, so a later call is recorded outside it' do
      renderer.rotated(45, 0, 0) { renderer.rect(0, 0, 1, 1) }
      renderer.rect(2, 2, 1, 1)

      expect(renderer.calls_to(:rect).map(&:depth)).to eq([1, 0])
    end

    it 'closes the block even when it raises' do
      expect { renderer.rotated(45, 0, 0) { raise 'boom' } }.to raise_error('boom')
      renderer.rect(0, 0, 1, 1)

      expect(renderer.calls_to(:rect).first.depth).to be_zero
    end

    it 'records the transform itself as a call too' do
      renderer.translated(5, 7) { nil }

      expect(renderer.calls_to(:translated).map(&:args)).to eq([[5, 7]])
    end
  end
end
