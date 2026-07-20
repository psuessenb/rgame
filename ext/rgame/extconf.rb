# extconf.rb — run by `ruby extconf.rb` to generate a Makefile via mkmf.
#
# mkmf is Ruby's "make makefile" library. It probes the system (headers,
# libraries, pkg-config) and writes a Makefile that knows how to compile a
# loadable extension (`rgame.so`) against the running Ruby's headers. This is
# the same tool that `gem install` uses under the hood, which is why the root
# Makefile was written to look like what mkmf emits — the mental model carries
# straight over.

require "mkmf"

# This extension compiles the pure-C engine sources (src/core.c,
# src/frame_loop.c) straight into rgame.so alongside the Ruby glue, instead of
# linking a prebuilt librgame_core.a. One build step, and it reuses the exact
# same sources the root Makefile builds.

# We're in ext/rgame/, so the project root is two directories up.
root = File.expand_path("../..", __dir__)

# Public API header only (include/rgame/core.h). core.c finds its *private*
# "frame_loop.h" on its own, because a quoted #include searches the including
# file's own directory (src/) first — so we don't add src/ to the include path.
$INCFLAGS << " -I#{root}/include"

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

# Tell make where to find the engine sources, then list them so they get
# compiled and linked in. $VPATH is make's search path for sources; $srcs is
# the explicit source list (basenames — VPATH resolves them to a directory).
# Dir.glob picks up the glue file(s) in *this* directory; we append the two
# engine sources from src/.
$VPATH << "#{root}/src"
$srcs = Dir.glob("#{$srcdir}/*.c").map { |path| File.basename(path) }
$srcs += %w[core.c frame_loop.c]

# Emits the Makefile. The name here ("rgame") must match the Init_rgame
# function in rgame_ext.c and the eventual `require "rgame"`.
create_makefile("rgame")
