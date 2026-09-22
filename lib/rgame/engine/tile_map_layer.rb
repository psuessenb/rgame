# frozen_string_literal: true

module RGame
  module Engine
    # One layer of the scene's tile map, drawn in world space, once per viewport.
    #
    #   world = scene.add_node(WorldView.new)
    #   slots = TileMapLayer.mount(world)
    #   slots[:actors].add_node(player)
    #
    # A node per layer that draws, and the layers Tiled lists are the layers you
    # get. The scene tree is then what says what covers what: everything mounted
    # before a gap draws under what the scene puts in it, everything after draws
    # over it, and each gap `mount` leaves is a node the scene hangs things on.
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
    # ## Why a node per layer, rather than two passes
    #
    # There used to be one of these, drawing a "below" band and an "above" band
    # in one go and relying on a global z to slot the actors between them. Draw
    # order is tree order now (see RGame::Util::Z), so a node's drawing is
    # contiguous and "between them" has to mean "between two nodes".
    #
    # That turned out to be the better shape anyway. A designer already orders
    # layers in Tiled and can see the result there; content can go between *any*
    # two of them rather than at one flagged boundary; and the `above` property
    # stops being something to remember on every layer — it is read once, by
    # `mount`, to decide where the gap goes.
    class TileMapLayer < Node2D
      # The gaps `mount` left between the layers, by the names the scene gave
      # them. Each is an empty node for the scene to add to.
      class Slots
        def initialize(gaps)
          @gaps = gaps.freeze
          freeze
        end

        # The node in the gap called `name`. Raises `KeyError` naming the gaps
        # there are when there is none of that name.
        def [](name)
          @gaps.fetch(name) do
            raise KeyError.new("no gap #{name.inspect} was mounted (the gaps are #{names.map(&:inspect).join(', ')})",
                               receiver: self, key: name)
          end
        end

        # The gaps' names, in the order the scene declared them.
        def names = @gaps.keys
      end

      # Mounts one node per layer of the scene's map under `parent`, leaves an
      # empty node in each gap `gaps` names, and returns them as `Slots`.
      # Nothing here picks a z by hand, and neither does the caller.
      #
      # Each gap's value names the layer that covers it: an index, or a name or
      # `'Group/layer'` path as `TileMap#layer_index` takes them. `nil` means
      # the first layer marked `above` in Tiled, and `layer_count` means over
      # every layer. With no `gaps:`, the one gap is `:actors`, under the first
      # layer marked `above`, so a map that already marks its canopies needs
      # nothing said. Gaps under the same layer draw in the order declared.
      #
      # An object layer gets no node, since it has nothing to draw. `parent`
      # must be inside a WorldView, like the nodes themselves.
      def self.mount(parent, gaps: { actors: nil })
        world = parent.system(Components::TileWorld)
        under = gaps.transform_values { covering_layer(world, it) }
        z = -1
        nodes = {}

        (world.layer_count + 1).times do |index|
          under.each { |name, layer| nodes[name] = parent.add_node(Node2D.new(z: z += 1)) if layer == index }
          next if index == world.layer_count || world.layer(index).kind == :object

          parent.add_node(new(layer: index, z: z += 1))
        end
        Slots.new(gaps.keys.to_h { [it, nodes.fetch(it)] })
      end

      def self.covering_layer(world, layer)
        case layer
        when nil then world.first_above_layer
        when String then world.layer_index(layer)
        when 0..world.layer_count then layer
        else raise ArgumentError, "a gap goes under a layer index from 0 to #{world.layer_count}, a layer's " \
                                  "name or path, or nil for the first layer marked above; got #{layer.inspect}"
        end
      end
      private_class_method :covering_layer

      def initialize(layer:, **)
        super(**)
        @layer = layer
      end

      def _enter_tree = @world = system(Components::TileWorld)

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

        renderer.tilemap(@world.tilemap_id, @layer, camera.x, camera.y,
                         view.width, view.height, elapsed: @world.elapsed)
      end
    end
  end
end
