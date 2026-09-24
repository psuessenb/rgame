# frozen_string_literal: true

module RGame
  module Engine
    module Scene
      # One cover, switch and reveal, run from a Scene::Fade: what a SceneStack
      # runs over the whole view, and what Scene::Rooms runs over each moving
      # player's region.
      #
      #   curtain = Curtain.new(host)
      #   curtain.close(fade)            # a switch was asked for: cover
      #   curtain.ready?                 # the switch may land: nothing covers, or the cover is complete
      #   curtain.open                   # it landed: reveal, if a cover was under way
      #   curtain.update(dt)
      #   curtain.draw(renderer, view)
      #
      # It holds a ScreenFade off `host`'s child list, naming `host` as its
      # parent, so the fade enters and leaves the tree with the host. The owner
      # draws it by calling #draw from wherever the fade belongs: over every
      # scene for the stack, and inside a player's region for the rooms.
      #
      # A close asked for during a cover keeps the cover under way. One asked
      # for during a reveal covers again from where the reveal got to, in the
      # running transition's durations when it names none of its own. With
      # `at_once:` the cover is opaque at once, for a host with nothing on
      # screen to cover.
      #
      # @api private
      class Curtain
        def initialize(host)
          @host = host
          @fade = nil
          @running = nil
          @phase = nil
        end

        # Starts covering with `transition`, a Scene::Fade or nil. See the class
        # comment for a close during a cover or a reveal.
        def close(transition, at_once: false)
          case @phase
          when :reveal then cover(transition || @running, at_once)
          when nil then cover(transition, at_once) if transition
          end
          self
        end

        # Whether a switch may land now: nothing covers, or the cover is opaque
        # and done.
        def ready? = @phase != :cover || @fade.covered?

        # Reveals, when the switch that just landed was covered.
        def open
          return self unless @phase == :cover

          @fade.reveal(@running.reveal)
          @phase = :reveal
          self
        end

        # Whether a cover is under way or complete, and not yet revealing.
        def covering? = @phase == :cover

        # Whether a cover or a reveal is under way.
        def running? = !@phase.nil?

        # hot-path
        def update(dt)
          return unless @phase

          @fade.update(dt)
          @phase = nil if @phase == :reveal && !@fade.running?
        end

        # hot-path
        def draw(renderer, view)
          @fade&.draw(renderer, view)
        end

        private

        def cover(transition, at_once)
          @running = transition
          fade.color = transition.color
          if at_once
            fade.opacity = 1
          else
            fade.cover(transition.cover)
          end
          @phase = :cover
        end

        def fade
          @fade ||= Engine::ScreenFade.new.tap do |built|
            built.parent = @host
            built.enter_tree
          end
        end
      end
    end
  end
end
