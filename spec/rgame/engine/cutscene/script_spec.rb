# frozen_string_literal: true

RSpec.describe RGame::Engine::Cutscene::Script do
  it 'builds the five kinds of step, in order, and freezes' do
    script = described_class.build do
      run { |c| c << :ran }
      wait 1
      hold { |c| c }
      talk { |c| c }
      press
    end
    expect([script.steps.map(&:kind), script.steps[1].seconds, script.size, script.frozen?,
            script.steps.frozen?]).to eq([%i[run wait hold talk press], 1.0, 5, true, true])
  end

  it 'keeps each block to call with the context' do
    log = []
    described_class.build { run { |c| c << :ran } }.steps.first.block.call(log)
    expect(log).to eq([:ran])
  end

  describe 'what build refuses' do
    it 'a script with no steps' do
      expect { described_class.build { nil } }.to raise_error(ArgumentError, /at least one step/)
    end

    it 'no block' do
      expect { described_class.build }.to raise_error(ArgumentError, /needs a block/)
    end

    it 'a run, a hold or a talk with no block' do
      %i[run hold talk].each do |kind|
        expect { described_class.build { public_send(kind) } }.to raise_error(ArgumentError, /#{kind} needs a block/)
      end
    end

    it 'a press with a block' do
      expect { described_class.build { press { nil } } }.to raise_error(ArgumentError, /press takes no block/)
    end

    it 'a wait that is not a number, or not positive' do
      expect { described_class.build { wait '1' } }.to raise_error(TypeError, /number of seconds/)
      expect { described_class.build { wait 0 } }.to raise_error(ArgumentError, /positive/)
    end

    it 'new, so every script is checked' do
      expect { described_class.new([]) }.to raise_error(NoMethodError)
    end
  end
end
