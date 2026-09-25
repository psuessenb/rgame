# frozen_string_literal: true

module RGame
  module Engine
    # The fall of one node, run from beside it: it suspends the node, shrinks it
    # through Node2D#scale over its Components::Footing's `fall` seconds, then
    # resumes it on its Components::Respawn point, or frees a node with none.
    #
    # A Footing keeps one for its life and adds it to the falling node's parent for
    # each fall, because a suspended node stops its own components. Beside the node,
    # it pauses when the world around the node pauses, and a fall allocates nothing.
    # It frees itself from the parent when the fall ends.
    #
    # @api private
    class Fall < Node2D
      # `owner` is the Footing that lends it. Not `@footing`: that ivar is Node2D's.
      def initialize(owner)
        super()
        @owner = owner
        @shrink = Engine::Tween.new(owner.fall, from: 1.0, to: 0.0, ease: :in)
        @falling_node = nil
      end

      # Suspends `node` and joins its parent, to shrink it from its own next update.
      def start(node)
        @falling_node = node
        @shrink.duration = @owner.fall
        @shrink.restart
        node.suspend
        node.parent.add_node(self)
      end

      # Ends the fall where it is: the node is unscaled and resumed, and nothing
      # else happens to it.
      def stop
        node = end_fall
        node&.scale = 1
      end

      # hot-path
      def _update(dt)
        return unless @falling_node

        @falling_node.scale = @shrink.update(dt).value
        land if @shrink.done?
      end

      private

      def land
        node = end_fall
        node.scale = 1
        respawn = node.get_component(Components::Respawn)
        respawn ? respawn.respawn : node.queue_free
      end

      def end_fall
        node = @falling_node
        return unless node

        @falling_node = nil
        node.resume
        queue_free
        @owner.fall_ended
        node
      end
    end
  end
end
