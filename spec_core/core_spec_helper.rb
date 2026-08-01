# frozen_string_literal: true

# Entry point for the RGame::Core spec suite (`rake spec:core`).
#
# This is the suite that is *allowed* to load SDL and OpenGL. Its counterpart,
# spec/, must never do so — which is why the two live in separate directories
# with separate runners rather than sharing a root and an exclude rule. See
# CLAUDE.md, "Why the Ruby specs are two suites, in two directories".
#
# Core used to be untested here because Gosu occupied this layer and shipped
# its own specs. Replacing Gosu made this ours to cover.
#
# The helper is named core_spec_helper (not spec_helper) so it can never be
# picked up by the headless suite's `--require spec_helper`.

require_relative 'support/headless_display'
HeadlessDisplay.start

require_relative '../lib/rgame/core'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!

  # Specs that drive real keystrokes only work where XTEST does.
  config.filter_run_excluding(:needs_key_injection) unless HeadlessDisplay.can_inject_keys?
end
