# frozen_string_literal: true

require 'mkmf'

$CFLAGS << ' -std=gnu17 -Wall -Wextra'

$CFLAGS << ' -ffp-contract=off'

unless enable_config('libruby-link', true) || RbConfig::CONFIG['host_os'].match?(/mingw|mswin|cygwin/)
  $LIBRUBYARG = ''
  $DEFLIBPATH.delete('$(libdir)')
end

create_makefile('rgame/util_ext')
