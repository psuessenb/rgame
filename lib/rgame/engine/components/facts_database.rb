# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A store for flags that belong to no object — "met the smith", "the bridge
      # is down" — and the one entry a game writes to its save. A node's own
      # value, such as whether a chest is open, is kept here too, through
      # Components::Fact.
      #
      #   root.add_component(Engine::Components::FactsDatabase.new)
      #
      #   facts = node.system(Engine::Components::FactsDatabase)
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
      # true, false, an Integer, a Float, a String, or a record: a Hash whose
      # fields are Symbols and whose values follow the same rule, records
      # included. Anything else raises `TypeError`. A Symbol value is refused
      # because JSON brings it back a String, and a comparison against it would
      # fail after every load.
      #
      # **A record keeps the facts of one thing under one key**, as
      # Components::Facts keeps a node's:
      #
      #   facts[:crate, :x] = 3        # one field, written in place
      #   facts[:crate, :x]            # => 3
      #   facts[:crate]                # => { x: 3 }, a frozen copy
      #
      # Reading or writing one field allocates nothing, so a node may write its
      # record every frame. `facts[:crate]` answers a frozen copy of the whole
      # record, and a Hash written whole is copied in, so neither side can change
      # the other's. A field write on a key that holds no record raises
      # `TypeError`. Deleting a record's last field deletes the key.
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
      # play, so a listener may act on it, and a restore never fires it. It
      # hears the key, the new value and `nil`, or for a field write the key, the
      # field's new value and the field. `watch` keeps something in step with
      # one key: it hears the value at once, then every value that differs, a
      # field of its record and restores included.
      class FactsDatabase < Engine::Component
        signal :changed, :key, :value, :field

        VALUE_TYPES = [NilClass, TrueClass, FalseClass, Integer, Float, String].freeze
        WHOLE = Object.new.freeze
        private_constant :VALUE_TYPES, :WHOLE

        # Returns `value` if a save brings it back as it was, and raises
        # `TypeError` otherwise: the rule every fact is held to, for anything
        # else a game saves. The block names what holds the value, for the
        # message, and runs only on a refusal.
        #
        # @api private
        def self.check_value(value)
          return value if VALUE_TYPES.any? { value.is_a?(it) }
          return check_record(value, yield) if value.is_a?(Hash)

          if value.is_a?(Symbol)
            raise TypeError, "#{yield} cannot hold the Symbol #{value.inspect}: " \
                             "a save brings it back as the String #{value.to_s.inspect}, so store that instead"
          end

          raise TypeError, "#{yield} holds nil, true, false, an Integer, a Float, a String or a record of " \
                           "those, got a #{value.class}"
        end

        def self.check_record(record, where)
          record.each do |field, value|
            unless field.is_a?(Symbol)
              raise TypeError, "#{where} is a record, whose fields are Symbols, got #{field.inspect} " \
                               "(#{field.class}): a save brings every name back as a Symbol"
            end

            check_value(value) { "#{where}[#{field.inspect}]" }
          end
          record
        end
        private_class_method :check_record

        def initialize
          super
          @rgame_values = {}
          @rgame_entries = {}
          @rgame_machines = {}
          @rgame_watchers = {}
        end

        # The value of `key`, or nil for a key never set. With a `field`, that
        # field of the record `key` holds, or nil for either never set.
        def [](key, field = nil)
          value = @rgame_values[checked_key(key)]
          return shown(value) if field.nil?

          record = record_of(key, value) or return
          record[checked_field(field)]
        end

        # `facts[key] = value` sets `key`, and `facts[key, field] = value` one
        # field of its record, making the record when the key has none. Either
        # emits `on_changed` and calls the key's watchers when the value differs
        # from the one held.
        def []=(key, field, value = WHOLE)
          WHOLE.equal?(value) ? write(key, field) : write_field(key, field, value)
        end

        # As `Hash#fetch`: a default, a block, or `KeyError` for a key never set.
        def fetch(key, ...) = shown(@rgame_values.fetch(checked_key(key), ...))

        # Whether `key` was set, or with a `field`, that field of its record.
        def key?(key, field = nil)
          return @rgame_values.key?(checked_key(key)) if field.nil?

          record = record_of(key, @rgame_values[checked_key(key)]) or return false
          record.key?(checked_field(field))
        end

        # Removes `key`, or one `field` of its record, and returns its value.
        # Reads nil afterwards, so it emits and calls watchers when the value was
        # not already nil.
        def delete(key, field = nil)
          return delete_field(key, field) unless field.nil?

          previous = @rgame_values.delete(checked_key(key))
          report_change(key, previous)
          shown(previous)
        end

        # Calls the block with the value of `key` now, then with every value that
        # differs, a field of its record and restores included. Returns a handle
        # for `unwatch`.
        def watch(key, &block)
          (@rgame_watchers[checked_key(key)] ||= []) << block
          yield shown(@rgame_values[key])
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
          { values: @rgame_values.transform_values { shown(it) }.freeze, machines: machines.freeze }.freeze
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

        def checked_field(field)
          return field if field.is_a?(Symbol)

          raise TypeError, "a fact's field is a Symbol, got #{field.inspect} (#{field.class})"
        end

        def checked_value(key, value) = FactsDatabase.check_value(value) { "facts[#{key.inspect}]" }

        def record_of(key, value)
          return value if value.nil? || value.is_a?(Hash)

          raise TypeError, "facts[#{key.inspect}] holds #{value.inspect}, not a record of fields; " \
                           'write it whole, or delete it first'
        end

        def write(key, value)
          checked_key(key)
          checked_value(key, value)
          previous = @rgame_values[key]
          @rgame_values[key] = stored(value)
          report_change(key, previous)
        end

        def write_field(key, field, value)
          checked_key(key)
          checked_field(field)
          FactsDatabase.check_value(value) { "facts[#{key.inspect}, #{field.inspect}]" }
          record = record_of(key, @rgame_values[key]) || (@rgame_values[key] = {})
          previous = record[field]
          current = record[field] = frozen(value)
          report_field_change(key, field, previous, current)
        end

        def delete_field(key, field)
          record = record_of(key, @rgame_values[checked_key(key)]) or return
          previous = record.delete(checked_field(field))
          @rgame_values.delete(key) if record.empty?
          report_field_change(key, field, previous, nil)
          previous
        end

        def stored(value) = value.is_a?(Hash) ? value.to_h { |field, inner| [field, frozen(inner)] } : frozen(value)

        def frozen(value)
          case value
          when String then -value
          when Hash then value.to_h { |field, inner| [field, frozen(inner)] }.freeze
          else value
          end
        end

        def shown(value) = value.is_a?(Hash) ? value.dup.freeze : value

        def parse(saved)
          return [{}, {}] if saved.nil?
          raise TypeError, "facts restore from a Hash, got #{saved.class}" unless saved.is_a?(Hash)

          values = saved.fetch(:values, {}).to_h do |key, value|
            checked_value(checked_key(key), value)
            [key, stored(value)]
          end
          [values, saved.fetch(:machines, {}).to_h { |name, entry| [checked_key(name), entry] }]
        end

        def report_change(key, previous)
          value = @rgame_values[key]
          return if previous.eql?(value)

          changed_signal.emit(key:, value: shown(value), field: nil)
          notify_watchers(key)
        end

        def report_field_change(key, field, previous, value)
          return if previous.eql?(value)

          changed_signal.emit(key:, value:, field:)
          notify_watchers(key)
        end

        def notify_watchers(key)
          @rgame_watchers[key]&.each { it.call(shown(@rgame_values[key])) }
        end
      end
    end
  end
end
