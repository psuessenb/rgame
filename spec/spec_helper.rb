# frozen_string_literal: true

# Requiring only lib/rgame is itself the guard this suite is built on: it loads
# RGame::Util and RGame::Engine — everything that runs without a window — so SDL
# and OpenGL are absent from the process and `RGame::Core` is an undefined
# constant. Anything here that reached for it fails loudly rather than quietly
# working. See CLAUDE.md, "Why the Ruby specs are two suites, in two
# directories", and spec/rgame/no_graphics_spec.rb, which asserts the first
# half of that rather than trusting it.
require_relative '../lib/rgame'

# Shared spec support (custom matchers, allocation-free fakes); never the specs themselves.
Dir[File.join(__dir__, 'support', '**', '*.rb')].grep_v(/_spec\.rb\z/).each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!

  # I18n is global, so every example starts from empty tables, and a key a spec
  # draws without loading fails the example instead of drawing itself.
  config.before do
    RGame::Engine::I18n.reset
    RGame::Engine::I18n.missing = :raise
  end
end
