# frozen_string_literal: true

RSpec.describe FakeRenderer do
  # Half of why this file exists: the fake is run against the same contract as
  # the real renderer, so it cannot quietly fall behind it. The other half is
  # the recording itself, which engine specs assert against.
  subject(:renderer) { described_class.new }

  # The contract's hook. The fake needs no frame to draw into, so this just
  # yields; the real renderer's version opens a window and runs one.
  #
  # A StubImage rather than a bare Symbol: since the renderer resolves an id
  # that is not an image, a Symbol here would be ambiguous between "this is the
  # image" and "this names one". The stand-in type is what makes the fake
  # dispatch the way the real renderer dispatches on Core::Image.
  def render = yield(renderer, StubImage.new(4, 4))

  it_behaves_like 'a renderer'

  describe 'recording' do
    it 'keeps each call with its positional arguments' do
      renderer.rect(10, 20, 30, 40)

      expect(renderer.calls_to(:rect).map(&:args)).to eq([[10, 20, 30, 40]])
    end

    it 'keeps the keywords, including the defaults the caller did not pass' do
      renderer.circle(1, 2, 3)

      expect(renderer.calls_to(:circle).first.options)
        .to eq(z: 0, color: nil, segments: 64)
    end

    # The real renderer defaults every drawing method to one z, so call order
    # decides between them; a fake that kept a different default for one kind
    # would sort a headless spec's frame differently from the game's.
    it 'defaults every drawing method to the same z' do
      renderer.rect(0, 0, 1, 1)
      renderer.line(0, 0, 1, 1)
      renderer.circle(0, 0, 1)
      renderer.quad(0, 0, 1, 0, 1, 1, 0, 1)
      renderer.triangle(0, 0, 1, 0, 0, 1)
      renderer.debug_box(0, 0, 1, 1)
      renderer.text('a', 0, 0)

      expect(renderer.calls.map { it.options[:z] }.uniq).to eq([0])
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

    it 'keeps the String a label converted to, not the label' do
      # What a frame showed: the label may read otherwise by the next one.
      label = instance_double(String, to_str: 'Score')
      renderer.text(label, 10, 20)

      expect(renderer.calls_to(:text).first.args).to eq(['Score', 10, 20])
      expect(renderer.calls_to(:text).first.args.first).to be_an_instance_of(String)
    end

    it 'forgets everything on #clear, so one spec can drive several frames' do
      renderer.rect(0, 0, 1, 1)

      expect(renderer.clear.calls).to be_empty
    end
  end

  describe 'baking with #record' do
    it 'collects what the block drew, and does not put it in this frame' do
      baked = renderer.record do
        renderer.rect(0, 0, 10, 10)
        renderer.circle(5, 5, 3)
      end

      expect(baked.calls.map(&:name)).to eq(%i[rect circle])
      expect(renderer.calls).to be_empty
    end

    it 'records each replay, on the recording and on the renderer' do
      baked = renderer.record { renderer.rect(0, 0, 1, 1) }
      baked.draw(10, 20, z: 3)

      expect(baked.draws.map(&:args)).to eq([[10, 20]])
      expect(baked.draws.first.options).to eq(z: 3, color: nil)
      expect(renderer.calls_to(:recording_draw).first.args).to eq([baked, 10, 20])
    end

    it 'defaults the replay to the origin' do
      baked = renderer.record { renderer.rect(0, 0, 1, 1) }
      baked.draw

      expect(baked.draws.first.args).to eq([0, 0])
    end

    it 'goes back to recording into the frame afterwards' do
      renderer.record { renderer.rect(0, 0, 1, 1) }
      renderer.circle(0, 0, 1)

      expect(renderer.calls.map(&:name)).to eq([:circle])
    end

    it 'says whether anything was baked' do
      expect(renderer.record { nil }).to be_empty
      expect(renderer.record { renderer.rect(0, 0, 1, 1) }).not_to be_empty
    end

    it 'stops recording when the block raises' do
      expect { renderer.record { raise 'boom' } }.to raise_error('boom')

      renderer.rect(0, 0, 1, 1)
      expect(renderer.calls.map(&:name)).to eq([:rect])
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
