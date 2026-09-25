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
      #     def _draw(renderer, _view)
      #       inset = state == :focused ? 0 : 4
      #       renderer.rect(inset, inset, width - (inset * 2), height - (inset * 2), color: @color)
      #     end
      #   end
      #
      # The look is a subclass's `_draw`, and it reads `state` to decide what
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
      # A Button with no `_draw` of its own draws nothing.
      #
      # ## The label is a translation key
      #
      # `label: 'play'` is a key, and the button holds it as an Engine::Text, so
      # what is drawn follows `I18n.locale` without the button being rebuilt.
      # Text that must not be translated — a player's name — is passed as one:
      #
      #   UI::TextButton.new(label: 'play')                        # the key 'play'
      #   UI::TextButton.new(label: Engine::Text.literal(name))    # the name, in every language
      #
      # A label is drawn as it reads, so a `Text` with variables shows the values
      # its last `with` was given. The node that owns them calls `with` in
      # `update`, and the label follows:
      #
      #   @continue = Engine::Text.new('continue', :saves)
      #   menu.add(UI::PanelButton.new(label: @continue))
      #   def _update(_dt) = @continue.with(saves: @save_count)
      #
      # One given no `with` yet raises on the first draw, naming the keywords.
      #
      # `label_scope` puts a scope in front of a label given as a key, and
      # UI::Menu sets it from its own `scope:` as the button is added. A label
      # given as a `Text` is the caller's, scope and all, and nothing changes it.
      #
      # ## When a press activates
      #
      # `activate_on:` is `:release` by default: confirm draws the button pressed
      # while it is held and activates it when it is let go, so a player who
      # moves focus away while still holding cancels. `:press` activates on the
      # way down — what a skill bar wants — and keeps the button drawn pressed
      # for at least `PRESS_FEEDBACK` seconds, because a tap is otherwise a
      # single frame of pressed that nobody sees. Its 0.1 s is Unity's, which
      # holds a submitted button pressed that long; Godot holds a shortcut's for
      # 0.2 s.
      #
      # Either way a button only acts on a press it saw start. A press whose
      # release it did not see — its menu was paused or covered in between — is
      # dropped rather than finished, so a menu that closes itself from
      # `on_activated` and is opened again does not come back pressed. See
      # UI::Menu for the other half, a menu that has not yet seen confirm up.
      #
      # ## A hotkey
      #
      # `hotkey:` names an action that presses this button whether or not it is
      # focused, and without moving focus — a skill bar's number keys:
      #
      #   UI::IconButton.new(image: :torch, hotkey: :skill3)
      #
      # A hotkey always activates on the press, whatever `activate_on:` says,
      # and draws pressed for `PRESS_FEEDBACK` or while held. Its release
      # activates nothing. The menu reads it, so the action has to be declared
      # in the player's InputMap; an undeclared one raises on the first frame.
      #
      # **A press belongs to the source that started it.** The menu passes
      # `:confirm` or `:hotkey` to `press`, `release` and `cancel_press`, and
      # while one source holds the button a press from the other is ignored and
      # its release ends nothing. So a player holding confirm on a `:release`
      # button who taps that button's hotkey activates it once, when confirm is
      # let go; and losing focus ends a confirm hold but not a hotkey one.
      class Button < Node2D
        signal :activated

        PRESS_FEEDBACK = 0.1
        STATES = %i[idle focused pressed disabled].freeze
        ACTIVATE_ON = %i[release press].freeze
        SOURCES = %i[confirm hotkey].freeze

        sealed_accessor :enabled
        # The Engine::Text drawn for this button, or nil.
        sealed_reader :label
        # The scope a label given as a key resolves under, or nil.
        sealed_reader :label_scope
        # `hotkey` is an action name, or nil.
        sealed_reader :activate_on, :hotkey

        def initialize(label: nil, enabled: true, activate_on: :release, hotkey: nil, **)
          super(**)
          unless ACTIVATE_ON.include?(activate_on)
            raise ArgumentError, "activate_on: must be :release or :press, not #{activate_on.inspect}"
          end

          @rgame_label_scope = nil
          self.label = label
          @rgame_enabled = enabled
          @rgame_activate_on = activate_on
          @rgame_hotkey = hotkey
          @rgame_focused = false
          @rgame_holder = nil
          @rgame_feedback = 0.0
        end

        # Sets the label: a key String or Symbol, which the button makes an
        # Engine::Text of under `label_scope`; a `Text`, used as it is; or nil.
        def label=(label)
          @rgame_label = label && text_for(label)
          @rgame_label_from_key = !(label.nil? || label.is_a?(Text))
        end

        # Sets the scope a label given as a key resolves under — `'title_menu'`
        # makes the key `'play'` read `'title_menu.play'` — and resolves it again
        # on the next draw.
        def label_scope=(scope)
          @rgame_label_scope = scope&.to_s
          @rgame_label.scope = @rgame_label_scope if @rgame_label_from_key
        end

        def enabled? = @rgame_enabled
        def focused? = @rgame_focused
        def pressed? = !@rgame_holder.nil? || @rgame_feedback.positive?

        # What to draw: `:disabled` whenever the button is disabled, whatever
        # else is true; then `:pressed`, `:focused`, and otherwise `:idle`.
        # Pressed does not require focus: a press can outlast the focus that
        # started it by its `PRESS_FEEDBACK`.
        def state
          return :disabled unless @rgame_enabled
          return :pressed if pressed?

          @rgame_focused ? :focused : :idle
        end

        # Called by the Menu. Calls `_gain_focus` or `_lose_focus` when the value actually
        # changes, and never for a repeated assignment, so a menu that reasserts
        # focus every frame does not replay a focus sound every frame. Losing
        # focus lets go of a confirm press without activating it; a hotkey press
        # was never about focus, and is kept.
        def focused=(value)
          return if @rgame_focused == value

          @rgame_focused = value
          @rgame_holder = nil if !value && @rgame_holder == :confirm
          value ? _gain_focus : _lose_focus
        end

        # Called by the Menu when a press from `source` — `:confirm` or
        # `:hotkey` — starts on this button. A hotkey press, or any press under
        # `activate_on: :press`, activates at once and returns what `activate`
        # did; a confirm press under `:release` holds and returns nil. Ignored,
        # returning nil, while disabled or while any source already holds it.
        def press(source = :confirm)
          unless SOURCES.include?(source)
            raise ArgumentError, "source must be :confirm or :hotkey, not #{source.inspect}"
          end
          return nil unless @rgame_enabled && @rgame_holder.nil?

          @rgame_holder = source
          return nil unless source == :hotkey || @rgame_activate_on == :press

          activate_with_feedback
        end

        # Called by the Menu when a press `source` started is let go. Activates
        # a confirm press under `activate_on: :release`, and returns what
        # `activate` did; ends nothing another source started.
        def release(source = :confirm)
          return nil unless @rgame_holder == source

          @rgame_holder = nil
          activate if source == :confirm && @rgame_activate_on == :release
        end

        # Called by the Menu for a press from `source` whose release this button
        # never saw. Drops it, and the feedback with it, activating nothing.
        def cancel_press(source = :confirm)
          return unless @rgame_holder == source

          @rgame_holder = nil
          @rgame_feedback = 0.0
        end

        # The instant press: activates, and shows pressed for `PRESS_FEEDBACK`
        # though nothing holds the button. What a hotkey press and a
        # `:press` confirm do, available on its own for a press that ends
        # somewhere other than on this button. Returns what `activate` did.
        def activate_with_feedback
          return nil unless @rgame_enabled

          @rgame_feedback = PRESS_FEEDBACK
          activate
        end

        # What the focused button does with `ui_left` / `ui_right`, which the
        # menu hands down without knowing what kind of button it is talking to.
        # A plain button has nothing to change, and answers nil the way a
        # disabled `activate` does. UI::OptionButton is the one that overrides it.
        def adjust(_delta) = nil

        # Whether this button's class overrides `adjust`: true for a
        # UI::OptionButton and for a game's own slider, false for every other
        # shipped button. A UI::FocusGroup crosses to the next menu on a
        # direction the focused button cannot adjust. Nil from `adjust` cannot
        # say that, since an OptionButton answers nil at the end of its values.
        def adjustable? = self.class.adjustable?

        # The same question asked of a class, worked out once per class. A
        # subclass therefore needs nothing more than the `adjust` it writes.
        def self.adjustable?
          @rgame_adjustable = !instance_method(:adjust).owner.equal?(Button) if @rgame_adjustable.nil?
          @rgame_adjustable
        end

        # Fires the signal and returns the button, or nil if it is disabled — so
        # a caller never has to check first, and a disabled button cannot be
        # activated by any route.
        def activate
          return nil unless @rgame_enabled

          activated_signal.emit
          self
        end

        # Counts down the pressed feedback, then does what every node does.
        def update(dt)
          @rgame_feedback -= dt if @rgame_feedback.positive? && !rgame_stopped?
          super
        end

        hook :_gain_focus, :_lose_focus

        # Hooks: override to react to gaining or losing focus — a sound, the
        # start of an animation. Each is called only on a change.
        def _gain_focus; end
        def _lose_focus; end

        private

        def text_for(shown) = shown.is_a?(Text) ? shown : Text.new(shown, scope: @rgame_label_scope)
      end
    end
  end
end
