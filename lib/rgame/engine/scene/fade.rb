# frozen_string_literal: true

module RGame
  module Engine
    module Scene
      # How a SceneStack changes scenes: it covers the view in `color` over
      # `cover` seconds, switches while covered, and reveals the new scene over
      # `reveal` seconds.
      #
      #   stack.transition = Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)
      #
      # A frozen value. `color` defaults to black and must be a Util::Color;
      # each duration must be a positive number of seconds.
      Fade = Data.define(:color, :cover, :reveal) do
        def initialize(cover:, reveal:, color: Util::Color::BLACK)
          raise TypeError, "a Fade's colour must be a Util::Color, not #{color.inspect}" unless color.is_a?(Util::Color)

          { cover:, reveal: }.each { |name, seconds| check_seconds(name, seconds) }
          super
        end

        private

        def check_seconds(name, seconds)
          raise TypeError, "a Fade's #{name} is in seconds, not #{seconds.inspect}" unless seconds.is_a?(Numeric)
          raise ArgumentError, "a Fade's #{name} must be positive, not #{seconds}" unless seconds.positive?
        end
      end
    end
  end
end
