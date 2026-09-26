# frozen_string_literal: true

module RGame
  module Engine
    # One layer of the scene's tile map, drawn in world space, once per viewport.
    #
    #   world = scene.add_node(WorldView.new)
    #   places = TileMapLayer.mount(world)
    #   places[:actors].add_node(player)
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
    # object layer, wherever the designer put it, and the `above` property is
    # read once, by `mount`, to place the actors on a map that marks no layer
    # for them.
    class TileMapLayer < Node2D
      # The places `mount` made for what a scene adds itself: the actors', and
      # each object layer's node.
      class Places
        def initialize(world, actors, object_layers)
          @world = world
          @actors = actors
          @object_layers = object_layers.freeze
          freeze
        end

        # The node for `place`. `:actors` is where the scene's actors go: the
        # layer marked `actors`, or on a map with no mark, a node under the
        # first layer marked `above`. A String is the object layer that name or
        # `'Group/layer'` path names, as `TileMap#layer_index` takes them.
        #
        # Raises `KeyError` listing the object layers for a String that names
        # no one layer, and `ArgumentError` for a tile or image layer's name and
        # for any other key.
        def [](place)
          return @actors if place == :actors

          unless place.is_a?(String)
            raise ArgumentError, "a place is :actors, or the name or 'Group/layer' path of an object layer; " \
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
      # **The actors go in the layer marked `actors`.** On a map with no mark,
      # they go in a node of their own, under the first layer marked `above`,
      # or over every layer when none is. That node is y-sorted (see
      # Node2D#y_sort), so actors in it draw by where they stand, and
      # `y_sort: false` leaves them in the order added, for a side-view game.
      #
      # `parent` must be inside a WorldView, like the nodes themselves. A
      # second mount over the same TileWorld raises, since it would build every
      # object twice.
      def self.mount(parent, y_sort: true)
        world = parent.system!(Components::TileWorld)
        world.record_mount
        builder = MapBuilder.new(tilemap_id: world.tilemap_id, scope: world.node.class)
        objects = world.objects.group_by(&:layer)
        actors_under = world.first_above_layer unless world.actors_layer
        z = -1
        actors = nil
        object_layers = {}

        (world.layer_count + 1).times do |index|
          actors = parent.add_node(Node2D.new(z: z += 1, y_sort:)) if index == actors_under
          next if index == world.layer_count

          layer = world.layer(index)
          if layer.kind == :object
            object_layers[index] = parent.add_node(object_layer(layer, objects.fetch(index, NONE), builder, z += 1))
          else
            parent.add_node(new(layer: index, z: z += 1))
          end
        end
        Places.new(world, actors || object_layers.fetch(world.actors_layer), object_layers)
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
