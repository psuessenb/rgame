# frozen_string_literal: true

require_relative 'hot_path'

module RuboCop
  module Cop
    module Game
      # Disallow leaving a block with `return` or `break` on a per-frame path: a
      # lifecycle hook, a method tagged `# hot-path`, or any method in a file the
      # `EveryMethodIn` option names.
      #
      # Ruby allocates an object each time one of them leaves a block, to carry
      # the jump out through the method that yielded to it. So a search written
      # as `each { |f| return f if ... }` allocates once for every answer found
      # before the end, and `TileMap#frame_tile`, written that way, allocated
      # once for every animated tile in view on every frame. `find`, `any?` and
      # `index` answer the same question and allocate nothing, and so does a
      # `while` loop, from which `return` and `break` leave for free. `next`
      # stays inside its block and is never flagged.
      #
      # A lambda is a block here too: `return` in `-> { ... }` or in a
      # `define_method` block allocates the same way.
      #
      # @example
      #   # bad
      #   def frame_tile(tile, elapsed)
      #     frames.each { |shown, ends| return shown if elapsed < ends }
      #   end
      #
      #   # good
      #   def frame_tile(tile, elapsed)
      #     frames.find { |_shown, ends| elapsed < ends }.first
      #   end
      class NoBlockExitInHotPath < RuboCop::Cop::Base
        include HotPath

        MSG = 'Leaving a block with `%{keyword}` allocates an object each time it happens. ' \
              'Use `find`, `any?` or `index`, or a `while` loop, which leave for free.'

        BLOCKS = %i[block numblock itblock].freeze
        LOOPS = %i[while until while_post until_post for].freeze

        def on_return(node)
          check(node, :return)
        end

        def on_break(node)
          check(node, :break)
        end

        private

        def check(node, keyword)
          return unless leaves_block?(node, keyword)
          return unless every_method_hot? || hot_path_def?(node.each_ancestor(:def, :defs).first)

          add_offense(node.loc.keyword, message: format(MSG, keyword: keyword))
        end

        def leaves_block?(node, keyword)
          node.each_ancestor do |ancestor|
            return false if ancestor.type?(:def, :defs)
            return false if keyword == :break && LOOPS.include?(ancestor.type)
            return true if BLOCKS.include?(ancestor.type)
          end
          false
        end
      end
    end
  end
end
