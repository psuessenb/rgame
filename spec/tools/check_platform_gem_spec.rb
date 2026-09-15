# frozen_string_literal: true

require 'rubygems/package'
require 'rubygems/user_interaction'
require 'stringio'
require 'tmpdir'

require_relative '../../tools/check_platform_gem'

RSpec.describe CheckPlatformGem do
  describe '.broken_rules' do
    let(:root) { File.expand_path('../..', __dir__) }

    def build_source_gem(path)
      spec = Gem::Specification.load(File.join(root, 'rgame.gemspec'))
      Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
        Dir.chdir(root) { Gem::Package.build(spec, false, false, path) }
      end
    end

    it 'fails the source gem on every rule a gem without binaries can break' do
      Dir.mktmpdir('rgame-source-gem') do |dir|
        path = File.join(dir, 'rgame.gem')
        build_source_gem(path)

        rules = described_class.broken_rules(path, StringIO.new).map { it[/\Arule (\d)/, 1] }

        expect(rules.uniq).to eq(%w[1 2 3 4 5 6])
      end
    end
  end
end
