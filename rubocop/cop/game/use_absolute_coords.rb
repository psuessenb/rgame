# frozen_string_literal: true

module RuboCop
  module Cop
    module Game
      # Disallow reading the relative `@x` / `@y` / `@z` inside `draw`, `update` and
      # `contains?`.
      #
      # Since the scene-graph refactor, a Node's `@x`/`@y`/`@z` are *relative to its
      # parent*. The traversal (`trigger_update`/`trigger_draw`) resolves the absolute
      # position into `@abs_x`/`@abs_y`/`@abs_z` before `update`/`draw` run, and that
      # is what hit-testing and rendering must use — the pointer is in absolute
      # coordinates and a child of an offset parent draws at its absolute origin.
      # Reaching for the raw relative `@x` in these methods silently mislocates the
      # widget the moment it lives under any non-zero origin.
      #
      # Only *reads* are flagged: assigning (`@x = …`, `@x += …`) is how a node moves
      # itself in its parent's space and stays legal.
      #
      # @example
      #   # bad — relative coords in a render/hit-test path
      #   def draw(renderer)
      #     renderer.nine_slice(texture, @x, @y, @width, @height, z: @z)
      #   end
      #
      #   def contains?(px, py)
      #     px >= @x && px < @x + @width
      #   end
      #
      #   # good — the resolved absolutes
      #   def draw(renderer)
      #     renderer.nine_slice(texture, @abs_x, @abs_y, @width, @height, z: @abs_z)
      #   end
      #
      #   def contains?(px, py)
      #     px >= @abs_x && px < @abs_x + @width
      #   end
      class UseAbsoluteCoords < RuboCop::Cop::Base
        MSG = 'Use `%{abs}` (the resolved absolute) instead of relative `%{rel}` ' \
              'in `%{method}`: `@x`/`@y`/`@z` are parent-relative and only valid ' \
              'after the traversal resolves `@abs_*`.'

        METHODS = %i[draw update contains?].freeze
        ABSOLUTE = { :@x => :@abs_x, :@y => :@abs_y, :@z => :@abs_z }.freeze

        def on_def(node)
          return unless METHODS.include?(node.method_name)

          node.each_descendant(:ivar) do |ivar|
            name = ivar.children.first
            next unless ABSOLUTE.key?(name)

            add_offense(
              ivar,
              message: format(MSG, abs: ABSOLUTE.fetch(name), rel: name, method: node.method_name)
            )
          end
        end
      end
    end
  end
end
