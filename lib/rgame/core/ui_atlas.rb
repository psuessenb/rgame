# frozen_string_literal: true

require 'json'

require_relative 'image'
require_relative 'nine_slice'

module RGame
  module Core
    # One sheet of UI chrome, cut into named nine-slices.
    #
    #   atlas = RGame::Core::UiAtlas.load(app, 'media/ui.json')
    #   renderer.register_ui_atlas(atlas)
    #   renderer.nine_slice(:button_idle, x, y, width, height)
    #
    # A button has four states, a panel has one, a scrollbar has three pieces —
    # all of them small, and all of them cheaper as sub-rectangles of a single
    # texture than as a dozen separate files. This is that texture plus a
    # descriptor naming what is where.
    #
    # ## The descriptor
    #
    #   {
    #     "image": "buttons.png",
    #     "scale": 3,
    #     "nine_slices": {
    #       "button_idle":  { "x": 11, "y": 59, "w": 26, "h": 28, "border": 7 },
    #       "button_focus": { "x": 43, "y": 59, "w": 26, "h": 28, "border": 7 },
    #       "panel":        { "x": 0,  "y": 0,  "w": 32, "h": 32,
    #                         "border": { "left": 4, "right": 4, "top": 8, "bottom": 4 },
    #                         "scale": 2 }
    #     }
    #   }
    #
    # `image` is resolved next to the descriptor. Each entry is a source
    # rectangle plus a border — a uniform integer or one value per side — and an
    # optional `scale` overriding the sheet default. See
    # RGame::Core::NineSlice for what those mean when it is drawn.
    #
    # ## Element names, not filenames
    #
    # `nine_slices` is keyed by whatever the descriptor calls each element, and
    # those names are what a widget asks for. That is why nine-slices are the
    # one asset the renderer resolves by registration only: `:button_focus` is
    # not a file and never can be. `Renderer#register_ui_atlas` registers every
    # element in one call.
    #
    # Parsing happens once, at load. Nothing here is touched again per frame.
    class UiAtlas
      # The elements, by name. Values are `NineSlice`s.
      attr_reader :nine_slices

      # Loads a descriptor and the sheet beside it.
      #
      # The `AssetManager` uses `.new` instead, with an image it has already
      # cached, so the sheet is shared with any other use of the same file.
      def self.load(app, atlas_path)
        data = JSON.parse(File.read(atlas_path), symbolize_names: true)
        directory = File.dirname(File.expand_path(atlas_path))
        new(Image.new(app, File.join(directory, data[:image])), data)
      end

      # `data` is the parsed descriptor; `image` an already-loaded sheet.
      def initialize(image, data)
        sheet_scale = data[:scale] || 1

        @nine_slices = (data[:nine_slices] || {}).to_h do |id, spec|
          [id, build(image, id, spec, sheet_scale)]
        end
      end

      private

      # A descriptor holds many elements, and a mistake in one of them surfaces
      # from inside NineSlice's arithmetic — "undefined method '-' for nil" says
      # nothing about *which* button is wrong. Naming the element is the whole
      # value this wrapper adds, so it catches broadly on purpose.
      def build(image, id, spec, sheet_scale)
        NineSlice.new(image, x: spec[:x], y: spec[:y], w: spec[:w], h: spec[:h],
                             border: spec[:border], scale: spec[:scale] || sheet_scale)
      rescue StandardError => e
        raise ArgumentError, "ui atlas element #{id.inspect}: #{e.message}"
      end
    end
  end
end
