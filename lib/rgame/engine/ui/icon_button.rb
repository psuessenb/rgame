# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A picture, tinted by state, with an optional caption: the round,
      # image-only entry of a quick-select wheel, or a skill with its name
      # underneath.
      #
      #   disc = UI::ShapeStyle.new(shape: :disc)
      #   wheel.add(UI::IconButton.new(image: :home, style: disc)).on_activated { go_home }
      #   bar.add(UI::IconButton.new(image: :torch, label: 'torch', style: disc))
      #
      # `image:` is an image id — a registered Symbol or a path String — drawn at
      # its natural size, centred in the slot, or centred in the space above the
      # caption when there is one. The caption is centred along the bottom edge,
      # inside the slot, so the slot is still the button's whole extent.
      #
      # **A caption sits under the style, not on it.** With a caption the style
      # is handed the space above it, so a disc is drawn round the picture and the
      # caption reads on whatever is behind the button, in the button's own label
      # colours. A caption wider than the disc — "Watering can" under a tool — is
      # the ordinary case in a skill bar, and one drawn across a disc's edge would
      # be half on the fill and half off it, legible on neither.
      #
      # `image: nil` draws no picture and leaves the caption, for an entry whose
      # art is not in yet. An id nobody registered is a mistake rather than that
      # case, and fails on the first draw like any other image.
      #
      # **Tint is a multiply**, so the art should be white: white takes each
      # colour in `tints:` exactly, and dark art takes none of them. Scales
      # default to 1 in every state because images sample nearest-neighbour, so
      # any scale but a whole number doubles some pixel rows and not others; focus
      # shows through the tint and the style instead. `tints:` and `scales:` need
      # every state, checked here rather than the first frame one is reached.
      #
      # No style by default: an icon on its own is a complete look. The style is
      # drawn at `z: 0` or below, the picture and the caption at `z: 1`. A style
      # answering `content_color(state)` — UI::ShapeStyle does — replaces the tint
      # in any state it names, because what reads on its fill is the style's to
      # say: the pressed tint is the same gold as a ShapeStyle's pressed fill. It
      # does not touch the caption, which is not on the fill.
      class IconButton < Button
        TINTS = {
          idle: Util::Color.new(200, 200, 212),
          focused: Util::Color.new(255, 255, 255),
          pressed: Util::Color.new(240, 200, 96),
          disabled: Util::Color.new(90, 88, 100)
        }.freeze
        SCALES = { idle: 1, focused: 1, pressed: 1, disabled: 1 }.freeze

        attr_reader :image, :style, :tints, :scales, :label_color, :disabled_label_color

        def initialize(image:, style: nil, tints: TINTS, scales: SCALES,
                       label_color: TextButton::LABEL_COLOR,
                       disabled_label_color: TextButton::DISABLED_LABEL_COLOR, **)
          super(**)
          @image = image
          @style = style
          @style_names_content = style.respond_to?(:content_color)
          @tints = STATES.to_h { |state| [state, Util::Color.coerce(tints.fetch(state))] }.freeze
          @scales = STATES.to_h { |state| [state, scales.fetch(state)] }.freeze
          @label_color = Util::Color.coerce(label_color)
          @disabled_label_color = Util::Color.coerce(disabled_label_color)
        end

        def on_draw(renderer, _view)
          current = state
          caption_height = @label ? renderer.text_height : 0
          @style&.draw(renderer, current, width, height - caption_height)
          content = @style_names_content ? @style.content_color(current) : nil
          draw_image(renderer, current, content, (height - caption_height) / 2.0)
          draw_caption(renderer, caption_height) if @label
        end

        private

        def draw_image(renderer, current, content, cy)
          return unless @image

          renderer.image(@image, width / 2.0, cy,
                         scale: @scales.fetch(current), z: 1, color: content || @tints.fetch(current))
        end

        def draw_caption(renderer, caption_height)
          text = @label.to_s
          renderer.text(text, (width - renderer.text_width(text)) / 2, height - caption_height,
                        z: 1, color: @enabled ? @label_color : @disabled_label_color)
        end
      end
    end
  end
end
