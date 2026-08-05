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

# The contracts live in spec/, and are deliberately shared: the fakes there and
# the real implementations here are both run against them, so a fake cannot
# drift into describing something that no longer exists. See CLAUDE.md, "Fakes
# must be checked against the same contract as the real thing". Only the shared
# examples cross the line — no spec/ *_spec.rb is loaded here, and nothing in
# spec/ ever loads Core.
require_relative '../spec/support/shared_examples/a_renderer'
require_relative '../spec/support/shared_examples/an_audio_server'

# The fakes cross too, and for a related reason. The pure-Ruby classes under
# RGame::Core — SpriteSheet, NineSlice and friends — are handed a renderer and
# call it by name, so their sharpest test is "these exact calls, in this order",
# which is what FakeRenderer records. They cannot be specced from spec/, because
# naming them loads the extension. So the fake comes here instead of the spec
# going there.
#
# Safe because a fake that has drifted from the real thing is already a failing
# example on the other side: fake_renderer_spec.rb runs it against the same
# contract this file loads above.
require_relative '../spec/support/fake_renderer'
require_relative '../spec/support/fake_recording'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!

  # Specs that drive real keystrokes only work where XTEST does.
  config.filter_run_excluding(:needs_key_injection) unless HeadlessDisplay.can_inject_keys?
end
