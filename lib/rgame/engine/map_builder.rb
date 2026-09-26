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
    # **The node stands at the bottom centre of the object's box**, turned with
    # it. A point object's node stands on its point, and a polygon's or
    # polyline's on its own `(x, y)`. `angle` is the object's rotation in
    # radians, and `width` and `height` are its size.
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
      UNBOXED = %i[point polygon polyline].freeze
      ROUTED = %i[polygon polyline].freeze
      NAMED = %i[key keyreq].freeze
      private_constant :BUILDS, :UNBOXED, :ROUTED, :NAMED

      # `tilemap_id` is the map's asset key, which each refusal names. `scope`
      # is the class the map's class names resolve in.
      def initialize(tilemap_id:, scope:)
        @tilemap_id = tilemap_id
        @scope = scope
        @nesting = nesting_of(scope).freeze
      end

      # The node `object` names, placed and set up, or `nil` when its class is
      # data.
      def build(object)
        return unless object.class_name.match?(BUILDS)

        node_class = resolve(object)
        parameters = node_class.instance_method(:initialize).parameters
        keywords = { **placement(object), map_object_id: object.id }
        keywords.merge!(settings(object, node_class))
        keywords.merge!(asked_for(object, node_class, parameters))
        check_required(object, node_class, keywords, parameters)
        node_class.new(**keywords)
      end

      private

      def nesting_of(scope)
        names = scope.name&.split('::') or return [scope]

        names.size.downto(1).map { Object.const_get(names.first(it).join('::')) }
      end

      def resolve(object)
        name = object.class_name
        home = @nesting.find { it.const_defined?(name, false) }
        value = home ? home.const_get(name, false) : @scope.const_get(name)
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
        angle = object.rotation * Math::PI / 180.0
        { x: origin_x(object, angle), y: origin_y(object, angle), angle:, width: object.width,
          height: object.height }
      end

      def origin_x(object, angle)
        return object.x if UNBOXED.include?(object.shape)

        object.x + (object.width / 2.0 * Math.cos(angle)) - (object.height * Math.sin(angle))
      end

      def origin_y(object, angle)
        return object.y if UNBOXED.include?(object.shape)

        object.y + (object.width / 2.0 * Math.sin(angle)) + (object.height * Math.cos(angle))
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
