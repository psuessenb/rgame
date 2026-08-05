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

# The engine sources live in this directory rather than a top-level src/:
# `gem install` unpacks the gem and runs this script, and an extension must be
# buildable from its own directory.
#
# They are grouped into subdirectories by subsystem (app, graphics, text, input,
# audio) plus ruby/ for the Ruby-facing glue and vendor/ for third-party code.
# mkmf's default is to compile every .c in the extension's *own* directory and
# nothing deeper, so the source list has to be spelled out — which is what
# $srcs and $VPATH below do.
#
#   $srcs  — what to compile. mkmf names each object after the source's
#            *basename*, so the .o files land flat in this directory no matter
#            how deep the .c was. Basenames therefore have to be unique across
#            the subdirectories; mkmf aborts with "source files duplication" if
#            they ever aren't, so that rule enforces itself.
#   $VPATH — where make looks for a source when a rule names it by basename.
#            The generic `.c.o` rule mkmf emits does exactly that, so without
#            this every object would come up as a missing prerequisite.
#
# vendor/ contributes only its <name>_impl.c translation units. The libraries
# themselves are #included *by* those files (stb_vorbis even ships as a .c), so
# compiling them separately would duplicate every symbol in them.
SOURCE_DIRS = %w[app graphics text input audio ruby].freeze

# Dir.glob sorts its results, so the object list is the same on every machine.
$srcs = SOURCE_DIRS.flat_map { |dir| Dir.glob("#{$srcdir}/#{dir}/*.c") } +
        Dir.glob("#{$srcdir}/vendor/*_impl.c")

(SOURCE_DIRS + %w[vendor]).each { |dir| $VPATH << "$(srcdir)/#{dir}" }

# The extension directory itself, so a cross-subsystem include names the folder
# it comes from: graphics/canvas.c says `#include "graphics/clip.h"`, and text/
# reaching into graphics/ is visible in the source rather than hidden in a
# search path. It is also what resolves `#include "vendor/stb_image.h"`.
# $(srcdir) stays literal here — make expands it, not Ruby.
$INCFLAGS << ' -I$(srcdir)'

# Public API header (include/rgame/core.h), so `#include "rgame/core.h"`
# resolves.
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
#
# Checked rather than assumed, unlike in the root Makefile. This script is what
# runs on someone else's machine during `gem install`, and a missing OpenGL
# development package is a routine thing to hit there. Without a check it
# surfaces as a linker error about an undefined `glClear` at the end of a long
# build; with one, the install stops on a sentence naming the package to
# install. Same reasoning as the SDL2 abort above.
#
# The header probed is the one the sources actually include — SDL's own
# <SDL2/SDL_opengl.h>, which resolves to GL/gl.h or OpenGL/gl.h per platform, so
# probing GL/gl.h directly would ask the wrong question off Linux. It needs
# SDL's cflags, which pkg_config folded into $CFLAGS just above.
abort 'SDL2 OpenGL header not found (SDL2/SDL_opengl.h). Install libsdl2-dev.' unless have_header('SDL2/SDL_opengl.h')

# `-lGL` is how OpenGL is linked on Linux and the BSDs; macOS wants
# `-framework OpenGL` instead. Only the first is implemented — as in the root
# Makefile, which hardcodes -lGL — so this aborts on a platform it cannot link
# rather than emitting undefined symbols for every gl* call. have_library
# appends -lGL to $libs itself when the probe succeeds.
unless have_library('GL', 'glClear')
  abort 'OpenGL library not found (-lGL). Install libgl1-mesa-dev. ' \
        '(macOS needs -framework OpenGL, which is not implemented yet.)'
end

$libs = append_library($libs, 'm')

# miniaudio's threading, and the dlopen it uses to find ALSA or PulseAudio at
# runtime — the property that makes audio cost no new system dependency. Both
# live in glibc on Linux/BSD. Windows and macOS need neither, and appending them
# unconditionally would fail the link there, so each is probed first.
$libs = append_library($libs, 'pthread') if have_library('pthread')
$libs = append_library($libs, 'dl') if have_library('dl')

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

# The vendored implementations, compiled with warnings off (see
# vendor/README.md). mkmf has no per-file flag setting, so the rules are
# appended to the Makefile it just wrote. An explicit rule for a specific
# target beats mkmf's generic .c.o suffix rule, so these are what get used for
# those objects and nothing else.
#
# Written from one list rather than one block per library: a second hand-copied
# rule is how the first one drifts. They are explicit rules rather than a `%`
# pattern because mkmf's Makefiles are meant to work with whatever `make` the
# platform has, and pattern rules are a GNU extension.
#
# `-w` comes last on the command line and switches every warning back off,
# which is simpler and more robust than trying to subtract -Wall -Wextra from
# $(CFLAGS) — everything else about how the extension compiles stays identical.
# Each vendored library's implementation TU (<name>_impl.c) and the file it
# instantiates. stb_vorbis is the odd one out: it ships as a .c, not a .h.
VENDORED = {
  'stb_image' => 'stb_image.h',
  'stb_truetype' => 'stb_truetype.h',
  'stb_vorbis' => 'stb_vorbis.c',
  'miniaudio' => 'miniaudio.h'
}.freeze

File.open('Makefile', 'a') do |makefile|
  VENDORED.each do |name, source|
    makefile.puts <<~MAKE

      #{name}_impl.#{$OBJEXT}: $(srcdir)/vendor/#{name}_impl.c $(srcdir)/vendor/#{source}
      \t$(ECHO) compiling vendored #{name} with warnings off
      \t$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) -w $(COUTFLAG)$@ -c $(srcdir)/vendor/#{name}_impl.c
    MAKE
  end

  # Rebuild everything when any of our headers changes.
  #
  # mkmf emits `$(OBJS): $(HDRS)` for this, but it builds HDRS by globbing the
  # extension's own directory only — with the headers a level down in
  # graphics/, text/ and the rest, HDRS comes out empty and editing a header
  # rebuilds *nothing*. That failure is silent: the build succeeds and links
  # objects compiled against the previous version of the struct.
  #
  # One coarse dependency rather than a real per-object dependency scan, for the
  # same reason the root Makefile treats the vendored sources as one list: this
  # is a small project where a full rebuild costs seconds, and a hand-maintained
  # dependency graph is a thing to get quietly wrong.
  headers = SOURCE_DIRS.flat_map { |dir| Dir.glob("#{$srcdir}/#{dir}/*.h") }
                       .map { |path| "$(srcdir)/#{path.delete_prefix("#{$srcdir}/")}" }

  makefile.puts "\n$(OBJS): #{headers.join(' ')}"
end
