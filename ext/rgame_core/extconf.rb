# frozen_string_literal: true

require 'mkmf'

SOURCE_DIRS = %w[app graphics text input audio ruby].freeze

SHARED_UTIL_SOURCES = %w[typeface.c].freeze

SHARED_UTIL_VISIBILITY = RbConfig::CONFIG['host_os'].match?(/mingw|mswin|cygwin/) ? '' : '-fvisibility=hidden'

VENDORED = {
  'stb_image' => 'vendor/stb_image.h',
  'stb_truetype' => '../rgame_util/vendor/stb_truetype.h',
  'stb_vorbis' => 'vendor/stb_vorbis.c',
  'miniaudio' => 'vendor/miniaudio.h'
}.freeze

def vendored_impl(name, source) = "#{File.dirname(source)}/#{name}_impl.c"

$srcs = SOURCE_DIRS.flat_map { |dir| Dir.glob("#{$srcdir}/#{dir}/*.c") } +
        VENDORED.map { |name, source| "#{$srcdir}/#{vendored_impl(name, source)}" } +
        SHARED_UTIL_SOURCES.map { |source| "#{$srcdir}/../rgame_util/#{source}" }

(SOURCE_DIRS + %w[vendor]).each { |dir| $VPATH << "$(srcdir)/#{dir}" }

$INCFLAGS << ' -I$(srcdir)'

$INCFLAGS << ' -I$(srcdir)/include'

$INCFLAGS << ' -I$(srcdir)/../rgame_util'

static_sdl2 = with_config('sdl2-static')

if static_sdl2
  static_sdl2 = File.expand_path(static_sdl2)
  pc_dir = File.join(static_sdl2, 'lib', 'pkgconfig')
  abort "No SDL2 under #{static_sdl2}. Run: rake sdl2" unless File.exist?(File.join(pc_dir, 'sdl2.pc'))

  ENV['PKG_CONFIG_LIBDIR'] = pc_dir
  abort "pkg-config could not read #{pc_dir}/sdl2.pc" unless pkg_config('sdl2')

  static_only = Shellwords.shellwords(pkg_config('sdl2', 'libs', 'static').to_s) - Shellwords.shellwords($libs)
  $libs += " #{static_only.shelljoin}" unless static_only.empty?
else
  abort 'SDL2 not found (pkg-config --exists sdl2 failed). Install libsdl2-dev.' unless pkg_config('sdl2')
end

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

$CFLAGS << ' -ffp-contract=off'

if static_sdl2
  case RbConfig::CONFIG['host_os']
  when /linux/ then $LDFLAGS << ' -Wl,--exclude-libs,ALL'
  when /darwin/ then $LDFLAGS << ' -Wl,-exported_symbol,_Init_core_ext'
  end
end

unless enable_config('libruby-link', true) || RbConfig::CONFIG['host_os'].match?(/mingw|mswin|cygwin/)
  $LIBRUBYARG = ''
  $DEFLIBPATH.delete('$(libdir)')
end

create_makefile('rgame/core_ext')

File.open('Makefile', 'a') do |makefile|
  VENDORED.each do |name, source|
    impl = "$(srcdir)/#{vendored_impl(name, source)}"
    flags = source.start_with?('../rgame_util/') ? SHARED_UTIL_VISIBILITY : ''
    makefile.puts <<~MAKE

      #{name}_impl.#{$OBJEXT}: #{impl} $(srcdir)/#{source}
      \t$(ECHO) compiling vendored #{name} with warnings off
      \t$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) #{flags} -w $(COUTFLAG)$@ -c #{impl}
    MAKE
  end

  SHARED_UTIL_SOURCES.each do |source|
    makefile.puts <<~MAKE

      #{File.basename(source, '.c')}.#{$OBJEXT}: $(srcdir)/../rgame_util/#{source}
      \t$(ECHO) compiling $(<)
      \t$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) #{SHARED_UTIL_VISIBILITY} $(COUTFLAG)$@ -c $(srcdir)/../rgame_util/#{source}
    MAKE
  end

  headers = (SOURCE_DIRS.flat_map { |dir| Dir.glob("#{$srcdir}/#{dir}/*.h") } +
             Dir.glob("#{$srcdir}/../rgame_util/*.h"))
            .map { |path| "$(srcdir)/#{path.delete_prefix("#{$srcdir}/")}" }

  makefile.puts "\n$(OBJS): #{headers.join(' ')}"
end
