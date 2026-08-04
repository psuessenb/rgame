# frozen_string_literal: true

# The gem's version, and deliberately nothing else.
#
# rgame.gemspec loads this file directly to fill in `spec.version`, which
# happens before either extension is compiled — so this file must never require
# anything that reaches for `rgame/util_ext` or `rgame/core_ext`. Reopening the
# module here is enough; the extensions define `RGame` too, and doing so twice
# is harmless.
module RGame
  VERSION = '0.1.0'
end
