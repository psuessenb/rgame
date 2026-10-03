# frozen_string_literal: true

require 'tmpdir'
require_relative '../../../tools/drive_test_project'

RSpec.describe DriveTestProject::Script do
  let(:dir) { Dir.mktmpdir('rgame-script-') }

  after { FileUtils.remove_entry(dir) }

  def load_script(source)
    path = File.join(dir, 'script.rb')
    File.write(path, source)
    described_class.load(path)
  end

  describe '#run_length' do
    it 'plays at least 240 ticks for a shorter script' do
      expect(load_script('idle 30').run_length).to eq(240)
    end

    it 'plays the whole of a longer script' do
      expect(load_script('idle 300').run_length).to eq(300)
    end

    it 'plays the longest track to its end' do
      script = load_script(<<~RUBY)
        on(controls::KEYBOARD) { idle 300 }
        on(controls.gamepad(0)) { idle 500 }
      RUBY

      expect(script.run_length).to eq(500)
    end

    it 'plays what ticks declares, past the script and under 240 alike' do
      expect([load_script("idle 300\nticks 360"), load_script("idle 30\nticks 100")].map(&:run_length))
        .to eq([360, 100])
    end
  end

  describe '#ticks' do
    it 'refuses a count that stops before the script ends, naming both' do
      expect { load_script("idle 883\nticks 240") }
        .to raise_error(ArgumentError, /script\.rb declares ticks 240, and its script runs 883/)
    end

    it 'refuses a count that is not a positive Integer' do
      %w[0 -1 1.5 nil].each do |count|
        expect { load_script("ticks #{count}") }.to raise_error(ArgumentError, /positive Integer/)
      end
    end
  end
end
