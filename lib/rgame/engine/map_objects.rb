# frozen_string_literal: true

module RGame
  module Engine
    # Builds nodes from a map's objects, one block per class the designer gave an
    # object in Tiled.
    #
    #   objects = RGame::Engine::MapObjects.new
    #   objects.define('chest') { |o| Chest.new(x: o.x, y: o.y, contents: o.properties.fetch('contents')) }
    #   objects.spawn_into(slots[:actors], map.objects)   # => the chests it added
    #
    # **An object of a class nobody defined builds nothing.** A map carries objects a
    # scene has no use for: spawn points another scene reads, notes for the designer,
    # shapes another system reads. So `build` answers `nil` for them rather than
    # raising.
    #
    # **Defining a class twice raises.** A second block that quietly replaced the first
    # would build the wrong node with no error, from a line far from either.
    #
    # **The block places the node.** A MapObject's `(x, y)` is its top-left corner,
    # and a node's origin is wherever its class puts it, so only the block knows how
    # the two relate. The registry passes the record through and moves nothing.
    #
    # Nothing calls it on its own. A scene that wants a map's objects as nodes
    # writes the `spawn_into` line, where it can see which parent they join.
    class MapObjects
      def initialize
        @builders = {}
      end

      # Registers the block that builds a node from an object of `class_name`, the
      # Class field in Tiled's object properties. Returns the registry. Raises
      # ArgumentError for a class already defined, a name that is not a String, or
      # a missing block.
      def define(class_name, &build)
        unless class_name.is_a?(String)
          raise ArgumentError, "#{class_name.inspect} is not a String, and a Tiled class always is"
        end
        raise ArgumentError, "define('#{class_name}') needs a block that builds the node" unless build
        raise ArgumentError, "'#{class_name}' is already defined" if @builders.key?(class_name)

        @builders[class_name] = build
        self
      end

      # What the block for `object.class_name` returns for `object`, or `nil` when no
      # block was defined for that class.
      def build(object)
        builder = @builders[object.class_name] or return nil

        builder.call(object)
      end

      # Builds each of `objects` in turn and adds every node that comes back under
      # `parent`, in the objects' order. Returns the nodes added. A hidden object is
      # built too: whether it shows is the block's to decide from `visible?`.
      def spawn_into(parent, objects)
        objects.filter_map do |object|
          node = build(object)
          parent.add_node(node) if node
        end
      end
    end
  end
end
