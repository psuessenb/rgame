# frozen_string_literal: true

# Requiring only lib/rgame is itself the guard this suite is built on: it loads
# RGame::Util and nothing else, so SDL and OpenGL are absent from the process
# and `RGame::Core` is an undefined constant. Anything here that reached for
# either fails loudly rather than quietly working. See CLAUDE.md, "Why the Ruby
# specs are two suites, in two directories".
require_relative '../lib/rgame'
require_relative '../lib/rgame/engine'

# Shared spec support (custom matchers, allocation-free fakes); never the specs themselves.
Dir[File.join(__dir__, 'support', '**', '*.rb')].grep_v(/_spec\.rb\z/).each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
end
