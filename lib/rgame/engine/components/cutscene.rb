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

        attr_reader :script, :context, :camera

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

          @script = script
          @context = context
          @camera = camera
          @pause = Array(pause).dup.freeze
          @skip = skip
          @heard = proc { @step_done = true }
          reset
        end

        # Whether it has started and not yet ended.
        def running? = @running

        # Whether it ran to its end or was skipped.
        def ended? = @ended

        # The index of the step under way in the script's steps, nil when not
        # running.
        def step_index = @running ? @index : nil

        # Starts the script, taking what it stops. Raises `ArgumentError` when
        # `pause:` names the node the cutscene rides or one above it, since it
        # would then never run.
        def _attach
          reset
          refuse_pausing_itself
          take
          @running = true
          @index = 0
          begin_step
          advance while @running && @step_done
        end

        # Gives back everything it took, if it is still running, and fires
        # nothing.
        def _detach
          return unless @running

          release_step
          @running = false
          give_back
        end

        # hot-path
        def _control(actions)
          return unless @running

          @since = actions.poll_count if @since.equal?(UNSEEN)
          if @skip && fresh?(actions, @skip)
            @skip_asked = true
          else
            step = @script.steps[@index]
            @step_done = true if step.kind == :press && fresh?(actions, step.action)
          end
        end

        # hot-path
        def _update(dt)
          return unless @running
          return skip if @skip_asked

          step = @script.steps[@index]
          @elapsed += dt if step.kind == :wait
          @step_done = true if step.kind == :wait && @elapsed >= step.seconds
          advance while @running && @step_done
        end

        # Finishes the step under way, runs each remaining step's skip in order,
        # and ends, firing `on_ended` with true. Does nothing unless running.
        # Returns self.
        def skip
          return self unless @running

          finish_held
          release_step
          index = @index + 1
          while @running && index < @script.size
            skip_step(@script.steps[index])
            index += 1
          end
          conclude(true) if @running
          self
        end

        UNSEEN = Object.new.freeze
        private_constant :UNSEEN

        private

        def reset
          @running = false
          @ended = false
          @index = nil
          @step_done = false
          @skip_asked = false
          @elapsed = 0.0
          @held = nil
          @since = UNSEEN
        end

        def refuse_pausing_itself
          at = node
          while at
            if @pause.any? { it.equal?(at) }
              raise ArgumentError, "pause: names #{at.class}, which the cutscene rides, so it would never run. " \
                                   'Put the cutscene on a node pause: leaves running'
            end
            at = at.parent
          end
        end

        def take
          @pause.each(&:suspend)
          @stopped_rooms = []
          return unless @camera

          @room = node.scene.is_a?(Scene::Room) ? node.scene : nil
          take_the_window
          take_the_joins
          take_the_rooms
        end

        def take_the_window
          @viewports = node.system!(Engine::Viewports)
          @was_camera = @viewports.solo_camera
          @was_room = @viewports.solo_room
          @viewports.solo!(@camera, room: @room)
        end

        def take_the_joins
          @players = node.system(Engine::Players)
          return unless @players

          @was_joining = @players.accepting_joins
          @players.accepting_joins = false
        end

        def take_the_rooms
          rooms = node.system(Scene::Rooms)
          return unless rooms

          rooms.running.each do |room|
            next if room.equal?(@room)

            room.suspend
            @stopped_rooms << room
          end
        end

        def give_back
          @pause.each(&:resume)
          @stopped_rooms.each(&:resume)
          @stopped_rooms = []
          return unless @camera

          @players.accepting_joins = @was_joining if @players
          @was_camera ? @viewports.solo!(@was_camera, room: @was_room) : @viewports.split!
        end

        def advance
          release_step
          @index += 1
          return conclude(false) if @index >= @script.size

          begin_step
        end

        def begin_step
          step = @script.steps[@index]
          @step_done = false
          @elapsed = 0.0
          case step.kind
          when :run
            step.block.call(@context)
            @step_done = true
          when :hold then hold(step.block.call(@context))
          when :talk then talk(step.block.call(@context))
          end
        end

        def hold(held)
          checked_hold(held)
          @held = held
          @held.on_finished(&@heard)
          @step_done = true if held.respond_to?(:finished?) && held.finished?
        end

        def talk(dialogue)
          checked_talk(dialogue)
          @held = dialogue
          @held.on_ended(&@heard)
          @step_done = true if dialogue.ended?
        end

        def release_step
          return unless @held

          kind = @script.steps[@index].kind
          kind == :talk ? @held.disconnect_ended(@heard) : @held.disconnect_finished(@heard)
          @held = nil
        end

        def finish_held = @held&.finish

        def skip_step(step)
          case step.kind
          when :run then step.block.call(@context)
          when :hold then checked_hold(step.block.call(@context)).finish
          when :talk then checked_talk(step.block.call(@context)).finish
          end
        end

        def conclude(skipped)
          @running = false
          @ended = true
          give_back
          ended_signal.emit(skipped)
        end

        # hot-path
        def fresh?(actions, name)
          return false unless actions.pressed?(name)
          return true if @since.nil?

          since = actions.down_since(name)
          since.nil? || since > @since
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
