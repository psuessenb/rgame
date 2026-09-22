# frozen_string_literal: true

module RGame
  module Engine
    # An observer channel: listeners connect a block, and the owner emits to
    # every one of them in the order they connected. `Signal.define` builds the
    # class for a payload, and `Signal::DSL` declares one per instance of a class.
    module Signal
      IDENTIFIER = /\A[a-z_][a-zA-Z0-9_]*\z/

      # Declares a signal on every instance of a class, named by its event: a
      # verb in the past tense. `extend Engine::Signal::DSL`, then:
      #
      #   signal :activated                # no payload
      #   signal :changed, :index, :value  # a payload of two fields
      #
      # For :changed this generates:
      #   def on_changed(&block) = changed_signal.connect(&block)            # public: connect, returns the handle
      #   def changed_signal = (@changed_signal ||= Signal.define(...).new)  # private: the Signal, to emit on
      #
      # The class emits through the private reader, `changed_signal.emit(index: 2,
      # value: :hard)`. One field emits positionally and several as keywords, as
      # `Signal.define` decides. The Signal is built on first use, so the class
      # wires nothing in #initialize.
      #
      # The DSL adds the `on_` itself, so a name starting with `on_` raises at
      # class definition, as does anything but Symbols after the name.
      #
      # A subclass defining either generated method raises `NameError` where it
      # is defined. A `def on_activated` meant as a hook would otherwise replace
      # the connect method, and every block passed to it would be dropped
      # without a word.
      module DSL
        def signal(name, *fields)
          if name.start_with?('on_')
            raise ArgumentError, "signal :#{name}: declare the event, signal :#{name.to_s.delete_prefix('on_')}; " \
                                 'the DSL adds on_'
          end

          type = Signal.define(*fields)
          reader = :"#{name}_signal"
          connect = :"on_#{name}"
          ivar = :"@#{reader}"

          define_method(reader) do
            instance_variable_get(ivar) || instance_variable_set(ivar, type.new)
          end
          private reader

          define_method(connect) { |&block| send(reader).connect(&block) }
          signal_methods[reader] = signal_methods[connect] = name
        end

        def method_added(name)
          super
          declarer = ancestors.find { it.is_a?(DSL) && it.signal_methods.key?(name) }
          return unless declarer

          event = declarer.signal_methods[name]
          raise NameError.new("#{self}##{name} would replace what signal :#{event} generated in #{declarer}, " \
                              'and no block could connect to that signal any more. To react to it, connect ' \
                              "a block: on_#{event} { ... }. Otherwise give the method another name.", name)
        end

        protected

        def signal_methods = (@signal_methods ||= {})
      end

      def self.define(*fields)
        fields.each do |field|
          raise ArgumentError, "invalid field name: #{field.inspect}" unless field.to_s.match?(IDENTIFIER)
        end

        params = fields.size == 1 ? fields.first : fields.map { |f| "#{f}:" }.join(', ')
        args = fields.join(', ')

        Class.new do
          class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
            # For fields [:x, :y] this generates:
            #   def initialize
            #     @listeners = []
            #   end
            #   def connect(&callback)
            #     @listeners << callback
            #     callback
            #   end
            #   def disconnect(handle) = @listeners.delete(handle)
            #   def emit(x:, y:)
            #     @listeners.each { it.call(x, y) }
            #   end

            def initialize
              @listeners = []
            end

            def connect(&callback)
              @listeners << callback
              callback
            end

            def disconnect(handle) = @listeners.delete(handle)
            def emit(#{params})
              @listeners.each { it.call(#{args}) }
            end
          RUBY
        end
      end
    end
  end
end
