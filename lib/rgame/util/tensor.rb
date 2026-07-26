# frozen_string_literal: true

# RGame::Tensor is implemented in C — see ext/rgame_util/tensor.c. It used to be
# a pure-Ruby class here; the public API (RGame::Tensor.new(width, height, depth,
# initial: nil), #[], #[]=, #width/#height/#depth) is unchanged, only the backing
# implementation moved to C for speed and a compact flat-array layout.
#
# The compiled extension is a separate .so from the SDL/GL engine, so requiring
# Tensor pulls in no graphics libraries. It loads from lib/rgame/util_ext.so,
# which the build (`make ext`) copies out of ext/rgame_util/.
require 'rgame/util_ext'
