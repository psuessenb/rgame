# frozen_string_literal: true

# extconf.rb — run by `ruby extconf.rb` to generate a Makefile via mkmf.
#
# mkmf is Ruby's "make makefile" library. It probes the system (headers,
# libraries, pkg-config) and writes a Makefile that knows how to compile a
# loadable extension (`core_ext.so`) against the running Ruby's headers.
# This is the same tool that `gem install` uses under the hood, which is why the
# root Makefile was written to look like what mkmf emits — the mental model
# carries straight over.
#
# This is the SDL/OpenGL half of the project: everything under RGame::Core.
# The graphics-free half lives in ../rgame_util (RGame::Util) and links none of
# these libraries.

require 'mkmf'

# The engine sources (core.c, frame_loop.c) live in this directory alongside
# the Ruby glue (core_ext.c), so mkmf's default behaviour — compile every .c
# in the extension directory into one .so — picks them all up with no extra
# configuration. That's also why they live here rather than in a top-level
# src/: `gem install` unpacks the gem and runs this script, and an extension
# must be buildable from its own directory.

# Public API header (include/rgame/core.h), so `#include "rgame/core.h"`
# resolves. core.c finds its *private* "frame_loop.h" on its own, because a
# quoted #include searches the including file's own directory first.
# $(srcdir) stays literal here — make expands it, not Ruby.
$INCFLAGS << ' -I$(srcdir)/include'

# RGame::Util's colour header, for the RGBA byte order the renderer writes into
# every vertex. It is header-only (static inline), so this creates no link
# dependency between the two extensions — they stay separate .so files. Both
# directories ship together in the gem, so the relative path holds there too.
$INCFLAGS << ' -I$(srcdir)/../rgame_util'

# SDL2: pkg_config("sdl2") shells out to pkg-config and folds the resulting
# cflags and libs into mkmf's globals ($CFLAGS/$libs) for us. Returns nil if
# SDL2 isn't found, so we can fail with a clear message instead of a confusing
# later compile error.
abort 'SDL2 not found (pkg-config --exists sdl2 failed). Install libsdl2-dev.' unless pkg_config('sdl2')

# OpenGL + libm, matching the link line in the root Makefile. append_library
# adds `-lGL`/`-lm` in the right spot on the link command.
$libs = append_library($libs, 'GL')
$libs = append_library($libs, 'm')

# The vendored PNG decoder. stb_image is a single header that becomes an
# implementation in exactly one .c file (stb_image_impl.c). That file is the
# only one in the project compiled without -Wall -Wextra — third-party code
# rarely survives them, and everything we wrote is meant to stay warning-clean.
# The carve-out itself is at the bottom of this file. See vendor/README.md.
#
# What is needed *here* is the include path: stb_image_impl.c and image.c both
# say #include "vendor/stb_image.h", so the extension directory has to be on
# the path. A quoted include finds it relative to the including file when
# compiling in place, but mkmf may compile from elsewhere, so say it outright.
$INCFLAGS << ' -I$(srcdir)'

# Match the project's C standard and warning flags. Note: gnu17, not plain
# c17 — Ruby's headers occasionally lean on GNU extensions, and gnu17 is a
# superset of c17 so core.c (which targets c17) still compiles fine.
$CFLAGS << ' -std=gnu17 -Wall -Wextra'

# Emits the Makefile. "rgame/core_ext" -> loaded via
# `require "rgame/core_ext"`, entry point Init_core_ext (the basename)
# in core_ext.c. Namespacing it under rgame/ mirrors rgame/util_ext, keeps
# both extensions off the top of the load path, and — importantly — leaves the
# bare name "rgame" to lib/rgame.rb, which is the pure-Ruby entry point.
create_makefile('rgame/core_ext')

# One object compiled with warnings off: the vendored stb_image implementation
# (see stb_image_impl.c and vendor/README.md). mkmf has no per-file flag
# setting, so the rule is appended to the Makefile it just wrote. An explicit
# rule for a specific target beats mkmf's generic .c.o suffix rule, so this is
# what gets used for that one object and nothing else.
#
# `-w` comes last on the command line and switches every warning back off,
# which is simpler and more robust than trying to subtract -Wall -Wextra from
# $(CFLAGS) — everything else about how the extension compiles stays identical.
File.open('Makefile', 'a') do |makefile|
  makefile.puts <<~MAKE

    stb_image_impl.#{$OBJEXT}: $(srcdir)/stb_image_impl.c $(srcdir)/vendor/stb_image.h
    \t$(ECHO) compiling vendored stb_image with warnings off
    \t$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) -w $(COUTFLAG)$@ -c $(srcdir)/stb_image_impl.c
  MAKE
end
