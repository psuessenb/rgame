# frozen_string_literal: true

module Engine
  # A 2D camera: follows a target point and clamps to world bounds so it never
  # shows past the map edges. Pure; the platform applies (x, y) as a draw offset.
  class Camera
    attr_reader :x, :y, :viewport_width, :viewport_height

    def initialize(viewport_width:, viewport_height:, world_width:, world_height:)
      @viewport_width = viewport_width
      @viewport_height = viewport_height
      @world_width = world_width
      @world_height = world_height
      @x = 0.0
      @y = 0.0
    end

    def center_on(world_x, world_y)
      @x = clamp(world_x - @viewport_width / 2.0, @world_width - @viewport_width)
      @y = clamp(world_y - @viewport_height / 2.0, @world_height - @viewport_height)
    end

    private

    def clamp(value, max)
      return 0.0 if max <= 0 # world smaller than the viewport → pin to origin

      value.clamp(0.0, max.to_f)
    end
  end
end
