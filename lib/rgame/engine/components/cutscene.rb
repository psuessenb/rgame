# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Runs an Engine::Cutscene::Script on its node: each step in order, on
      # the node's update, from the moment the component attaches.
      #
      #   scene = add_component(Engine::Components::Cutscene.new(
      #     OPENING, context: self, camera: @camera, pause: heroes, skip: :skip
      #   ))
      #   scene.on_ended { |skipped| @cutscene = nil }
      #
      # **It takes what it stops, and gives it back.** As it starts, it
      # suspends each node in `pause:`. With `camera:`, everybody watches: it
      # solos the window through that camera onto its node's Scene::Room, stops
      # new players joining, and suspends every other running room. When it
      # ends, is skipped, or leaves the tree, it resumes each node and room and
      # puts the joins and the split back as they were. It suspends rather than
      # pauses, so a door that moves a hero it stopped, or a bag that pauses
      # one, gives back its own hold whenever it ends. A `run` step could be cut
      # off by a door, so no script undoes these itself.
      #
      # Without `camera:` it solos nothing and stops no room or join: a small
      # scene for the one player who walked into it, while the others play on.
      #
      # **It reads its node's player**, the primary one unless the game sets
      # `input_owner`, or every player for a node `Players#everyone` owns. A
      # `press` step waits for that player's press, and a press begun before
      # the cutscene started counts for neither it nor the skip.
      #
      # **`skip:` names an action the game declares with `hold:`**, so a player
      # has to mean it. Its press finishes the step under way, runs each
      # remaining step's skip in order, as Engine::Cutscene::Script lists them,
      # and ends. Without `skip:`, nothing skips it but a call to `skip`.
      #
      # `on_ended` fires once, with whether it was skipped, after everything is
      # given back. A cutscene that leaves the tree before its end gives
      # everything back and fires nothing.
      #
      # A running cutscene allocates nothing a tick. Starting a step may: a
      # step's block runs the game's code.
      class Cutscene < Engine::Component
        signal :ended, :skipped

        sealed_reader :script, :context, :camera

        # `script` is an Engine::Cutscene::Script and `context` what its blocks
        # are called with. `camera:` is the Camera everybody watches through, or
        # nil for a scene of one player's. `pause:` lists the nodes it stops.
        # `skip:` is the action that skips it, or nil.
        #
        # Raises `TypeError` for a script that is not a Script and a `skip:`
        # that is not a Symbol.
        def initialize(script, context: nil, camera: nil, pause: [], skip: nil)
          super()
          unless script.is_a?(Engine::Cutscene::Script)
            raise TypeError, "a cutscene runs an #{Engine::Cutscene::Script}, not #{script.inspect}"
          end
          raise TypeError, "skip: names an action, a Symbol, not #{skip.inspect}" unless skip.nil? || skip.is_a?(Symbol)

          @rgame_script = script
          @rgame_context = context
          @rgame_camera = camera
          @rgame_pause = Array(pause).dup.freeze
          @rgame_skip = skip
          @rgame_heard = proc { @rgame_step_done = true }
          reset
        end

        # Whether it has started and not yet ended.
        def running? = @rgame_running

        # Whether it ran to its end or was skipped.
        def ended? = @rgame_ended

        # The index of the step under way in the script's steps, nil when not
        # running.
        def step_index = @rgame_running ? @rgame_index : nil

        # Starts the script, taking what it stops. Raises `ArgumentError` when
        # `pause:` names the node the cutscene rides or one above it, since it
        # would then never run.
        def _attach
          reset
          refuse_pausing_itself
          take
          @rgame_running = true
          @rgame_index = 0
          begin_step
          advance while @rgame_running && @rgame_step_done
        end

        # Gives back everything it took, if it is still running, and fires
        # nothing.
        def _detach
          return unless @rgame_running

          release_step
          @rgame_running = false
          give_back
        end

        # hot-path
        def _control(actions)
          return unless @rgame_running

          @rgame_since = actions.poll_count if @rgame_since.equal?(UNSEEN)
          if @rgame_skip && fresh?(actions, @rgame_skip)
            @rgame_skip_asked = true
          else
            step = @rgame_script.steps[@rgame_index]
            @rgame_step_done = true if step.kind == :press && fresh?(actions, step.action)
          end
        end

        # hot-path
        def _update(dt)
          return unless @rgame_running
          return skip if @rgame_skip_asked

          step = @rgame_script.steps[@rgame_index]
          @rgame_elapsed += dt if step.kind == :wait
          @rgame_step_done = true if step.kind == :wait && @rgame_elapsed >= step.seconds
          advance while @rgame_running && @rgame_step_done
        end

        # Finishes the step under way, runs each remaining step's skip in order,
        # and ends, firing `on_ended` with true. Does nothing unless running.
        # Returns self.
        def skip
          return self unless @rgame_running

          finish_held
          release_step
          index = @rgame_index + 1
          while @rgame_running && index < @rgame_script.size
            skip_step(@rgame_script.steps[index])
            index += 1
          end
          conclude(true) if @rgame_running
          self
        end

        UNSEEN = Object.new.freeze
        private_constant :UNSEEN

        private

        def reset
          @rgame_running = false
          @rgame_ended = false
          @rgame_index = nil
          @rgame_step_done = false
          @rgame_skip_asked = false
          @rgame_elapsed = 0.0
          @rgame_held = nil
          @rgame_since = UNSEEN
        end

        def refuse_pausing_itself
          at = node
          while at
            if @rgame_pause.any? { it.equal?(at) }
              raise ArgumentError, "pause: names #{at.class}, which the cutscene rides, so it would never run. " \
                                   'Put the cutscene on a node pause: leaves running'
            end
            at = at.parent
          end
        end

        def take
          @rgame_pause.each(&:suspend)
          @rgame_stopped_rooms = []
          return unless @rgame_camera

          @rgame_room = node.scene.is_a?(Scene::Room) ? node.scene : nil
          take_the_window
          take_the_joins
          take_the_rooms
        end

        def take_the_window
          @rgame_viewports = node.system!(Engine::Viewports)
          @rgame_was_camera = @rgame_viewports.solo_camera
          @rgame_was_room = @rgame_viewports.solo_room
          @rgame_viewports.solo!(@rgame_camera, room: @rgame_room)
        end

        def take_the_joins
          @rgame_players = node.system(Engine::Players)
          return unless @rgame_players

          @rgame_was_joining = @rgame_players.accepting_joins
          @rgame_players.accepting_joins = false
        end

        def take_the_rooms
          rooms = node.system(Scene::Rooms)
          return unless rooms

          rooms.running.each do |room|
            next if room.equal?(@rgame_room)

            room.suspend
            @rgame_stopped_rooms << room
          end
        end

        def give_back
          @rgame_pause.each(&:resume)
          @rgame_stopped_rooms.each(&:resume)
          @rgame_stopped_rooms = []
          return unless @rgame_camera

          @rgame_players.accepting_joins = @rgame_was_joining if @rgame_players
          @rgame_was_camera ? @rgame_viewports.solo!(@rgame_was_camera, room: @rgame_was_room) : @rgame_viewports.split!
        end

        def advance
          release_step
          @rgame_index += 1
          return conclude(false) if @rgame_index >= @rgame_script.size

          begin_step
        end

        def begin_step
          step = @rgame_script.steps[@rgame_index]
          @rgame_step_done = false
          @rgame_elapsed = 0.0
          case step.kind
          when :run
            step.block.call(@rgame_context)
            @rgame_step_done = true
          when :hold then hold(step.block.call(@rgame_context))
          when :talk then talk(step.block.call(@rgame_context))
          end
        end

        def hold(held)
          checked_hold(held)
          @rgame_held = held
          @rgame_held.on_finished(&@rgame_heard)
          @rgame_step_done = true if held.respond_to?(:finished?) && held.finished?
        end

        def talk(dialogue)
          checked_talk(dialogue)
          @rgame_held = dialogue
          @rgame_held.on_ended(&@rgame_heard)
          @rgame_step_done = true if dialogue.ended?
        end

        def release_step
          return unless @rgame_held

          kind = @rgame_script.steps[@rgame_index].kind
          kind == :talk ? @rgame_held.disconnect_ended(@rgame_heard) : @rgame_held.disconnect_finished(@rgame_heard)
          @rgame_held = nil
        end

        def finish_held = @rgame_held&.finish

        def skip_step(step)
          case step.kind
          when :run then step.block.call(@rgame_context)
          when :hold then checked_hold(step.block.call(@rgame_context)).finish
          when :talk then checked_talk(step.block.call(@rgame_context)).finish
          end
        end

        def conclude(skipped)
          @rgame_running = false
          @rgame_ended = true
          give_back
          ended_signal.emit(skipped)
        end

        # hot-path
        def fresh?(actions, name)
          return false unless actions.pressed?(name)
          return true if @rgame_since.nil?

          since = actions.down_since(name)
          since.nil? || since > @rgame_since
        end

        def checked_hold(held)
          return held if held.respond_to?(:on_finished) && held.respond_to?(:finish)

          raise TypeError, "a hold step's block returns what it waits on, which answers on_finished and finish, " \
                           "not #{held.inspect}"
        end

        def checked_talk(dialogue)
          return dialogue if dialogue.respond_to?(:on_ended) && dialogue.respond_to?(:finish)

          raise TypeError, "a talk step's block returns the #{Engine::Dialogue} it put up, which answers on_ended " \
                           "and finish, not #{dialogue.inspect}"
        end
      end
    end
  end
end
