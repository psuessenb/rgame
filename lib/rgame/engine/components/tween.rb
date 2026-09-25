# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # An Engine::Tween that rides its node's update and emits `on_finished`
      # once when it reaches the end. It is the one-shot: a banner that removes
      # itself, a projectile's lifetime, a hold before a page turns, a fade the
      # next scene waits for.
      #
      #   life = node.add_component(Engine::Components::Tween.new(2.0), as: :life)
      #   life.on_finished { node.queue_free }
      #
      #   fade = node.add_component(Engine::Components::Tween.new(0.5, from: 0, to: 255))
      #   alpha = fade.value   # in the node's _draw
      #
      # It starts in `_attach`, so a pooled node reacquired and added again
      # runs from the start rather than inheriting a spent one. `stop` holds it
      # at the start until `start`, for a wait that begins later than the node
      # does. A paused node holds it too, since time reaches it only through
      # `update`.
      #
      # For something that happens every N seconds, use Components::Timer.
      class Tween < Engine::Component
        signal :finished

        # Takes what Engine::Tween takes, but not `loop:`: a tween that loops
        # never finishes.
        def initialize(duration, from: 0.0, to: 1.0, ease: :linear)
          super()
          @rgame_tween = Engine::Tween.new(duration, from:, to:, ease:)
          @rgame_running = false
        end

        def duration = @rgame_tween.duration

        # Changes the duration, as Engine::Tween#duration= does.
        def duration=(seconds)
          @rgame_tween.duration = seconds
        end

        def value = @rgame_tween.value
        def progress = @rgame_tween.progress
        def done? = @rgame_tween.done?
        def running? = @rgame_running

        # Held at the start by `stop`, neither running nor done.
        def stopped? = !@rgame_running && !@rgame_tween.done?

        def _attach = start

        # Runs it from the start. A handler of `on_finished` may call it to run
        # again. Returns self.
        def start
          @rgame_tween.restart
          @rgame_running = true
          self
        end

        # Holds it at the start, emitting nothing, until `start`. Returns self.
        def stop
          @rgame_tween.restart
          @rgame_running = false
          self
        end

        # Jumps to the end and emits `on_finished`, as skipping a fade does.
        # Does nothing unless it is running. Returns self.
        def finish
          return self unless @rgame_running

          @rgame_tween.finish
          complete
          self
        end

        def _update(dt)
          return unless @rgame_running

          @rgame_tween.update(dt)
          complete if @rgame_tween.done?
        end

        private

        def complete
          @rgame_running = false
          finished_signal.emit
        end
      end
    end
  end
end
