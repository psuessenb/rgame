# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Its node's own facts: a record of named fields, each with a default,
      # kept in the root's FactsDatabase so it outlives the room the node stands
      # in. A chest opened once stays open when its room is built again, and a
      # save keeps it with every other fact.
      #
      #   class Crate < Engine::Node2D
      #     def initialize(x:, y:, **)
      #       super
      #       @facts = add_component(Components::Facts.new(x:, y:, way: 'still'))
      #     end
      #
      #     def _enter_tree
      #       self.x = @facts[:x]
      #       @way = @facts[:way].to_sym
      #     end
      #
      #     def push(way) = @facts[:way] = way.name
      #   end
      #
      # **Each keyword but `key:` names a field**, and its value is the field's
      # default, which must be a value the FactsDatabase holds. `facts[field]`
      # is the field's value, or its default while it was never set.
      # `facts[field] = value` writes it into the node's record. Neither
      # allocates, so a node may write every frame. A field the node did not
      # name raises KeyError, listing the fields it did.
      #
      # **The key** is `key:` when the node passes one, as a node built in code
      # does. Otherwise it is `:"<tilemap id>#<object id>"`, made from the
      # node's `map_object_id` and the scene's TileWorld, so every object of
      # every map has a record of its own. The key is made once, at the node's
      # first `_attach`, and kept: a node moved into another room keeps it.
      #
      # So `key`, `[]` and `[]=` raise until the node has entered a tree: read
      # the fields in `_enter_tree` or later. `_attach` raises when the node
      # has neither a `key:` nor a `map_object_id`.
      class Facts < Engine::Component
        def initialize(key: nil, **fields)
          super()
          if fields.empty?
            raise ArgumentError, 'Components::Facts keeps named fields: pass each with its default, ' \
                                 "such as Facts.new(state: 'closed')"
          end
          fields.each { |field, default| FactsDatabase.check_value(default) { "the default of #{field}" } }
          @rgame_defaults = fields.freeze
          @rgame_given = given_key(key)
        end

        def _attach
          @rgame_database = node.system!(FactsDatabase)
          @rgame_key ||= derived_key
        end

        # The Symbol the record is kept under in the FactsDatabase.
        def key
          attached
          @rgame_key
        end

        def [](field)
          database = attached
          known(field)
          database.key?(@rgame_key, field) ? database[@rgame_key, field] : @rgame_defaults[field]
        end

        def []=(field, value)
          database = attached
          known(field)
          database[@rgame_key, field] = value
        end

        private

        def given_key(key)
          return key if key.nil? || key.is_a?(Symbol)

          raise TypeError, "Components::Facts' key: is a Symbol, got #{key.inspect} (#{key.class})"
        end

        def derived_key
          @rgame_given || map_key or
            raise ArgumentError, "#{node.class} has a Components::Facts with no key: pass key: to it, " \
                                 'or build the node from a map, whose object id makes one'
        end

        def map_key
          id = node.map_object_id or return

          :"#{node.system!(TileWorld).tilemap_id}##{id}"
        end

        def known(field)
          return if @rgame_defaults.key?(field)

          raise KeyError, "#{node.class}'s Components::Facts has no field #{field.inspect} " \
                          "(fields: #{@rgame_defaults.keys.join(', ')})"
        end

        def attached
          @rgame_database or raise "Components::Facts keeps its record in the root's FactsDatabase, found as its " \
                                   'node enters the tree. Read or write it from _enter_tree on.'
        end
      end
    end
  end
end
