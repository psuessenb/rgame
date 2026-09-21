# frozen_string_literal: true

require 'json'
require_relative 'child_ruby'

# Runs Ruby in a child process with a chosen locale environment, and answers
# whether this platform's SDL reads that environment at all.
#
# A child rather than this process, because SDL reads the environment on every
# call: changing `ENV['LANG']` here would leak into every example after it.
#
# `LANG` decides the locale only where SDL reads it — measured on Linux, SDL
# 2.0.20 reads `LANG` and then `LANGUAGE`. macOS and Windows ask the OS instead.
# So the examples that set it are gated on a probe, the way
# `VirtualGamepad.button_state_supported?` gates pad presses, rather than on
# `host_os`: they run wherever it works.
module LocaleEnvironment
  # Every variable SDL or the C library might consult, cleared unless given.
  CLEARED = { 'LANG' => nil, 'LANGUAGE' => nil, 'LC_ALL' => nil, 'LC_MESSAGES' => nil }.freeze

  class << self
    # Runs `script` with `env` over a cleared locale environment and returns
    # what it printed, parsed as JSON. Raises with the child's output if it fails.
    def run(script, env: {}, chdir: Dir.pwd)
      output, errors, status = ChildRuby.capture(script, env: CLEARED.merge(env), chdir: chdir)
      raise "child failed (#{status}):\n#{output}#{errors}" unless status.success?

      JSON.parse(output.lines.last)
    end

    # `RGame::Core.preferred_locales` under `LANG=lang`.
    def preferred_under(lang)
      run("require 'rgame/core'; require 'json'; puts JSON.generate(RGame::Core.preferred_locales)",
          env: { 'LANG' => lang })
    end

    # Whether setting `LANG` decides the preferred locales here. Memoised: it
    # spawns a process, and the answer cannot change within one.
    def follows_lang?
      return @follows_lang unless @follows_lang.nil?

      @follows_lang = preferred_under('fr_CA.UTF-8').first == 'fr-CA'
    end
  end
end
