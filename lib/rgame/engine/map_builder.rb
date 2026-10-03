# frozen_string_literal: true

module RGame
  module Engine
    # Builds the node a map's object names, as a scene would build it by hand.
    #
    #   builder = RGame::Engine::MapBuilder.new(tilemap_id: 'map/town.tmx', scope: MyGame::Town)
    #   builder.build(object)   # => a MyGame::Chest, or nil for an object whose class is data
    #
    # **A class starting with a capital letter names a Node2D class.** The name
    # resolves as Ruby resolves it inside `scope`, the class of the scene that
    # mounts the map. `Chest` is `MyGame::Town::Chest`, then
    # `MyGame::Chest`, then a constant `MyGame::Town` inherits, then
    # `::Chest`. A path such as `Town::Chest` resolves the same way. So a map
    # names no module, and one map serves two games that each define a `Door`.
    # Any other class, and none, is data and builds nothing.
    #
    # **Every tile object draws its tile.** Its node gets a
    # Components::MapTile after its class's `initialize` has run, and a tile
    # object whose class is data builds a plain Node2D to carry one. An object
    # the designer hid builds all the same, at opacity 0: it updates and
    # collides, and draws nothing, as Tiled shows it.
    #
    # **Each property sets a keyword** that MapSettings says the class takes,
    # cast to its type.
    #
    # **The builder hands the node values and keeps the object.** Every node
    # gets its object's id as `map_object_id`. A class whose `initialize` names
    # `route:` gets a polyline's or a polygon's route, as Path.from_object
    # builds it, and one that names `name:` gets the object's name, `''` when
    # the designer gave none. A class that names neither gets neither, since
    # Node2D takes neither.
    #
    # **The node stands on its object's origin**, MapObject#origin_x and
    # #origin_y: the bottom centre of the object's box, turned with it. A point
    # object's node stands on its point, and a polygon's or polyline's on its
    # own `(x, y)`. `angle` is the object's rotation in radians, and `width` and
    # `height` are its size.
    #
    # Each refusal names the tilemap id, the object and its class. A class that
    # names no constant raises NameError. A constant that is no Node2D class,
    # and a property of the wrong type, raise TypeError. A property no keyword
    # takes, a required keyword no property sets, and a required `route:` for
    # an object of another shape raise ArgumentError.
    #
    # @api private
    class MapBuilder
      BUILDS = /\A[[:upper:]]/
      ROUTED = %i[polygon polyline].freeze
      NAMED = %i[key keyreq].freeze

      # What every node gets from its object: the box and the id.
      PLACED = %i[x y angle width height map_object_id].freeze

      # What a class gets from its object when its initialize names it.
      ASKED = %i[route name].freeze
      private_constant :BUILDS, :ROUTED, :NAMED, :PLACED, :ASKED

      # What stops any map building `node_class`, in words, or `nil` when a map
      # can. A map passes only keywords: the object's box and id to every
      # class, `route:` and `name:` to a class that names them, and the
      # properties the class's tags make settable. So a class that requires an
      # argument, or a keyword no map sets, or takes no `**`, is never built.
      def self.refusal(node_class)
        parameters = node_class.instance_method(:initialize).parameters
        if (argument = parameters.find { |kind, _name| kind == :req })
          return "its initialize requires the argument #{argument.last}, and a map passes only keywords"
        end
        unless parameters.any? { |kind, _name| kind == :keyrest } ||
               PLACED.all? { |placed| parameters.any? { |kind, name| NAMED.include?(kind) && name == placed } }
          return "its initialize takes no **, and a map passes every node #{PLACED.join(', ')}"
        end

        given = [*PLACED, *ASKED, *MapSettings.of(node_class).keys]
        missing = parameters.filter_map { |kind, name| name if kind == :keyreq && !given.include?(name) }
        return if missing.empty?

        "its initialize requires #{missing.join(', ')}, which no @param tag lets a map set"
      end

      # `tilemap_id` is the map's asset key, which each refusal names. `scope`
      # is the class the map's class names resolve in.
      def initialize(tilemap_id:, scope:)
        @tilemap_id = tilemap_id
        @scope = scope
        @nesting = MapSettings.nesting(scope).freeze
      end

      # The node `object` names, placed and set up, or `nil` when its class is
      # data and it is no tile object.
      def build(object)
        node = if object.class_name.match?(BUILDS) then built(object)
               elsif object.tile then Node2D.new(**placement(object), map_object_id: object.id)
               end
        return unless node

        node.add_component(Components::MapTile.new(tile: object.tile, orientation: object.orientation)) if object.tile
        node.opacity = 0 unless object.visible?
        node
      end

      private

      def built(object)
        node_class = resolve(object)
        parameters = node_class.instance_method(:initialize).parameters
        keywords = { **placement(object), map_object_id: object.id }
        keywords.merge!(settings(object, node_class))
        keywords.merge!(asked_for(object, node_class, parameters))
        check_required(object, node_class, keywords, parameters)
        node_class.new(**keywords)
      end

      def resolve(object)
        value = MapSettings.resolve(object.class_name, @nesting)
        return value if value.is_a?(Class) && value <= Node2D

        raise TypeError, "#{where(object)} names #{value.inspect}, which is not a Node2D class. #{rule}"
      rescue NameError => e
        raise NameError, "#{where(object)} names no constant in #{@scope} (#{e.message}). #{rule}"
      end

      def rule
        'A class starting with a capital letter builds the node class of that name; ' \
          'start it with a lower-case letter to keep the object as data'
      end

      def placement(object)
        { x: object.origin_x, y: object.origin_y, angle: object.rotation * Math::PI / 180.0, width: object.width,
          height: object.height }
      end

      def settings(object, node_class)
        settable = MapSettings.of(node_class)
        keywords = {}
        object.properties.each do |name, value|
          keywords[name.to_sym] = setting(object, node_class, settable, name, value)
        end
        keywords
      end

      def asked_for(object, node_class, parameters)
        keywords = {}
        parameters.each do |kind, name|
          next unless NAMED.include?(kind)

          keywords[:name] = object.name if name == :name
          keywords[:route] = route(object, node_class, kind) if name == :route
        end
        keywords.compact
      end

      def route(object, node_class, kind)
        return Path.from_object(object) if ROUTED.include?(object.shape)
        return unless kind == :keyreq

        raise ArgumentError, "#{where(object)} is a #{object.shape}, and #{node_class}#initialize requires " \
                             'route:, which only a polyline or a polygon gives; draw the object as one of those'
      end

      def setting(object, node_class, settable, name, value)
        unless (type = settable[name.to_sym])
          raise ArgumentError, "#{where(object)} sets '#{name}', which #{node_class} does not let a map set " \
                               "(settable: #{listed(settable)}). A map sets a keyword whose @param tag above " \
                               'initialize gives a type Tiled can hold'
        end

        MapSettings.cast(type, value) do
          raise TypeError, "#{where(object)} sets '#{name}' to #{shown(value)}, and #{node_class} takes " \
                           "#{MapSettings.expected(type)} there"
        end
      end

      def check_required(object, node_class, keywords, parameters)
        missing = parameters.filter_map { |kind, name| name if kind == :keyreq && !keywords.key?(name) }
        return if missing.empty?

        unset = missing.map { "'#{it}'" }.join(', ')
        raise ArgumentError, "#{where(object)} sets no #{unset}, which #{node_class}#initialize requires " \
                             "(settable: #{listed(MapSettings.of(node_class))})"
      end

      def where(object)
        named = object.name.empty? ? '' : " '#{object.name}'"
        "object #{object.id}#{named} of class '#{object.class_name}' in #{@tilemap_id}"
      end

      def listed(settable) = settable.empty? ? 'none' : settable.keys.join(', ')

      def shown(value)
        return value.inspect unless value.is_a?(Properties)

        value.class_name ? "a value of the class '#{value.class_name}'" : 'a class value'
      end
    end
  end
end
