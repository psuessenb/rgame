# frozen_string_literal: true

require_relative 'hot_path'

module RuboCop
  module Cop
    module Game
      # Disallow string interpolation inside per-frame methods — the engine's lifecycle
      # hooks (`update`/`control`/`draw`/`on_update`/`on_draw`/`on_control`) and any method
      # tagged `# hot-path`.
      #
      # These run every frame (~60/s), and string interpolation builds a brand-new
      # `String` each time it is evaluated (the `frozen_string_literal` pragma freezes
      # *literals*, not interpolated results). So a `"Score: #{n}"` here is a per-frame
      # allocation. Build the string once — on construction, or when the value changes
      # (see `Engine::CachedLabel`) — and draw the cached copy.
      #
      # @example
      #   # bad
      #   def draw(renderer)
      #     renderer.text("Score: #{@score}", 10, 10)
      #   end
      #
      #   # good  (rebuilt only when @score changes)
      #   def draw(renderer)
      #     renderer.text(@score_label, 10, 10)
      #   end
      class NoInterpolationInHotPath < RuboCop::Cop::Base
        include HotPath

        MSG = 'Avoid string interpolation in a per-frame method: it allocates a String ' \
              'every frame. Build the string once (on change) and use the cached value.'

        def on_def(node)
          return unless hot_path_def?(node)

          node.each_descendant(:dstr) do |dstr|
            add_offense(dstr) if interpolated?(dstr)
          end
        end

        private

        # A `dstr` is interpolated when any direct child is a `#{...}` (begin) node;
        # plain adjacent/multiline literals have only `str` children.
        def interpolated?(dstr)
          dstr.children.any?(&:begin_type?)
        end
      end
    end
  end
end
