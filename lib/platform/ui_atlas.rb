# frozen_string_literal: true

require 'json'

module Platform
  # Loads a UI texture atlas (one source sheet + a JSON descriptor) into NineSlice
  # objects keyed by element id. The descriptor names a sub-rect and 9-slice border
  # for each element, so a single sheet supplies button states, panels, etc.
  #
  #   { "image": "buttons.png", "scale": 3,
  #     "nine_slices": {
  #       "button_idle": { "x": 11, "y": 59, "w": 26, "h": 28, "border": 7 }
  #     } }
  #
  # `border` is a uniform integer or an explicit { left, right, top, bottom }. A
  # per-entry `scale` overrides the sheet default.
  class UiAtlas
    attr_reader :nine_slices

    # Load standalone: parse the descriptor and its image. The AssetManager instead
    # calls .new with an image it has already loaded + cached (so the PNG is shared),
    # mirroring Platform::TileMapRenderer.load.
    def self.load(atlas_path)
      data = JSON.parse(File.read(atlas_path), symbolize_names: true)
      dir  = File.dirname(File.expand_path(atlas_path))
      new(Gosu::Image.new(File.join(dir, data[:image]), retro: true), data)
    end

    # `data` is the parsed descriptor hash; `image` the already-loaded sheet image.
    def initialize(image, data)
      scale = data[:scale] || 1

      @nine_slices = (data[:nine_slices] || {}).transform_values do |spec|
        NineSlice.new(
          image,
          x: spec[:x], y: spec[:y], w: spec[:w], h: spec[:h],
          border: normalize_border(spec[:border]), scale: spec[:scale] || scale
        )
      end
    end

    private

    def normalize_border(border)
      return border.transform_keys(&:to_sym) unless border.is_a?(Integer)

      { left: border, right: border, top: border, bottom: border }
    end
  end
end
