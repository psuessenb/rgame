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
      #
      # ## When a press activates
      #
      # `activate_on:` is `:release` by default: confirm draws the button pressed
      # while it is held and activates it when it is let go, so a player who
      # moves focus away while still holding cancels. `:press` activates on the
      # way down — what a skill bar wants — and keeps the button drawn pressed
      # for at least `PRESS_FEEDBACK` seconds, because a tap is otherwise a
      # single frame of pressed that nobody sees.
      #
      # Either way a button only acts on a press it saw start. A press whose
      # release it did not see — its menu was paused or covered in between — is
      # dropped rather than finished, so a menu that closes itself from
      # `on_activated` and is opened again does not come back pressed. See
      # UI::Menu for the other half, a menu that has not yet seen confirm up.
      class Button < Node2D
        signal :on_activated

        PRESS_FEEDBACK = 0.1
        ACTIVATE_ON = %i[release press].freeze

        attr_accessor :label, :enabled
        attr_reader :activate_on

        def initialize(label: nil, enabled: true, activate_on: :release, **)
          super(**)
          unless ACTIVATE_ON.include?(activate_on)
            raise ArgumentError, "activate_on: must be :release or :press, not #{activate_on.inspect}"
          end

          @label = label
          @enabled = enabled
          @activate_on = activate_on
          @focused = false
          @held = false
          @feedback = 0.0
        end

        def enabled? = @enabled
        def focused? = @focused
        def pressed? = @held || @feedback.positive?

        # What to draw: `:disabled` whenever the button is disabled, whatever
        # else is true; then `:pressed`, `:focused`, and otherwise `:idle`.
        # Pressed does not require focus: a press can outlast the focus that
        # started it by its `PRESS_FEEDBACK`.
        def state
          return :disabled unless @enabled
          return :pressed if pressed?

          @focused ? :focused : :idle
        end

        # Called by the Menu. Calls `on_focus_changed` when the value actually
        # changes, and never for a repeated assignment, so a menu that reasserts
        # focus every frame does not replay a focus sound every frame. Losing
        # focus lets go of a held press without activating it.
        def focused=(value)
          return if @focused == value

          @focused = value
          @held = false unless value
          on_focus_changed(value)
        end

        # Called by the Menu when a press starts on this button. Activates at
        # once under `activate_on: :press` and returns what `activate` did;
        # otherwise holds the press and returns nil. A disabled button ignores
        # it.
        def press
          return nil unless @enabled

          @held = true
          return nil unless @activate_on == :press

          @feedback = PRESS_FEEDBACK
          activate
        end

        # Called by the Menu when a press this button saw start is let go.
        # Activates under `activate_on: :release`, and returns what `activate`
        # did.
        def release
          return nil unless @held

          @held = false
          activate if @activate_on == :release
        end

        # Called by the Menu for a press whose release this button never saw.
        # Drops it, and the feedback with it, activating nothing.
        def cancel_press
          return unless @held

          @held = false
          @feedback = 0.0
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

        # Counts down the pressed feedback, then does what every node does.
        def update(dt)
          @feedback -= dt if @feedback.positive? && !@paused
          super
        end

        # Hook: override to react to gaining or losing focus — a sound, the
        # start of an animation. Called only on a change.
        def on_focus_changed(focused); end
      end
    end
  end
end
