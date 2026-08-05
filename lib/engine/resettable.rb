# frozen_string_literal: true

module Engine
  # Builds value-object classes for pooling. Like `Data.define`, instances expose
  # read-only accessors and carry their fields as a unit — but where a `Data` value
  # is fully immutable (every change means a fresh allocation), these add exactly
  # one mutation: `reset`, which overwrites all fields at once and returns self.
  #
  # That is the only mutability a pool needs: acquire a recycled instance and
  # `reset` it, without exposing the per-field setters a `Struct` would. The methods
  # are generated fixed-arity with direct ivar assignment (as Struct/Data do), so
  # `reset` is allocation-free and recycling stays zero-allocation in steady state.
  #
  # Positional by default; pass `keyword_init: true` for keyword fields. Keywords
  # are *also* allocation-free here because they are generated as named parameters
  # (`reset(x:, y:)`), not a `**kwargs` splat — the splat is the one form that builds
  # a Hash per call.
  #
  #   Point = Engine::Resettable.define(:x, :y)
  #   p = Point.new(3, 4); p.x            # => 3
  #   p.reset(5, 6)                       # same object, new values; returns p
  #
  #   Event = Engine::Resettable.define(:type, :payload, keyword_init: true)
  #   e = Event.new(type: :hit, payload: 10)
  #   e.reset(type: :lose, payload: nil)  # same object; returns e
  #   e.respond_to?(:type=)               # => false (no setters)
  #
  # Field names are generated into real methods, so they must be plain identifiers.
  module Resettable
    IDENTIFIER = /\A[a-z_][a-zA-Z0-9_]*\z/

    def self.define(*fields, keyword_init: false)
      fields.each do |field|
        raise ArgumentError, "invalid field name: #{field.inspect}" unless field.to_s.match?(IDENTIFIER)
      end

      params = fields.map { |f| keyword_init ? "#{f}:" : f.to_s }.join(', ')
      assign = fields.map { |f| "@#{f} = #{f}" }.join("\n")

      Class.new do
        class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          # For fields [:x, :y] this generates (keyword_init makes `x, y` -> `x:, y:`):
          #   attr_reader :x, :y
          #   def initialize(x, y)
          #     @x = x; @y = y
          #   end
          #   def reset(x, y)
          #     @x = x; @y = y
          #     self
          #   end
          attr_reader #{fields.map { |f| ":#{f}" }.join(', ')}

          def initialize(#{params})
            #{assign}
          end

          def reset(#{params})
            #{assign}
            self
          end
        RUBY
      end
    end
  end
end
