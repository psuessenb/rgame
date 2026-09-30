# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Takes its node out of play for `duration` seconds, then brings it back. It
      # suspends the node and shows its Components::FallLook, if it has one. At the
      # end it hands the node to its Respawn, or frees a node with none.
      #
      #   fall = hero.add_component(Fall.new)
      #   hero.add_component(Shrink.new)
      #   hero.add_component(Respawn.new)
      #   fall.start
      #
      # A game or a cutscene starts one with #start, wherever the node stands. It
      # answers `on_finished` and #finish, so a cutscene's `hold` step waits on
      # it, and a skip ends it as its end would.
      #
      # **Each piece is the game's to add.** A node with no look holds still at
      # its scale while it falls, and a node with no Respawn is freed. The fall
      # looks the look up after `on_fell`, and the Respawn as it ends, so no add
      # order matters. A game decides both in `on_fell`: a look it adds there
      # shows, and a Respawn it removes there frees the node. A fall started on a
      # platform leaves it: the node's Footing lets it go.
      #
      # The fall runs from a Clock this keeps for its life, lent to the node's
      # parent for each fall, because a suspended node stops its own components.
      # So a fall pauses with the world around the node, and a fall allocates
      # nothing. A node taken out of the tree mid-fall, through a door or freed,
      # stops falling at once, resumed, with its look finished, and `on_finished`
      # does not fire.
      class Fall < Engine::Component
        # Fired as the fall starts, which is where a game takes a life.
        signal :fell

        # Fired once the fall has ended: the node stands on its respawn point, or
        # is freed.
        signal :finished

        # Seconds the fall takes, from its start to the respawn.
        sealed_reader :duration

        # `duration` must be a positive number of seconds, or it raises
        # ArgumentError.
        def initialize(duration: 0.4)
          super()
          unless duration.is_a?(Numeric) && duration.positive?
            raise ArgumentError, "duration must be a positive number of seconds, not #{duration.inspect}"
          end

          @rgame_duration = duration
          @rgame_progress = Engine::Tween.new(duration)
          @rgame_clock = Clock.new(self)
          @rgame_falling = false
          @rgame_look = nil
        end

        # Starts a fall, and returns self. Does nothing during a fall. Raises for a
        # node outside the tree, which has no parent to run the fall from, and for a
        # node with two FallLooks.
        def start
          return self if @rgame_falling

          refuse_outside_tree
          node.get_component(Footing)&.leave_platform
          @rgame_falling = true
          @rgame_progress.restart
          node.suspend
          @rgame_clock = Clock.new(self) if @rgame_clock.freed? && @rgame_clock.parent
          node.parent.add_node(@rgame_clock)
          fell_signal.emit
          start_look if @rgame_falling
          self
        end

        # Ends a fall under way as its end would: the node comes back or is freed.
        # Does nothing when none is under way. Returns self.
        def finish
          land if @rgame_falling
          self
        end

        def falling? = @rgame_falling

        # Ends a fall under way, with no respawn and no `on_finished`, as the node
        # leaves the tree or the Fall leaves the node.
        def _detach
          end_fall if @rgame_falling
        end

        # Moves the fall on by `dt` seconds: shows the look, and ends the fall once
        # `duration` has run. The Clock calls it.
        #
        # @api private
        # hot-path
        def advance(dt)
          return unless @rgame_falling

          @rgame_progress.update(dt)
          look = shown_look
          look&.show(@rgame_progress.progress)
          land if @rgame_progress.done?
        end

        # The node a Fall lends to its node's parent for each fall. It updates while
        # the falling node is suspended, and pauses when the parent does.
        #
        # @api private
        class Clock < Engine::Node2D
          def initialize(fall)
            super()
            @rgame_fall = fall
          end

          def _update(dt)
            @rgame_fall.advance(dt) unless freed?
          end
        end

        private

        def refuse_outside_tree
          return if node&.in_tree? && node.parent

          raise "#{self.class} runs a fall from its node's parent, so it starts only on a node in the tree " \
                'with a parent.'
        end

        def start_look
          @rgame_look = find_look
          @rgame_look&.start
        end

        def find_look
          found = nil
          node.components.each do |component|
            next unless component.is_a?(FallLook)
            if found
              raise ArgumentError, "#{node.class} has two FallLooks, #{found.class} and #{component.class}, and " \
                                   'a Fall shows one. Keep one of them on the node.'
            end

            found = component
          end
          found
        end

        def shown_look
          look = @rgame_look
          return look if look.nil? || look.node.equal?(node)

          @rgame_look = nil
        end

        def land
          fallen = node
          end_fall
          respawn = fallen.get_component(Respawn)
          respawn ? respawn.respawn : fallen.queue_free
          finished_signal.emit
        end

        def end_fall
          @rgame_falling = false
          node.resume
          @rgame_clock.queue_free
          shown_look&.finish
          @rgame_look = nil
        end
      end
    end
  end
end
