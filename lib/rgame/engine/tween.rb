# frozen_string_literal: true

module RGame
  module Engine
    # A value moving from one number to another over a duration: a fade, a
    # camera move, a jump's arc, a delay before a hint appears.
    #
    #   @fade = Engine::Tween.new(0.5, from: 0, to: 255, ease: :in_out)   # built once
    #   @fade.update(dt)                                                  # in _update
    #   alpha = @fade.value                                               # in _draw
    #   start_game if @fade.done?
    #
    # Time enters only through `update`, so a paused owner freezes it mid-way
    # and a spec asks for the value at 0.25 s by passing 0.25. It is pure and
    # allocates nothing, so it runs on the per-frame path, and `restart`
    # reuses it rather than building another.
    #
    # `ease:` shapes the way from `from` to `to`. It is one of EASES, or any
    # object answering `call(t)` for a `t` from 0 to 1. An ease need not end
    # at 1: `:arc` rises to `to` halfway and comes back to `from`, which is a
    # jump.
    #
    # With `loop: true` it starts again each time it reaches the end, carrying
    # the overshoot, and is never done: a playhead, a pulse.
    #
    # Engine::Timer answers a different question. A tween says how far along
    # something is; a timer counts how many whole intervals have passed.
    # Components::Tween drives one on a node and emits `on_finished`.
    class Tween
      EASES = {
        linear: ->(t) { t },
        in: ->(t) { t * t },
        out: ->(t) { t * (2.0 - t) },
        in_out: ->(t) { t * t * (3.0 - (2.0 * t)) },
        arc: ->(t) { 4.0 * t * (1.0 - t) }
      }.freeze

      attr_reader :duration, :ease

      # Where the value starts and ends. Either may change mid-way, as a
      # camera move retargets.
      attr_accessor :from, :to

      # `duration` is in seconds and must be positive. `ease:` is a key of
      # EASES or a callable; anything else raises ArgumentError.
      def initialize(duration, from: 0.0, to: 1.0, ease: :linear, loop: false)
        self.duration = duration
        @from = from
        @to = to
        @ease = ease
        @curve = curve_for(ease)
        @loop = loop
        @elapsed = 0.0
      end

      # Changes the duration and keeps the time elapsed, so a longer duration
      # sets a finished tween running again. Must be positive.
      def duration=(seconds)
        unless seconds.is_a?(Numeric) && seconds.positive?
          raise ArgumentError, "duration must be a positive number of seconds, not #{seconds.inspect}"
        end

        @duration = seconds
      end

      def loop? = @loop

      # Advances by one timestep, stopping at the end unless it loops. Returns
      # self.
      def update(dt)
        @elapsed += dt
        @elapsed = @loop ? @elapsed % @duration : @duration if @elapsed >= @duration
        self
      end

      # How far along it is, from 0 at the start to 1 at the end, before the
      # ease.
      def progress = @elapsed >= @duration ? 1.0 : @elapsed / @duration

      # The eased value between `from` and `to`.
      def value = @from + ((@to - @from) * @curve.call(progress))

      # Whether it has reached the end. Never true for a tween that loops.
      def done? = !@loop && @elapsed >= @duration

      # Jumps to the end, as skipping a fade does. Returns self.
      def finish
        @elapsed = @duration
        self
      end

      # Back to the start, to run again. Returns self.
      def restart
        @elapsed = 0.0
        self
      end

      private

      def curve_for(ease)
        return EASES.fetch(ease) if EASES.key?(ease)
        return ease if ease.respond_to?(:call)

        raise ArgumentError, "ease: must be one of #{EASES.keys.inspect} or respond to call, not #{ease.inspect}"
      end
    end
  end
end
