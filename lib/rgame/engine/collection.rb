# frozen_string_literal: true

module RGame
  module Engine
    # Enumerable for a class that keeps its members in one Array, answered by
    # that Array rather than through the class's own `each`.
    #
    #   class Players < Component
    #     include Collection.of(:@list)
    #   end
    #
    # `include Enumerable` answers `any?`, `find` or `count` by calling `each`
    # with a block Ruby wraps for the purpose, and that costs three objects a
    # call. An Array answers the same methods itself and allocates nothing. So
    # the module `of` builds forwards every Enumerable method to the Array in
    # the named instance variable, and `players.any? { ... }` in a `_control`
    # costs what it costs on an Array. The class keeps its own `each`, and is
    # still an Enumerable.
    #
    # `to_a` is the one method not forwarded. `Array#to_a` returns the Array
    # itself, which would hand a caller the collection's own list to change.
    #
    # A class that includes Enumerable over an `each` of its own fails
    # `spec/rgame/engine/collection_spec.rb`, which finds every one in RGame.
    #
    # @api private
    module Collection
      KEPT = %i[to_a].freeze

      @modules = {}

      # The module to include for members held in the Array at `ivar`, such as
      # `:@list`. One module per name, shared by every class that uses it.
      def self.of(ivar)
        unless ivar.match?(/\A@\w+\z/)
          raise ArgumentError, "a collection forwards to an instance variable, not #{ivar.inspect}"
        end

        @modules[ivar] ||= forwarding(ivar)
      end

      def self.forwarding(ivar)
        Module.new.tap do |mod|
          mod.include(Enumerable)
          mod.module_eval(forwarders(ivar), __FILE__, __LINE__)
        end
      end

      def self.forwarders(ivar)
        (Enumerable.instance_methods - KEPT).map { |name| "def #{name}(...) = #{ivar}.#{name}(...)\n" }.join
      end
      private_class_method :forwarding, :forwarders
    end
  end
end
