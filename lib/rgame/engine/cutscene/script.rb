# frozen_string_literal: true

module RGame
  module Engine
    module Cutscene
      # The recipe for a cutscene: steps that run in order, each ending on
      # something the engine already says. `Components::Cutscene` runs one;
      # many can run the same script.
      #
      #   OPENING = Engine::Cutscene::Script.build do
      #     wait 0.5
      #     hold { |c| c.pan_to('square') }   # ends on what it returns emitting on_finished
      #     talk { |c| c.say(MAYOR) }          # ends on the Dialogue it returns emitting on_ended
      #     press                              # ends on ui_confirm
      #     press :carry_on                    # ends on the action named
      #     run { |c| c.open_gate }            # ends at once
      #   end
      #
      # Each block is called with the cutscene's `context:`, so a script holds
      # no game object and can be a constant.
      #
      # | Step | Ends when | A skip |
      # |---|---|---|
      # | `run` | at once | runs its block |
      # | `wait n` | `n` seconds have passed | ends it |
      # | `hold` | what its block returns emits `on_finished` | runs the block, then `finish`es what it returned |
      # | `talk` | the `Dialogue` its block returns emits `on_ended` | runs the block, then `finish`es the dialogue |
      # | `press` | the cutscene's player presses `ui_confirm`, or the action named | ends it |
      #
      # So a skipped cutscene leaves the world where watching it would have:
      # every `run` has run, and every walk and fade stands at its end. A
      # skipped `talk` ends where it stands, so an outcome that must hold
      # either way goes in a `run` after it.
      #
      # `build` checks each step as it is declared and freezes the script.
      class Script
        KINDS = %i[run wait hold talk press].freeze

        # One step: its `kind`, one of `KINDS`, the `seconds` a `wait` lasts,
        # the `action` a `press` waits for, and the `block` a `run`, `hold` or
        # `talk` calls.
        Step = Data.define(:kind, :seconds, :action, :block)

        # Builds a script from the block, which runs against a `Builder`, and
        # returns it frozen. Raises `ArgumentError` for a script with no steps
        # and for each step `Builder` refuses.
        def self.build(&block)
          raise ArgumentError, 'Script.build needs a block that declares the steps' unless block

          builder = Builder.new
          builder.instance_exec(&block)
          new(builder.steps)
        end

        private_class_method :new

        # The steps, in order, a frozen Array of `Step`s.
        attr_reader :steps

        def initialize(steps)
          raise ArgumentError, 'a cutscene script needs at least one step' if steps.empty?

          @steps = steps.dup.freeze
          freeze
        end

        # How many steps the script has.
        def size = @steps.size

        # What `Script.build`'s block runs against.
        class Builder
          # @api private
          attr_reader :steps

          def initialize
            @steps = []
          end

          # A step that calls its block and ends at once.
          def run(&block) = add(:run, block)

          # A step that ends after `seconds`, a positive number. Raises
          # `TypeError` for anything but a number, and `ArgumentError` for one
          # that is not positive.
          def wait(seconds)
            raise TypeError, "wait takes a number of seconds, not #{seconds.inspect}" unless seconds.is_a?(Numeric)
            raise ArgumentError, "wait takes a positive number of seconds, not #{seconds}" unless seconds.positive?

            @steps << Step.new(:wait, seconds.to_f, nil, nil)
            self
          end

          # A step that ends when what its block returns emits `on_finished`:
          # a `Components::Tween`, a `PathFollow`, a `ScreenFade`, or anything
          # else answering `on_finished` and `finish`.
          def hold(&block) = add(:hold, block)

          # A step that ends when the `Engine::Dialogue` its block returns
          # emits `on_ended`. The block puts up whatever shows the dialogue,
          # such as a `UI::DialogueBox`.
          def talk(&block) = add(:talk, block)

          # A step that ends when the cutscene's player presses `action`,
          # `ui_confirm` unless named. Takes no block. Raises `TypeError` for an
          # action that is not a Symbol.
          def press(action = :ui_confirm, &block)
            raise ArgumentError, 'press takes no block; it ends on a press of its action' if block
            raise TypeError, "press takes an action, a Symbol, not #{action.inspect}" unless action.is_a?(Symbol)

            @steps << Step.new(:press, nil, action, nil)
            self
          end

          private

          def add(kind, block)
            raise ArgumentError, "#{kind} needs a block, called with the cutscene's context" unless block

            @steps << Step.new(kind, nil, nil, block)
            self
          end
        end
      end
    end
  end
end
