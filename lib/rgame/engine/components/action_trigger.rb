# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Maps held input actions to an `on_triggered(action)` signal, rate-limited by a
      # per-action cooldown. One instance covers several actions and emits the action
      # name, so listeners filter — "fire" here, or "jump" and "fire" in a platformer.
      # Two triggers on one node would each need a slot of its own, named with `as:`.
      #
      #   trigger = node.add_component(ActionTrigger.new(fire: 0.22, dash: 0.5))
      #   trigger.on_triggered { |action| fire if action == :fire }
      #
      # Semantics: while an action is held and its cooldown has elapsed, it fires and
      # the cooldown restarts — i.e. auto-repeat at the cooldown rate.
      class ActionTrigger < Engine::Component
        signal :triggered, :action

        def initialize(cooldowns)
          super()
          @rgame_cooldowns = cooldowns
          @rgame_timers = cooldowns.transform_values { 0.0 }
        end

        def _update(dt)
          @rgame_timers.each { |action, remaining| @rgame_timers[action] = remaining - dt if remaining.positive? }
        end

        def _control(actions)
          @rgame_cooldowns.each_key do |action|
            next unless actions.held?(action) && @rgame_timers[action] <= 0.0

            @rgame_timers[action] = @rgame_cooldowns[action]
            triggered_signal.emit(action)
          end
        end
      end
    end
  end
end
