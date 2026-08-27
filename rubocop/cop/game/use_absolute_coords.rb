# frozen_string_literal: true

require_relative 'hot_path'

module RuboCop
  module Cop
    module Game
      # Disallow reading a node's parent-relative transform (`x`, `y`, `angle`)
      # inside a per-frame method.
      #
      # A Node2D's `@x`/`@y`/`@angle` are *relative to its parent*. Every traversal
      # resolves the absolute transform into `@abs_x`/`@abs_y`/`@abs_angle` (see
      # Node2D#resolve_origin) before the node's own hooks run, and that is what
      # drawing and per-frame logic must use — a child of an offset or rotated parent
      # lives at its absolute origin, not at the offset it declared. Reaching for the
      # raw relative value silently mislocates the node the moment it hangs under a
      # parent that is anywhere but the origin, pointing right.
      #
      # The methods are `Game::HotPath::METHODS`, the same list the allocation guards
      # use: the six lifecycle hooks plus Node2D's `draw_children`/`draw_content`.
      # Both halves of each hook pair are in it deliberately — `draw`/`update`/`control`
      # are what a Component overrides, `on_draw`/`on_update`/`on_control` are what a
      # Node2D subclass overrides, and the rule is identical for both.
      #
      # The list is shared but the `# hot-path` tag opt-in is not, because this rule is
      # not about *frequency*. A tagged helper is any per-frame method, on any class —
      # `Engine::View#offset_x` is one — and only a node has a relative transform to
      # confuse with a resolved one. Flagging outside the lifecycle would report a
      # `@x` that is nobody's parent-relative anything.
      #
      # `@z` is deliberately **not** in this list, and has no absolute counterpart.
      # It orders a node against its siblings and is never resolved into anything,
      # so there is nothing to reach for instead — see RGame::Util::Z.
      #
      # Only *reads* are flagged: assigning (`@x = …`, `@x += …`) is how a node moves
      # itself in its parent's space and stays legal.
      #
      # @example
      #   # bad — the relative transform on a render path
      #   def on_draw(renderer, _view)
      #     renderer.sprite(@sheet, @x, @y, angle: @angle)
      #   end
      #
      #   # bad — the reader is the same read
      #   def on_draw(renderer, _view)
      #     renderer.text(@label, x, y)
      #   end
      #
      #   # good — the resolved absolutes
      #   def on_draw(renderer, _view)
      #     renderer.sprite(@sheet, @abs_x, @abs_y, angle: @abs_angle)
      #   end
      class UseAbsoluteCoords < RuboCop::Cop::Base
        MSG = 'Use `%{abs}` (the resolved absolute) instead of relative `%{rel}` ' \
              'in `%{method}`: `x`/`y`/`angle` are parent-relative and only valid ' \
              'after the traversal resolves the `abs_*` transform.'

        # Both spellings of the same read: the ivar, and the attr_reader Node2D
        # defines for it. A node that draws with `x` is as wrong as one that draws
        # with `@x`, and half a rule is worse than none — the reader is the spelling
        # a Node2D subclass reaches for first.
        RELATIVE_IVARS = { :@x => :@abs_x, :@y => :@abs_y, :@angle => :@abs_angle }.freeze
        RELATIVE_READERS = { x: :abs_x, y: :abs_y, angle: :abs_angle }.freeze

        def on_def(node)
          return unless HotPath::METHODS.include?(node.method_name)

          node.each_descendant(:ivar, :send) do |read|
            rel, abs = relative_read(read)
            next unless rel

            add_offense(read, message: format(MSG, abs: abs, rel: rel, method: node.method_name))
          end
        end

        private

        # The relative name this node reads, and the absolute to use instead — or nil
        # if it reads neither.
        def relative_read(node)
          if node.ivar_type?
            name = node.children.first
            [name, RELATIVE_IVARS[name]] if RELATIVE_IVARS.key?(name)
          elsif self_read?(node)
            name = node.method_name
            [name, RELATIVE_READERS[name]] if RELATIVE_READERS.key?(name)
          end
        end

        # A bare `x` with no receiver and no arguments: a read of self's own reader.
        # `view.x` and `camera.x` have a receiver and are somebody else's coordinate,
        # so they are none of this cop's business; a local named `x` parses as an
        # `lvar` rather than a `send` and never reaches here at all.
        def self_read?(node)
          node.send_type? && node.receiver.nil? && node.arguments.empty? && !node.block_literal?
        end
      end
    end
  end
end
