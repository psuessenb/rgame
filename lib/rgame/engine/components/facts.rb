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
        signal :changed, :key, :value

        VALUE_TYPES = [NilClass, TrueClass, FalseClass, Integer, Float, String].freeze
        private_constant :VALUE_TYPES

        # Returns `value` if a save brings it back as it was, and raises
        # `TypeError` otherwise: the rule every fact is held to, for anything
        # else a game saves. The block names what holds the value, for the
        # message, and runs only on a refusal.
        #
        # @api private
        def self.check_value(value)
          return value if VALUE_TYPES.any? { value.is_a?(it) }

          if value.is_a?(Symbol)
            raise TypeError, "#{yield} cannot hold the Symbol #{value.inspect}: " \
                             "a save brings it back as the String #{value.to_s.inspect}, so store that instead"
          end

          raise TypeError, "#{yield} holds nil, true, false, an Integer, a Float or a String, got a #{value.class}"
        end

        def initialize
          super
          @rgame_values = {}
          @rgame_entries = {}
          @rgame_machines = {}
          @rgame_watchers = {}
        end

        # The value of `key`, or nil for a key never set.
        def [](key) = @rgame_values[checked_key(key)]

        # Sets `key`, and emits `on_changed` and calls its watchers when the value
        # differs from the one held.
        def []=(key, value)
          checked_key(key)
          checked_value(key, value)
          previous = @rgame_values[key]
          @rgame_values[key] = value.is_a?(String) ? -value : value
          report_change(key, previous)
        end

        # As `Hash#fetch`: a default, a block, or `KeyError` for a key never set.
        def fetch(key, ...) = @rgame_values.fetch(checked_key(key), ...)

        def key?(key) = @rgame_values.key?(checked_key(key))

        # Removes `key` and returns its value. Reads nil afterwards, so it emits
        # and calls watchers when the value was not already nil.
        def delete(key)
          previous = @rgame_values.delete(checked_key(key))
          report_change(key, previous)
          previous
        end

        # Calls the block with the value of `key` now, then with every value that
        # differs, restores included. Returns a handle for `unwatch`.
        def watch(key, &block)
          (@rgame_watchers[checked_key(key)] ||= []) << block
          yield @rgame_values[key]
          block
        end

        # Stops calling the block `watch` returned.
        def unwatch(handle)
          @rgame_watchers.each_value { it.delete(handle) }
          nil
        end

        # Every fact and every named machine, frozen, in the shape
        # `Util::SaveFile#write` takes. A machine a restore brought back but no
        # live machine has claimed is saved as it was.
        def to_h
          machines = @rgame_entries.merge(@rgame_machines.transform_values(&:to_h))
          { values: @rgame_values.dup.freeze, machines: machines.freeze }.freeze
        end

        # Replaces every fact and every named machine with those in `saved`,
        # which is what `to_h` returned or `Util::SaveFile#read` read back; nil
        # clears everything. A live machine with no entry goes back to its start
        # state, and an entry no machine claims is kept for one built later.
        #
        # Checks everything first, so a value `[]=` would refuse, or an entry
        # naming a state its machine's graph lacks, raises and changes nothing.
        # Runs no effect and emits no `on_changed`. Once every fact and machine is
        # back, calls the watchers of each key whose value differs.
        def restore(saved)
          values, entries = parse(saved)
          placed = @rgame_machines.to_h { |name, machine| [machine, machine.parse_saved(entries[name])] }
          previous = @rgame_values
          @rgame_values = values
          @rgame_entries = entries
          placed.each { |machine, parsed| machine.place(parsed) }
          (previous.keys | values.keys).each do |key|
            notify_watchers(key) unless previous[key].eql?(values[key])
          end
          self
        end

        # Adopts a machine built with a `name:`, yielding the entry it resumes
        # from: that of the machine it replaces, or the saved one. The machine
        # replaced is retired and refuses to move from then on.
        #
        # @api private
        def register(machine)
          current = @rgame_machines[machine.name]
          yield current ? current.to_h : @rgame_entries[machine.name]
          current&.retire
          @rgame_machines[machine.name] = machine
        end

        private

        def checked_key(key)
          return key if key.is_a?(Symbol)

          raise TypeError, "a fact's key is a Symbol, got #{key.inspect} (#{key.class})"
        end

        def checked_value(key, value) = Facts.check_value(value) { "facts[#{key.inspect}]" }

        def parse(saved)
          return [{}, {}] if saved.nil?
          raise TypeError, "facts restore from a Hash, got #{saved.class}" unless saved.is_a?(Hash)

          values = saved.fetch(:values, {}).to_h do |key, value|
            checked_value(checked_key(key), value)
            [key, value.is_a?(String) ? -value : value]
          end
          [values, saved.fetch(:machines, {}).to_h { |name, entry| [checked_key(name), entry] }]
        end

        def report_change(key, previous)
          value = @rgame_values[key]
          return if previous.eql?(value)

          changed_signal.emit(key:, value:)
          notify_watchers(key)
        end

        def notify_watchers(key)
          @rgame_watchers[key]&.each { it.call(@rgame_values[key]) }
        end
      end
    end
  end
end
