# frozen_string_literal: true

# The engine core must be testable with zero Gosu loaded. Requiring only
# lib/engine here is itself a guard: if any core file reaches for Gosu, these
# specs fail to load.
require_relative '../lib/rgame'

# Shared spec support (custom matchers, allocation-free fakes); never the specs themselves.
Dir[File.join(__dir__, 'support', '**', '*.rb')].grep_v(/_spec\.rb\z/).each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
end
