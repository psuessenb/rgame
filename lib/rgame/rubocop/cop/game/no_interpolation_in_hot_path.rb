# frozen_string_literal: true

require_relative 'hot_path'

module RuboCop
  module Cop
    module Game
      # Disallow string interpolation inside per-frame methods — the engine's lifecycle
      # hooks (`update`/`control`/`draw`/`_update`/`_draw`/`_control`) and any method
      # tagged `# hot-path`.
      #
      # These run every frame (~60/s), and string interpolation builds a brand-new
      # `String` each time it is evaluated (the `frozen_string_literal` pragma freezes
      # *literals*, not interpolated results). So a `"Score: #{n}"` here is a per-frame
      # allocation. The message names the answer, `RGame::Engine::Text`, rather than
      # asking for a hand-rolled cache: a `Text` renders again only when a variable
      # or the language changes, and reaches the translation tables.
      #
      # @example
      #   # bad
      #   def _draw(renderer, _view)
      #     renderer.text("Score: #{@score}", 10, 10)
      #   end
      #
      #   # good  (@score_label = RGame::Engine::Text.new('hud.score', :score), built once)
      #   def _draw(renderer, _view)
      #     renderer.text(@score_label.with(score: @score), 10, 10)
      #   end
      class NoInterpolationInHotPath < RuboCop::Cop::Base
        include HotPath

        MSG = 'Avoid string interpolation in a per-frame method: it allocates a String ' \
              'every frame. Build an RGame::Engine::Text once, outside it, and read it ' \
              'with `with`.'

        def on_def(node)
          return unless hot_path_def?(node)

          node.each_descendant(:dstr) do |dstr|
            add_offense(dstr) if interpolated?(dstr)
          end
        end

        private

        def interpolated?(dstr)
          dstr.children.any?(&:begin_type?)
        end
      end
    end
  end
end
