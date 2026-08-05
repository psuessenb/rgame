# frozen_string_literal: true

module Engine
  module Components
    # Maps held input actions to an `on_triggered(action)` signal, rate-limited by a
    # per-action cooldown. One instance covers several actions (the engine allows
    # only one component of a class per node), so it emits the action name and lets
    # listeners filter — reusable for "fire" here, or "jump"/"fire" in a platformer.
    #
    #   trigger = node.add_component(ActionTrigger.new(fire: 0.22, dash: 0.5))
    #   trigger.on_triggered { |action| fire if action == :fire }
    #
    # Semantics: while an action is held and its cooldown has elapsed, it fires and
    # the cooldown restarts — i.e. auto-repeat at the cooldown rate.
    class ActionTrigger < Engine::Component
      signal :on_triggered, Engine::Signal.define(:action)

      def initialize(cooldowns)
        super()
        @cooldowns = cooldowns
        # action => seconds remaining until it may fire again (0 = ready).
        @timers = cooldowns.transform_values { 0.0 }
      end

      def update(dt)
        @timers.each { |action, remaining| @timers[action] = remaining - dt if remaining.positive? }
      end

      def control(actions)
        @cooldowns.each_key do |action|
          next unless actions.held?(action) && @timers[action] <= 0.0

          @timers[action] = @cooldowns[action]
          on_triggered_signal.emit(action)
        end
      end
    end
  end
end
