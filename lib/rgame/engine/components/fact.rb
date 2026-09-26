# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # One value of its node's, kept in the root's FactsDatabase, so it outlives the
      # room the node stands in. A chest opened once stays open when its room is
      # built again, and a save keeps it with every other fact.
      #
      #   class Chest < Engine::Node2D
      #     def initialize(**)
      #       super
      #       @kept = add_component(Components::Fact.new(default: 'closed'))
      #     end
      #
      #     def _enter_tree = @state = @kept.value.to_sym
      #     def open = @kept.value = 'open'
      #   end
      #
      # **The key** is `key:` when the node passes one, as a node built in code
      # does. Otherwise it is `:"<tilemap id>#<object id>"`, made from the
      # node's `map_object_id` and the scene's TileWorld, so every object of
      # every map has a key of its own. A node keeping several values adds one
      # Fact for each, with a `part:`, which joins the key after a dot:
      # `:"map/town.tmx#7.x"`, or `:"crate.x"` for `key: :crate`. Each takes a
      # slot of its own, as a second component of one class does:
      #
      #   @x = add_component(Components::Fact.new(part: :x, default: x), as: :x)
      #   @y = add_component(Components::Fact.new(part: :y, default: y), as: :y)
      #
      # The key is made once, at the node's first `_attach`, and kept: a node
      # moved into another room keeps its key. So `key`, `value` and `value=`
      # raise until the node has entered a tree. Read the value in `_enter_tree`
      # or later. `_attach` raises when the node has neither a `key:` nor a
      # `map_object_id`.
      #
      # `value` is the fact, or `default` for a fact never set. `value=` writes
      # it through `FactsDatabase#[]=`, which checks it, emits `on_changed` and calls the
      # watchers. A `default` a fact cannot hold, and a `key:` or `part:` that
      # is not a Symbol, raise TypeError as the component is built.
      class Fact < Engine::Component
        def initialize(default: nil, key: nil, part: nil)
          super()
          @rgame_default = FactsDatabase.check_value(default) { 'a Fact default' }
          @rgame_given = symbol(key, :key)
          @rgame_part = symbol(part, :part)
        end

        def _attach
          @rgame_facts = node.system!(FactsDatabase)
          @rgame_key ||= derived_key
        end

        # The Symbol the value is kept under in the FactsDatabase.
        def key
          attached
          @rgame_key
        end

        def value
          facts = attached
          facts.key?(@rgame_key) ? facts[@rgame_key] : @rgame_default
        end

        def value=(value)
          attached[@rgame_key] = value
        end

        private

        def symbol(value, name)
          return value if value.nil? || value.is_a?(Symbol)

          raise TypeError, "a Fact's #{name}: is a Symbol, got #{value.inspect} (#{value.class})"
        end

        def derived_key
          base = @rgame_given || map_key
          unless base
            raise ArgumentError, "#{node.class} has a Components::Fact with no key: pass key: to it, " \
                                 'or build the node from a map, whose object id makes one'
          end

          @rgame_part ? :"#{base}.#{@rgame_part}" : base
        end

        def map_key
          id = node.map_object_id or return

          :"#{node.system!(TileWorld).tilemap_id}##{id}"
        end

        def attached
          @rgame_facts or raise "Components::Fact keeps its value in the root's FactsDatabase, found as its node " \
                                'enters the tree. Read or write it from _enter_tree on.'
        end
      end
    end
  end
end
