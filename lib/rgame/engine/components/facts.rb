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
      # A `StateMachine` built with a `name:` registers here, so `to_h` saves
      # every flag and every named quest and conversation, and `restore` puts
      # them all back. A game adds a quest by building it, never by adding a
      # line to its save. Order does not matter: a machine built after
      # `restore` resumes from its entry. Neither does building one again: a
      # scene entered a second time builds its quest anew, and the new machine
      # takes over where the old one was.
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
          @machines = {}
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

        # Every fact and every named machine, frozen, in the shape
        # `Util::SaveFile#write` takes. A machine a restore brought back but no
        # live machine has claimed is saved as it was.
        def to_h
          machines = @entries.merge(@machines.transform_values(&:to_h))
          { values: @values.dup.freeze, machines: machines.freeze }.freeze
        end

        # Replaces every fact and every named machine with those in `saved`,
        # which is what `to_h` returned or `Util::SaveFile#read` read back; nil
        # clears everything. A live machine with no entry goes back to its start
        # state, and an entry no machine claims is kept for one built later.
        #
        # Checks everything first, so a value `[]=` would refuse, or an entry
        # naming a state its machine's graph lacks, raises and changes nothing.
        # Runs no effect and emits no `on_changed`. Calls the watchers of each key
        # whose value differs, then every named machine's, once all are restored.
        def restore(saved)
          values, entries = _parse(saved)
          placed = @machines.to_h { |name, machine| [machine, machine.parse_saved(entries[name])] }
          previous = @values
          @values = values
          @entries = entries
          placed.each { |machine, parsed| machine.place(parsed) }
          (previous.keys | values.keys).each do |key|
            _notify(key) unless previous[key].eql?(values[key])
          end
          placed.each_key(&:notify_watchers)
          self
        end

        # Adopts a machine built with a `name:`, yielding the entry it resumes
        # from: that of the machine it replaces, or the saved one. The machine
        # replaced is retired and refuses to move from then on.
        #
        # @api private
        def register(machine)
          current = @machines[machine.name]
          yield current ? current.to_h : @entries[machine.name]
          current&.retire
          @machines[machine.name] = machine
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
