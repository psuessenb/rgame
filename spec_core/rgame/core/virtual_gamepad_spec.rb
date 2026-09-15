# frozen_string_literal: true

require 'json'
require 'open3'

RSpec.describe RGame::Core::VirtualGamepad do
  # What a pad does around SDL's lifetime. Both cases need a process in which no
  # App is alive, and the suite's own Apps are collected whenever GC decides, so
  # these run in a child process and report back as JSON.
  def in_a_fresh_process(body)
    lib = File.expand_path('../../../lib', __dir__)
    script = "require 'rgame/core'\nrequire 'json'\n#{body}"
    output, errors, status = Open3.capture3(RbConfig.ruby, '-I', lib, '-e', script)
    expect(status).to be_success, errors
    JSON.parse(output.lines.last)
  end

  describe '.new' do
    it 'raises when no App is open, because SDL is not running' do
      result = in_a_fresh_process(<<~RUBY)
        begin
          RGame::Core::VirtualGamepad.new
          puts JSON.generate(raised: nil)
        rescue RuntimeError => e
          puts JSON.generate(raised: e.message)
        end
      RUBY

      expect(result['raised']).to include('no app is open')
    end
  end

  describe 'a pad that outlives every App' do
    it 'raises instead of touching SDL, and can still be detached' do
      result = in_a_fresh_process(<<~RUBY)
        def attach_with_an_app
          RGame::Core::App.new(width: 64, height: 48, caption: 'virtual-gamepad-spec')
          RGame::Core::VirtualGamepad.new
        end

        pad = attach_with_an_app
        4.times { GC.start(full_mark: true, immediate_sweep: true) }

        raised = begin
          pad.set_button(0, true)
          nil
        rescue RuntimeError => e
          e.message
        end
        pad.detach
        puts JSON.generate(raised: raised, detached: true)
      RUBY

      expect(result['raised']).to include('outlived SDL')
      expect(result['detached']).to be(true)
    end
  end

  describe '#set_axis' do
    it "refuses a value outside SDL's axis range" do
      results = {}

      Class.new(RGame::Core::App) do
        define_method(:initialize) { super(width: 64, height: 48, caption: 'virtual-gamepad-spec') }

        define_method(:draw) do
          pad = RGame::Core::VirtualGamepad.new
          results[:in_range] = pad.set_axis(0, -32_768)
          begin
            pad.set_axis(0, 32_768)
          rescue RangeError => e
            results[:error] = e
          end
          pad.detach
          close
        end
      end.new.run

      expect(results[:in_range]).to be(true)
      expect(results[:error]).to be_a(RangeError)
    end
  end
end
