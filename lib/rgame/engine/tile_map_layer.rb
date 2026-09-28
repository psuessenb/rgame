# frozen_string_literal: true

module RGame
  module Engine
    # One layer of the scene's tile map, drawn in world space, once per viewport.
    #
    #   world = scene.add_node(WorldView.new)
    #   places = TileMapLayer.mount(world)
    #   places['actors'].add_node(player)
    #   places['doors'].add_node(door)
    #
    # A node per layer that draws, and the layers Tiled lists are the layers you
    # get. The scene tree is then what says what covers what: everything mounted
    # before a place draws under what the scene puts in it, and everything after
    # draws over it. An object layer is a place: its node holds the nodes its
    # objects build, and whatever a scene adds to it.
    #
    # It belongs **inside a WorldView**, which is the whole point of it existing
    # separately from Components::TileWorld. The map is world content: it
    # scrolls under a camera and every player sees their own part of it, so it
    # has to be drawn where the rest of the world is drawn rather than once for
    # the frame.
    #
    # It carries no state. The map id and the animation clock come from the
    # scene's TileWorld system, and the region worth drawing comes from the view.
    #
    # ## Why a node per layer
    #
    # Draw order is tree order (see RGame::Util::Z), so a node's drawing is
    # contiguous, and "between two layers" means between two nodes. A designer
    # orders the layers in Tiled and sees the result there. Content goes in any
    # object layer, wherever the designer put it, the actors included: a layer
    # covers them when Tiled lists it after theirs.
    class TileMapLayer < Node2D
      # The places `mount` made for what a scene adds itself: each object
      # layer's node.
      class Places
        def initialize(world, object_layers)
          @world = world
          @object_layers = object_layers.freeze
          freeze
        end

        # The node of the object layer that `place` names, a name or a
        # `'Group/layer'` path, as `TileMap#layer_index` takes them.
        #
        # Raises `KeyError` listing the object layers for a name that names no
        # one layer, and `ArgumentError` for a tile or image layer's name and for
        # a key that is not a String.
        def [](place)
          unless place.is_a?(String)
            raise ArgumentError, "a place is the name or 'Group/layer' path of an object layer, as a String; " \
                                 "got #{place.inspect}"
          end

          index = layer_index(place)
          @object_layers.fetch(index) do
            raise ArgumentError, "layer '#{place}' is a #{@world.layer(index).kind} layer, and only an object " \
                                 "layer holds nodes (the object layers are #{object_layer_paths})"
          end
        end

        private

        def layer_index(place)
          @world.layer_index(place)
        rescue KeyError
          raise KeyError.new("'#{place}' names no one layer of this map; name an object layer, or give its " \
                             "'Group/layer' path (the object layers are #{object_layer_paths})",
                             receiver: self, key: place)
        end

        def object_layer_paths
          return 'none' if @object_layers.empty?

          @object_layers.keys.map { @world.layer(it).path.join('/') }.join(', ')
        end
      end

      # Mounts one node per layer of the scene's map under `parent`, and returns
      # the `Places` a scene adds to. Nothing here picks a z by hand, and
      # neither does the caller.
      #
      # **An object layer becomes a node in its place**, and each of its objects
      # a node under it, built by MapBuilder in the layer's order. Their classes
      # resolve in the class of the node the scene's TileWorld is attached to.
      # The layer's node is y-sorted when the layer draws *Top Down* in Tiled,
      # at the layer's opacity, or 0 when it is hidden.
      #
      # **The actors go in an object layer too**, whichever the scene names,
      # and a layer Tiled lists after it covers them. `mount` makes no node of
      # its own: a node for each layer, at the `z` of its index, and nothing
      # else.
      #
      # `parent` must be inside a WorldView, like the nodes themselves. A
      # second mount over the same TileWorld raises, since it would build every
      # object twice.
      def self.mount(parent)
        world = parent.system!(Components::TileWorld)
        world.record_mount
        builder = MapBuilder.new(tilemap_id: world.tilemap_id, scope: world.node.class)
        objects = world.objects.group_by(&:layer)
        object_layers = {}

        world.layer_count.times do |index|
          layer = world.layer(index)
          if layer.kind == :object
            object_layers[index] = parent.add_node(object_layer(layer, objects.fetch(index, NONE), builder, index))
          else
            parent.add_node(new(layer: index, z: index))
          end
        end
        Places.new(world, object_layers)
      end

      NONE = [].freeze
      private_constant :NONE

      def self.object_layer(layer, objects, builder, z)
        node = Node2D.new(z:, y_sort: layer.y_sort?)
        node.opacity = layer.visible? ? layer.opacity : 0
        objects.each do |object|
          built = builder.build(object)
          node.add_node(built) if built
        end
        node
      end
      private_class_method :object_layer

      def initialize(layer:, **)
        super(**)
        @rgame_layer = layer
      end

      def _enter_tree = @rgame_world = system(Components::TileWorld)

      # The view supplies the cull rect: which part of the world this viewport
      # can see. The map draws in world coordinates and the WorldView's
      # translate puts it on screen, so nothing here does camera arithmetic —
      # which is exactly what lets the same map serve every viewport.
      #
      # A screen-space view has no camera and nothing to cull against, so
      # there is nothing sensible to draw; that is a misplaced layer rather than
      # a state to handle, and it says so.
      def _draw(renderer, view)
        camera = view.camera
        raise 'TileMapLayer must be inside a WorldView — this view has no camera' if camera.nil?

        renderer.tilemap(@rgame_world.tilemap_id, @rgame_layer, camera.x, camera.y,
                         view.width, view.height, elapsed: @rgame_world.elapsed)
      end
    end
  end
end
