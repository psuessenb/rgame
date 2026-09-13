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
      # outline. Colours are coerced once, here, so `colors:` takes arrays and a
      # draw allocates nothing; and a missing state is a `KeyError` here, rather
      # than on the first frame a button happens to be disabled.
      #
      # Fill and outline are drawn at `z: 0` and `z: -1`. Shapes default to
      # `z: 50`, which would cover the label or icon a button draws at `z: 1`.
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

        FILL_Z = 0
        OUTLINE_Z = -1

        attr_reader :shape, :colors, :outline, :border

        def initialize(shape: :rect, colors: COLORS, outline: OUTLINE, border: 3)
          unless SHAPES.include?(shape)
            raise ArgumentError, "shape: must be one of #{SHAPES.inspect}, not #{shape.inspect}"
          end

          @shape = shape
          @colors = Button::STATES.to_h { |state| [state, colors.fetch(state)&.then { Util::Color.coerce(it) }] }.freeze
          @outline = outline&.then { Util::Color.coerce(it) }
          @border = border
        end

        DEFAULT = new

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
