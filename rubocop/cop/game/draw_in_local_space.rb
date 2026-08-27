# frozen_string_literal: true

module RuboCop
  module Cop
    module Game
      # A node's draw methods must not read the node's own position — in either
      # space, because both are already applied by the time they run.
      #
      # `Node2D#draw` pushes the node's transform onto the renderer and runs
      # everything below it inside that, so within `on_draw` the origin *is* the
      # node, turned the way the node is turned. Drawing is done at (0, 0), or at
      # an offset from it that means something to the node itself.
      #
      # Both spellings of "where am I" are therefore wrong there, and differ only
      # in how far off they put the result:
      #
      # - `world_x` is where the node sits on the map, which every ancestor's
      #   transform — the camera's included — has already contributed to. Passing
      #   it applies the whole chain twice.
      # - `x` is the node's offset inside its parent, which its own transform has
      #   already applied. Passing it offsets by that much a second time.
      #
      # Both are silent: they draw, they just draw in the wrong place, and only
      # once something is nested under an offset or rotated parent — which is
      # exactly the case a spec at the origin cannot see.
      #
      # A **component** drawing for its node is on this path too, and asks the
      # node by name: `node.world_x` for a cull test is a different object's
      # coordinate and is not flagged. Only a bare, receiverless read of the
      # node's own transform is.
      #
      # `width` and `height` are not positions and are ordinary here — a node
      # drawing its own box says `renderer.rect(0, 0, width, height)`.
      #
      # @example
      #   # bad — the traversal has already placed the renderer on this node
      #   def on_draw(renderer, _view)
      #     renderer.rect(world_x, world_y, width, height)
      #   end
      #
      #   # bad — same mistake, a smaller distance
      #   def on_draw(renderer, _view)
      #     renderer.rect(x, y, width, height)
      #   end
      #
      #   # good — its own origin
      #   def on_draw(renderer, _view)
      #     renderer.rect(0, 0, width, height)
      #   end
      #
      #   # good — a component culling against the camera, in world space, by name
      #   def draw(renderer, view)
      #     return if culled?(view, node.world_x, node.world_y, node.width, node.height)
      #
      #     renderer.image(@id, 0, 0)
      #   end
      class DrawInLocalSpace < RuboCop::Cop::Base
        MSG = 'Draw in local space: `%{name}` is already applied by the time ' \
              '`%{method}` runs, so passing it places this %{distance} a second ' \
              'time. Draw at your own origin (0, 0), or an offset from it.'

        # The draw path, and only it. `update` is deliberately not policed: there
        # both spellings are legitimate and the cop could not tell them apart — a
        # node moving itself in its parent's frame wants `x`, and one measuring a
        # distance to something else wants `world_x`.
        METHODS = %i[draw on_draw draw_content draw_children].freeze

        # Its own transform, in both spaces and both spellings.
        RELATIVE = %i[x y angle].freeze
        WORLD = %i[world_x world_y world_angle].freeze
        IVARS = { :@rel_x => :x, :@rel_y => :y, :@rel_angle => :angle,
                  :@world_x => :world_x, :@world_y => :world_y,
                  :@world_angle => :world_angle }.freeze

        def on_def(node)
          return unless METHODS.include?(node.method_name)

          node.each_descendant(:ivar, :send) do |read|
            name = own_transform_read(read)
            next unless name

            add_offense(read, message: format(MSG, name: name, method: node.method_name,
                                                   distance: distance_for(name)))
          end
        end

        private

        # The transform name this reads, or nil if it reads none. A bare `x` with
        # no receiver and no arguments is the node's own; `node.world_x` and
        # `view.x` have a receiver and belong to somebody else, and a local named
        # `x` parses as an `lvar` and never arrives here at all.
        def own_transform_read(node)
          if node.ivar_type?
            IVARS[node.children.first]
          elsif self_read?(node)
            name = node.method_name
            name if RELATIVE.include?(name) || WORLD.include?(name)
          end
        end

        def self_read?(node)
          node.send_type? && node.receiver.nil? && node.arguments.empty? && !node.block_literal?
        end

        def distance_for(name)
          WORLD.include?(name) ? 'on the map' : 'inside its parent'
        end
      end
    end
  end
end
