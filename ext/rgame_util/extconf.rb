# frozen_string_literal: true

# extconf.rb — mkmf script for the `rgame/util_ext` extension.
#
# This is the deliberately minimal half of the project's two extensions. Unlike
# ext/rgame_platform/extconf.rb (which links SDL2 + OpenGL for the engine), the
# util extension is pure data: RGame::Util::Tensor and future pure-logic helpers
# that must NOT drag SDL/GL into the process just to be required. So there is no
# pkg_config, no -lGL — only the C standard + warning flags.
#
# That split is the rule for deciding where new code goes: anything depending on
# SDL/OpenGL (or on something that does) belongs under RGame::Platform in
# ../rgame_platform; everything else belongs here under RGame::Util.

require 'mkmf'

# Match the project's C standard and warning flags. gnu17 (not plain c17) because
# Ruby's headers lean on GNU extensions; gnu17 is a superset so the code still
# compiles as c17. Same choice as ext/rgame_platform/extconf.rb.
$CFLAGS << ' -std=gnu17 -Wall -Wextra'

# "rgame/util_ext" -> the built object is loaded via `require "rgame/util_ext"`
# and its entry point is Init_util_ext (the basename). Naming it under rgame/
# (rather than plain "util_ext") keeps it namespaced alongside the engine's
# rgame/platform_ext.so and off the top of the load path, leaving the bare name
# "rgame" to lib/rgame.rb.
create_makefile('rgame/util_ext')
