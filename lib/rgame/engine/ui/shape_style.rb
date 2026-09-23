# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A button background drawn from plain shapes — a rectangle or a disc, a
      # fill per state, and an outline while focused or pressed — so a menu can
      # be built and played before any art exists.
      #
      #   round = UI::ShapeStyle.new(shape: :disc)
      #   quiet = UI::ShapeStyle.new(colors: UI::ShapeStyle::COLORS.merge(idle: nil), outline: nil)
      #
      # The fill is inset by `border` in every state, and the outline is the whole
      # shape drawn under it, so a button does not change size as its state
      # changes: focus only uncovers the ring the fill leaves. A disc is centred in
      # the slot, as large as its shorter side.
      #
      # `nil` in `colors:` draws no fill in that state, and `outline: nil` draws no
      # outline. Colours are coerced once, here, so a draw allocates nothing; and
      # a missing state is a `KeyError` here, rather than on the first frame a
      # button happens to be disabled.
      #
      # Fill and outline are drawn at `z: 0` and `z: -1`, under the label or
      # icon a button draws at `z: 1`.
      #
      # ## What reads on the fill is the style's to say
      #
      # `content:` is the colour a button draws its label or icon in over each
      # state's fill, or `nil` to keep the button's own. The pressed fill is gold,
      # and so is IconButton's pressed tint, so without it a pressed icon is gold
      # on gold and vanishes; a light label nearly does. The style picks the fill,
      # so it is the one place that can pick what goes on it. Defaults to dark
      # while pressed and the button's own colour otherwise.
      class ShapeStyle
        SHAPES = %i[rect disc].freeze
        OUTLINED = %i[focused pressed].freeze

        COLORS = {
          idle: Util::Color.new(52, 48, 62),
          focused: Util::Color.new(72, 66, 88),
          pressed: Util::Color.new(240, 200, 96),
          disabled: Util::Color.new(40, 38, 46)
        }.freeze
        OUTLINE = Util::Color.new(240, 200, 96)
        CONTENT = { idle: nil, focused: nil, pressed: Util::Color.new(46, 34, 24), disabled: nil }.freeze

        FILL_Z = 0
        OUTLINE_Z = -1

        attr_reader :shape, :colors, :outline, :border, :content

        def initialize(shape: :rect, colors: COLORS, outline: OUTLINE, border: 3, content: CONTENT)
          unless SHAPES.include?(shape)
            raise ArgumentError, "shape: must be one of #{SHAPES.inspect}, not #{shape.inspect}"
          end

          @shape = shape
          @colors = Button::STATES.to_h { |state| [state, colors.fetch(state)&.then { Util::Color.coerce(it) }] }.freeze
          @content = Button::STATES.to_h do |state|
            [state, content.fetch(state)&.then { Util::Color.coerce(it) }]
          end.freeze
          @outline = outline&.then { Util::Color.coerce(it) }
          @border = border
        end

        DEFAULT = new

        # The colour a button draws its content in over this state's fill, or
        # nil for the button's own. See "What reads on the fill" above.
        def content_color(state) = @content.fetch(state)

        def draw(renderer, state, width, height)
          outlined = @outline && OUTLINED.include?(state)
          fill = @colors.fetch(state)
          if @shape == :disc
            draw_disc(renderer, fill, outlined, width, height)
          else
            draw_rect(renderer, fill, outlined, width, height)
          end
        end

        private

        def draw_rect(renderer, fill, outlined, width, height)
          renderer.rect(0, 0, width, height, z: OUTLINE_Z, color: @outline) if outlined
          return unless fill

          renderer.rect(@border, @border, width - (@border * 2), height - (@border * 2),
                        z: FILL_Z, color: fill)
        end

        def draw_disc(renderer, fill, outlined, width, height)
          cx = width / 2.0
          cy = height / 2.0
          radius = [width, height].min / 2.0
          renderer.circle(cx, cy, radius, z: OUTLINE_Z, color: @outline) if outlined
          renderer.circle(cx, cy, radius - @border, z: FILL_Z, color: fill) if fill
        end
      end
    end
  end
end
