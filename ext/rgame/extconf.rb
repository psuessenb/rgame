# extconf.rb — run by `ruby extconf.rb` to generate a Makefile via mkmf.
#
# mkmf is Ruby's "make makefile" library. It probes the system (headers,
# libraries, pkg-config) and writes a Makefile that knows how to compile a
# loadable extension (`rgame.so`) against the running Ruby's headers. This is
# the same tool that `gem install` uses under the hood, which is why the root
# Makefile was written to look like what mkmf emits — the mental model carries
# straight over.

require "mkmf"

# The engine sources (core.c, frame_loop.c) live in this directory alongside
# the Ruby glue (rgame_ext.c), so mkmf's default behaviour — compile every .c
# in the extension directory into rgame.so — picks them all up with no extra
# configuration. That's also why they live here rather than in a top-level
# src/: `gem install` unpacks the gem and runs this script, and an extension
# must be buildable from its own directory.

# Public API header (include/rgame/core.h), so `#include "rgame/core.h"`
# resolves. core.c finds its *private* "frame_loop.h" on its own, because a
# quoted #include searches the including file's own directory first.
# $(srcdir) stays literal here — make expands it, not Ruby.
$INCFLAGS << " -I$(srcdir)/include"

# SDL2: pkg_config("sdl2") shells out to pkg-config and folds the resulting
# cflags and libs into mkmf's globals ($CFLAGS/$libs) for us. Returns nil if
# SDL2 isn't found, so we can fail with a clear message instead of a confusing
# later compile error.
unless pkg_config("sdl2")
  abort "SDL2 not found (pkg-config --exists sdl2 failed). Install libsdl2-dev."
end

# OpenGL + libm, matching the link line in the root Makefile. append_library
# adds `-lGL`/`-lm` in the right spot on the link command.
$libs = append_library($libs, "GL")
$libs = append_library($libs, "m")

# Match the project's C standard and warning flags. Note: gnu17, not plain
# c17 — Ruby's headers occasionally lean on GNU extensions, and gnu17 is a
# superset of c17 so core.c (which targets c17) still compiles fine.
$CFLAGS << " -std=gnu17 -Wall -Wextra"

# Emits the Makefile. The name here ("rgame") must match the Init_rgame
# function in rgame_ext.c and the eventual `require "rgame"`.
create_makefile("rgame")
