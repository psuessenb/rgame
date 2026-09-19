# frozen_string_literal: true

require 'mkmf'

$CFLAGS << ' -std=gnu17 -Wall -Wextra'

$CFLAGS << ' -ffp-contract=off'

unless enable_config('libruby-link', true) || RbConfig::CONFIG['host_os'].match?(/mingw|mswin|cygwin/)
  $LIBRUBYARG = ''
  $DEFLIBPATH.delete('$(libdir)')
end

$srcs = Dir.glob("#{$srcdir}/*.c") + Dir.glob("#{$srcdir}/vendor/*_impl.c")
$VPATH << '$(srcdir)/vendor'

create_makefile('rgame/util_ext')

File.open('Makefile', 'a') do |makefile|
  makefile.puts <<~MAKE

    stb_truetype_impl.#{$OBJEXT}: $(srcdir)/vendor/stb_truetype_impl.c $(srcdir)/vendor/stb_truetype.h
    \t$(ECHO) compiling vendored stb_truetype with warnings off
    \t$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) -w $(COUTFLAG)$@ -c $(srcdir)/vendor/stb_truetype_impl.c
  MAKE
end
