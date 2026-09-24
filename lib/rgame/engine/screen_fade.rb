# frozen_string_literal: true

module RGame
  module Engine
    # A rect of one colour over the whole view, fading in and out: the cover a
    # scene changes behind, and a storm's flash.
    #
    #   fade = add_node(Engine::ScreenFade.new(color: Util::Color::BLACK))   # clear, in :overlay
    #   fade.cover(0.4)                   # to opaque over 0.4 s, from where it is
    #   fade.reveal(0.4)                  # back to clear
    #   fade.flash(0.15, color: GLARE)    # up to GLARE and back down
    #   fade.finish                       # to where it was going, at once
    #   fade.on_finished { ... }
    #
    # **It fades by its own `opacity`.** It steps a tween in `_update` and
    # writes the value to `opacity`, and `Node2D#draw` fades the rect by it. So
    # it draws one colour it built once, and a clear fade draws nothing at all.
    #
    # It draws over the view it is drawn into, in the space its parent draws
    # in: the window at the root, one player's region under a PlayerLayer, and
    # the camera's view under a WorldView. Leave it at its parent's origin,
    # which is where it starts.
    #
    # It sits in the `:overlay` band, over the world and every player's HUD,
    # unless given another `band:`.
    #
    # `cover` and `reveal` start from the opacity the fade has, so a cover
    # begun halfway through a reveal turns back from there. A flash rises from
    # clear to its colour at half its duration, falls back to clear, and then
    # the fade draws in its own colour again. Each replaces whatever was
    # running, and `on_finished` fires once for the one that reaches its end.
    #
    # Time reaches it through `update`, so a paused fade holds where it is.
    class ScreenFade < Node2D
      # Fired once when a cover, a reveal or a flash reaches its end. One
      # replaced before its end fires nothing.
      signal :finished

      # The colour it covers in, and the colour a flash uses unless told
      # otherwise.
      attr_reader :color

      # Changes the colour a cover and a reveal draw in, one under way
      # included. A flash under way keeps its own colour until it ends. Anything
      # but a Util::Color raises `TypeError`.
      def color=(color)
        @color = checked_color(color)
        @drawn = @color unless @running.equal?(@flash)
      end

      # `color:` must be a Util::Color. Every other keyword is Node2D's.
      def initialize(color: Util::Color::BLACK, band: :overlay, **)
        super(band:, **)
        @color = checked_color(color)
        @drawn = @color
        @fade = Engine::Tween.new(1.0)
        @flash = Engine::Tween.new(1.0, ease: :arc)
        @running = nil
        self.opacity = 0
      end

      # Fades to opaque over `duration` seconds.
      def cover(duration) = fade_to(1.0, duration)

      # Fades to clear over `duration` seconds.
      def reveal(duration) = fade_to(0.0, duration)

      # Rises from clear to `color` at half of `duration`, then falls back to
      # clear. The colour's own alpha is the flash's peak, so a translucent
      # white flashes without covering.
      def flash(duration, color: @color)
        @flash.duration = duration
        @drawn = checked_color(color)
        run(@flash.restart)
      end

      # Jumps to where the cover, reveal or flash under way was going, and
      # emits `on_finished`, as its end does. A flash ends clear. Does nothing
      # when nothing is running. Returns self.
      def finish
        return self unless @running

        self.opacity = @running.finish.value.clamp(0.0, 1.0)
        complete
        self
      end

      # Whether a cover, a reveal or a flash is under way.
      def running? = !@running.nil?

      # Opaque, with nothing running: what a scene can change behind.
      def covered? = @running.nil? && opacity == 1

      def _update(dt)
        return unless @running

        self.opacity = @running.update(dt).value.clamp(0.0, 1.0)
        complete if @running.done?
      end

      def _draw(renderer, view)
        renderer.rect(view.origin_x, view.origin_y, view.width, view.height, color: @drawn)
      end

      private

      def complete
        @running = nil
        @drawn = @color
        finished_signal.emit
      end

      def fade_to(target, duration)
        @fade.duration = duration
        @fade.from = opacity
        @fade.to = target
        @drawn = @color
        run(@fade.restart)
      end

      def run(tween)
        @running = tween
        self
      end

      def checked_color(color)
        return color if color.is_a?(Util::Color)

        raise TypeError, "a ScreenFade's colour must be a #{Util::Color}, not #{color.inspect}"
      end
    end
  end
end
