# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # Anything a Menu can hold: the state a button has — enabled, focused,
      # pressed — and a signal for when it is chosen, with no look at all.
      #
      #   class Swatch < UI::Button
      #     def initialize(color:, **)
      #       super(**)
      #       @color = color
      #     end
      #
      #     def on_draw(renderer, _view)
      #       inset = state == :focused ? 0 : 4
      #       renderer.rect(inset, inset, width - (inset * 2), height - (inset * 2), color: @color)
      #     end
      #   end
      #
      # The look is a subclass's `on_draw`, and it reads `state` to decide what
      # to draw. Everything the menu needs from a button — being told it is
      # focused or pressed, being activated, being asked to `adjust` — lives
      # here, so a subclass that only draws cannot leave any of it out.
      #
      # There is no hover, because there is no pointer: what a mouse-driven
      # control would get from the cursor being over it, this gets from the Menu
      # telling it it is the focused one.
      #
      # Its position is its own, resolved through the tree like any node's, so a
      # Menu inside a PlayerLayer puts its buttons inside that player's region
      # without either of them arranging it.
      #
      # A Button with no `on_draw` of its own draws nothing.
      class Button < Node2D
        signal :on_activated

        attr_accessor :label, :enabled
        attr_writer :pressed

        def initialize(label: nil, enabled: true, **)
          super(**)
          @label = label
          @enabled = enabled
          @focused = false
          @pressed = false
        end

        def enabled? = @enabled
        def focused? = @focused
        def pressed? = @pressed

        # What to draw: `:disabled` whenever the button is disabled, whatever
        # else is true; `:pressed` while it is focused and pressed; `:focused`;
        # and otherwise `:idle`.
        def state
          return :disabled unless @enabled
          return :idle unless @focused

          @pressed ? :pressed : :focused
        end

        # Called by the Menu. Calls `on_focus_changed` when the value actually
        # changes, and never for a repeated assignment, so a menu that reasserts
        # focus every frame does not replay a focus sound every frame.
        def focused=(value)
          return if @focused == value

          @focused = value
          on_focus_changed(value)
        end

        # What the focused button does with `ui_left` / `ui_right`, which the
        # menu hands down without knowing what kind of button it is talking to.
        # A plain button has nothing to change, and answers nil the way a
        # disabled `activate` does. UI::OptionButton is the one that overrides it.
        def adjust(_delta) = nil

        # Fires the signal and returns the button, or nil if it is disabled — so
        # a caller never has to check first, and a disabled button cannot be
        # activated by any route.
        def activate
          return nil unless @enabled

          on_activated_signal.emit
          self
        end

        # Hook: override to react to gaining or losing focus — a sound, the
        # start of an animation. Called only on a change.
        def on_focus_changed(focused); end
      end
    end
  end
end
