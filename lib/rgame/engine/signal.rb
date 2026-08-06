# frozen_string_literal: true

module RGame
  module Engine
    module Signal
      IDENTIFIER = /\A[a-z_][a-zA-Z0-9_]*\z/

      # Class-level DSL for declaring signal "slots" so a host class need not hand-write
      # the connect-forwarding boilerplate. `extend Engine::Signal::DSL`, then:
      #
      #   signal :on_clicked               # a no-arg signal
      #   signal :on_changed, ChangeSignal # a typed signal (Signal.define(:index, :value))
      #
      # For :on_clicked this generates:
      #   def on_clicked(&block) = on_clicked_signal.connect(&block) # public: subscribe, returns handle
      #   def on_clicked_signal = (@on_clicked ||= type.new)         # private: the Signal, to emit on
      #
      # The Signal is built lazily on first use, so the host wires nothing in #initialize;
      # emit from inside the host via the private `<name>_signal` reader.
      module DSL
        def signal(name, type = Signal.define)
          ivar = :"@#{name}"
          reader = :"#{name}_signal"

          define_method(reader) do
            instance_variable_get(ivar) || instance_variable_set(ivar, type.new)
          end
          private reader

          define_method(name) { |&block| send(reader).connect(&block) }
        end
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
