# frozen_string_literal: true

module Engine
  module UI
    # A clickable button: a 9-slice background whose texture reflects its current
    # state (idle / focused / pressed / disabled) plus a centred label. The owning
    # Menu decides which control is focused; a focused button watches the input
    # itself and emits :clicked to its observers on a confirm/click release inside
    # it. The click carries no payload — `source` (this button) identifies it; its
    # `action` id is what the Menu reads to report a selection.
    class Button < Control
      include Engine::UI::Localized

      # Atlas ids per visual state + the label colour (RGB, engine-side — the
      # renderer turns it into a Gosu colour). Pass a different Style to re-skin.
      Style = Data.define(:idle, :focus, :pressed, :disabled, :label_color) do
        def self.default
          new(
            idle: :button_idle, focus: :button_focus, pressed: :button_pressed,
            disabled: :button_disabled, label_color: [60, 42, 28]
          )
        end
      end
      signal :on_clicked # emits no payload; `source` (this button) identifies the click

      attr_reader :label, :action

      def initialize(parent, x:, y:, width:, height:, label: nil, key: nil, vars: nil, action: nil,
                     style: Style.default, z: 0, enabled: true)
        super(parent, x: x, y: y, width: width, height: height, z: z, enabled: enabled)
        @label = label
        @action = action
        @style = style
        @pressed = false
        @label_width = nil # measured once on first draw, then cached (never in the hot path)
        init_localization(key, vars)
      end

      def label=(value)
        @label = value
        @label_width = nil # invalidate the cached measurement
      end

      # Only acts while focused; the Menu owns focus. Confirm (keyboard/controller)
      # or a click (mouse, while hovering) arms it; releasing inside fires :clicked.
      def update(_dt, actions)
        return @pressed = false unless @enabled && @focused

        @pressed = true if actions.pressed?(:confirm)
        @pressed = true if actions.pressed?(:ui_click) && hovering?(actions)

        if actions.released?(:confirm)
          activate if @pressed
          @pressed = false
        elsif actions.released?(:ui_click)
          activate if @pressed && hovering?(actions)
          @pressed = false
        end
      end

      def draw(renderer)
        renderer.nine_slice(texture, @abs_x, @abs_y, @width, @height, z: @abs_z)
        refresh_localization { |resolved| self.label = resolved }
        @label_width ||= renderer.text_width(@label)
        tx = @abs_x + ((@width - @label_width) / 2)
        ty = @abs_y + ((@height - renderer.text_height) / 2)
        renderer.text(@label, tx, ty, z: @abs_z + 1, color: @style.label_color)
      end

      private

      def hovering?(actions) = contains?(actions.pointer_x, actions.pointer_y)

      def activate = on_clicked_signal.emit

      def texture
        return @style.disabled unless @enabled
        return @style.pressed if @pressed
        return @style.focus if @focused

        @style.idle
      end
    end
  end
end
