# frozen_string_literal: true

require 'lint_roller'

require_relative 'rubocop/plugin'
require_relative 'rubocop/cop/game/draw_in_local_space'
require_relative 'rubocop/cop/game/no_block_exit_in_hot_path'
require_relative 'rubocop/cop/game/no_core_in_engine_layer'
require_relative 'rubocop/cop/game/no_engine_ivar'
require_relative 'rubocop/cop/game/no_engine_in_core_layer'
require_relative 'rubocop/cop/game/no_interpolation_in_hot_path'
require_relative 'rubocop/cop/game/no_literal_text'
require_relative 'rubocop/cop/game/no_needless_allocation'
