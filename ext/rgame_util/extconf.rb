# extconf.rb — mkmf script for the `rgame/util_ext` extension.
#
# This is the second, deliberately minimal extension in the project. Unlike
# ext/rgame/extconf.rb (which links SDL2 + OpenGL for the engine), the util
# extension is pure data: RGame::Tensor and future pure-logic helpers that must
# NOT drag SDL/GL into the process just to be required. So there is no
# pkg_config, no -lGL — only the C standard + warning flags.

require "mkmf"

# Match the project's C standard and warning flags. gnu17 (not plain c17) because
# Ruby's headers lean on GNU extensions; gnu17 is a superset so the code still
# compiles as c17. Same choice as ext/rgame/extconf.rb.
$CFLAGS << " -std=gnu17 -Wall -Wextra"

# "rgame/util_ext" -> the built object is loaded via `require "rgame/util_ext"`
# and its entry point is Init_util_ext (the basename). Naming it under rgame/
# (rather than plain "util_ext") keeps it namespaced alongside the engine's
# eventual rgame/rgame.so and off the top of the load path.
create_makefile("rgame/util_ext")
