# frozen_string_literal: true

RSpec.describe Engine::ActionMapper do
  # A stand-in InputBackend: "down" is just the set of held physical ids.
  # Anonymous (not a constant) so it doesn't leak out of the example group.
  let(:fake_backend) do
    Struct.new(:down_ids, :px, :py) do
      def down?(id) = down_ids.include?(id)
      def pointer_x = px || 0
      def pointer_y = py || 0
    end
  end

  let(:map) do
    {
      move_x: { axis: %i[left right] },
      confirm: { button: %i[confirm] }
    }
  end

  def poll(*down_ids)
    described_class.new(map).poll(fake_backend.new(down_ids))
  end

  it 'yields +1.0 on the positive binding' do
    expect(poll(:right).axis(:move_x)).to eq(1.0)
  end

  it 'yields -1.0 on the negative binding' do
    expect(poll(:left).axis(:move_x)).to eq(-1.0)
  end

  it 'cancels to 0.0 when both bindings are down' do
    expect(poll(:left, :right).axis(:move_x)).to eq(0.0)
  end

  it 'is neutral (0.0) when nothing is down' do
    expect(poll.axis(:move_x)).to eq(0.0)
  end

  it 'reports a held button' do
    expect(poll(:confirm).held?(:confirm)).to be(true)
  end

  it 'reports an unheld button as false' do
    expect(poll.held?(:confirm)).to be(false)
  end

  # Edge detection compares against the previous poll, so it needs one mapper
  # polled repeatedly (not a fresh mapper per poll like the helper above).
  describe 'edge detection' do
    let(:backend) { fake_backend.new([]) }
    let(:mapper) { described_class.new(map) }

    def poll_with(*down_ids)
      backend.down_ids = down_ids
      mapper.poll(backend)
    end

    it 'pressed? is true only on the frame the button goes down' do
      expect(poll_with.pressed?(:confirm)).to be(false)           # stays up
      expect(poll_with(:confirm).pressed?(:confirm)).to be(true)  # up -> down
      expect(poll_with(:confirm).pressed?(:confirm)).to be(false) # held
    end

    it 'released? is true only on the frame the button goes up' do
      poll_with(:confirm)                                          # down
      expect(poll_with(:confirm).released?(:confirm)).to be(false) # held
      expect(poll_with.released?(:confirm)).to be(true)            # down -> up
      expect(poll_with.released?(:confirm)).to be(false)           # stays up
    end
  end
end
