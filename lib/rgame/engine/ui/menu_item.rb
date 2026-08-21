# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # One entry in a Menu: a label on a nine-slice, and a signal for when it is
      # chosen.
      #
      #   resume = menu.add_item('Resume')
      #   resume.on_activated { cutscene.close }
      #
      # It draws itself from its **state** — focused, pressed, disabled or
      # idle — which is why the shipped atlas has an element for each. There is
      # no hover, because there is no pointer: what a mouse-driven control would
      # get from the cursor being over it, this gets from the Menu telling it it
      # is the focused one.
      #
      # Its position is its own, resolved through the tree like any node's, so a
      # Menu inside a PlayerLayer puts its items inside that player's region
      # without either of them arranging it.
      class MenuItem < Node2D
        signal :on_activated # emits no payload; the item is the handle

        # Atlas element per state. Replaceable per menu, so a game with its own
        # art is not obliged to name it the way the shipped atlas does.
        STYLE = {
          idle: :button_idle,
          focus: :button_focus,
          pressed: :button_pressed,
          disabled: :button_disabled
        }.freeze

        LABEL_COLOR = [46, 34, 24].freeze
        DISABLED_LABEL_COLOR = [120, 110, 100].freeze

        attr_accessor :label, :enabled
        attr_writer :focused, :pressed

        def initialize(label:, z: Z::HUD, style: STYLE, enabled: true, **)
          super(**)
          @label = label
          @layer = z
          @style = style
          @enabled = enabled
          @focused = false
          @pressed = false
        end

        def enabled? = @enabled
        def focused? = @focused

        # Fires the signal and returns the item, or nil if it is disabled — so a
        # caller never has to check first, and a disabled item cannot be
        # activated by any route.
        def activate
          return nil unless @enabled

          on_activated_signal.emit
          self
        end

        def on_draw(renderer, _view)
          renderer.nine_slice(@style.fetch(state), abs_x, abs_y, width, height, z: @layer)
          renderer.text(@label, label_x(renderer), label_y(renderer),
                        z: @layer + 1, color: @enabled ? LABEL_COLOR : DISABLED_LABEL_COLOR)
        end

        private

        def state
          return :disabled unless @enabled
          return :idle unless @focused

          @pressed ? :pressed : :focus
        end

        def label_x(renderer) = abs_x + ((width - renderer.text_width(@label)) / 2)
        def label_y(renderer) = abs_y + ((height - renderer.text_height) / 2)
      end
    end
  end
end
