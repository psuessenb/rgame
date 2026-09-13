# frozen_string_literal: true

require 'mkmf'

SOURCE_DIRS = %w[app graphics text input audio ruby].freeze

$srcs = SOURCE_DIRS.flat_map { |dir| Dir.glob("#{$srcdir}/#{dir}/*.c") } +
        Dir.glob("#{$srcdir}/vendor/*_impl.c")

(SOURCE_DIRS + %w[vendor]).each { |dir| $VPATH << "$(srcdir)/#{dir}" }

$INCFLAGS << ' -I$(srcdir)'

$INCFLAGS << ' -I$(srcdir)/include'

$INCFLAGS << ' -I$(srcdir)/../rgame_util'

abort 'SDL2 not found (pkg-config --exists sdl2 failed). Install libsdl2-dev.' unless pkg_config('sdl2')

abort 'SDL2 OpenGL header not found (SDL2/SDL_opengl.h). Install libsdl2-dev.' unless have_header('SDL2/SDL_opengl.h')

case RbConfig::CONFIG['host_os']
when /darwin/
  unless have_framework('OpenGL')
    abort 'OpenGL framework not found. It ships with macOS, so this usually means ' \
          'the command line tools are missing: xcode-select --install'
  end
when /mingw|mswin|cygwin/
  unless have_library('opengl32', 'glClear')
    abort 'opengl32 not found. It is part of Windows itself, so this means an ' \
          'incomplete MSYS2 toolchain: pacman -S mingw-w64-ucrt-x86_64-gcc'
  end
else
  unless have_library('GL', 'glClear')
    abort 'OpenGL library not found (-lGL). Install the OpenGL development package: ' \
          'libgl1-mesa-dev on Debian/Ubuntu, mesa-libGL-devel on Fedora.'
  end
end

$libs = append_library($libs, 'm')

$libs = append_library($libs, 'pthread') if have_library('pthread')
$libs = append_library($libs, 'dl') if have_library('dl')

$CFLAGS << ' -std=gnu17 -Wall -Wextra'

create_makefile('rgame/core_ext')

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

  headers = SOURCE_DIRS.flat_map { |dir| Dir.glob("#{$srcdir}/#{dir}/*.h") }
                       .map { |path| "$(srcdir)/#{path.delete_prefix("#{$srcdir}/")}" }

  makefile.puts "\n$(OBJS): #{headers.join(' ')}"
end
