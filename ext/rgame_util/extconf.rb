# frozen_string_literal: true

require 'mkmf'

$CFLAGS << ' -std=gnu17 -Wall -Wextra'

$CFLAGS << ' -ffp-contract=off'

create_makefile('rgame/util_ext')
