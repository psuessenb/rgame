# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A store for flags that belong to no object — "met the smith", "the bridge
      # is down" — and the one entry a game writes to its save.
      #
      #   root.add_component(Engine::Components::Facts.new)
      #
      #   facts = node.system(Engine::Components::Facts)
      #   facts[:met_smith] = true
      #   facts[:wolves] = facts.fetch(:wolves, 0) + 1
      #
      #   save.write(world: facts.to_h)
      #   facts.restore(save.read[:world])
      #
      # A system on the root, found with `node.system` like `Players`, so every
      # node reaches the same store without being handed it.
      #
      # It takes only what survives a save. Keys are Symbols, and values are nil,
      # true, false, an Integer, a Float or a String; anything else raises
      # `TypeError`. A Symbol value is refused because JSON brings it back a
      # String, and a comparison against it would fail after every load.
      #
      # Two ways to listen, for two jobs. `on_changed` reports a change made in
      # play, so a listener may act on it, and a restore never fires it. `watch`
      # keeps something in step with one fact: it hears the value at once, then
      # every value that differs, restores included.
      class Facts < Engine::Component
        signal :on_changed, Signal.define(:key, :value)

        VALUE_TYPES = [NilClass, TrueClass, FalseClass, Integer, Float, String].freeze
        private_constant :VALUE_TYPES

        def initialize
          super
          @values = {}
          @entries = {}
          @watchers = {}
        end

        # The value of `key`, or nil for a key never set.
        def [](key) = @values[_key(key)]

        # Sets `key`, and emits `on_changed` and calls its watchers when the value
        # differs from the one held.
        def []=(key, value)
          _key(key)
          _value(key, value)
          previous = @values[key]
          @values[key] = value.is_a?(String) ? -value : value
          _changed(key, previous)
        end

        # As `Hash#fetch`: a default, a block, or `KeyError` for a key never set.
        def fetch(key, ...) = @values.fetch(_key(key), ...)

        def key?(key) = @values.key?(_key(key))

        # Removes `key` and returns its value. Reads nil afterwards, so it emits
        # and calls watchers when the value was not already nil.
        def delete(key)
          previous = @values.delete(_key(key))
          _changed(key, previous)
          previous
        end

        # Calls the block with the value of `key` now, then with every value that
        # differs, restores included. Returns a handle for `unwatch`.
        def watch(key, &block)
          (@watchers[_key(key)] ||= []) << block
          yield @values[key]
          block
        end

        # Stops calling the block `watch` returned.
        def unwatch(handle)
          @watchers.each_value { it.delete(handle) }
          nil
        end

        # Every fact and every saved machine, frozen, in the shape
        # `Util::SaveFile#write` takes.
        def to_h = { values: @values.dup.freeze, machines: @entries.dup.freeze }.freeze

        # Replaces every fact with those in `saved`, which is what `to_h` returned
        # or `Util::SaveFile#read` read back; nil clears everything. Checks every
        # value first, so a value `[]=` would refuse raises and changes nothing.
        # Emits no `on_changed`, and calls the watchers of each key whose value
        # differs.
        def restore(saved)
          values, entries = _parse(saved)
          previous = @values
          @values = values
          @entries = entries
          (previous.keys | values.keys).each do |key|
            _notify(key) unless previous[key].eql?(values[key])
          end
          self
        end

        private

        def _key(key)
          return key if key.is_a?(Symbol)

          raise TypeError, "a fact's key is a Symbol, got #{key.inspect} (#{key.class})"
        end

        def _value(key, value)
          return if VALUE_TYPES.any? { value.is_a?(it) }

          if value.is_a?(Symbol)
            raise TypeError, "facts[#{key.inspect}] cannot hold the Symbol #{value.inspect}: " \
                             "a save brings it back as the String #{value.to_s.inspect}, so store that instead"
          end

          raise TypeError, "facts[#{key.inspect}] holds nil, true, false, an Integer, a Float or a String, " \
                           "got a #{value.class}"
        end

        def _parse(saved)
          return [{}, {}] if saved.nil?
          raise TypeError, "facts restore from a Hash, got #{saved.class}" unless saved.is_a?(Hash)

          values = saved.fetch(:values, {}).to_h do |key, value|
            _value(_key(key), value)
            [key, value.is_a?(String) ? -value : value]
          end
          [values, saved.fetch(:machines, {}).to_h { |name, entry| [_key(name), entry] }]
        end

        def _changed(key, previous)
          value = @values[key]
          return if previous.eql?(value)

          on_changed_signal.emit(key:, value:)
          _notify(key)
        end

        def _notify(key)
          @watchers[key]&.each { it.call(@values[key]) }
        end
      end
    end
  end
end
