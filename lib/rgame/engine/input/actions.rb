# frozen_string_literal: true

module RGame
  module Engine
    # An immutable per-frame snapshot of abstract action state. Game logic reads
    # this, never physical keys. Built by ActionMapper (or constructed directly
    # in a spec).
    #
    # Edge queries (`pressed?`/`released?`) compare against the previous frame's
    # held state, so a one-shot action (menu confirm, jump) fires exactly once
    # per press rather than every frame it is held.
    #
    # A fourth query, `held_for`, answers how long an action's buttons have been
    # down. An action declared with `hold:` or `tap:` in the InputMap reads its
    # threshold through the ordinary three; `held_for` is for a game that wants
    # the number itself — a charge meter, a bar filling while a door is held
    # open.
    #
    # ## Reading an action nobody declared raises
    #
    # A game declares its actions once, in an InputMap. Asking for one that is
    # not in it is a typo, not a question with an answer, so it raises KeyError
    # rather than reading `false` forever:
    #
    #   actions.pressed?(:fyre)   # KeyError: no such action :fyre
    #
    # This matters because the failure it replaces is silent and remote. A
    # misspelled action reads as "never pressed", and what the player sees is a
    # button that does nothing — a bug that looks like it lives in the code that
    # *would* have run. RGame::Core::Input used to raise KeyError for an unbound
    # action and no longer can: it takes physical ids now, and binding moved up
    # to InputMap. This is where that guarantee went.
    #
    # **The hashes are the declaration.** ActionMapper seeds all three from its
    # map at construction, so every action the map knows answers and nothing
    # else does. A spec constructing one directly declares whatever it passes:
    #
    #   Actions.new(axes: { move_x: 1.0, move_y: 0.0 })   # both answer
    #   Actions.new(axes: { move_x: 1.0 }).axis(:move_y)  # KeyError
    #
    # That is stricter than it needs to be for a spec, and deliberately: a spec
    # that has not said what the action set is cannot claim a component reads
    # the right part of it.
    class Actions
      # `held`, `axes`, `prev_held`, `hold_times` and `down_since` are mutable
      # hashes the mapper updates in place each poll, so the snapshot stays a
      # single reused, allocation-free object. `poll_count` is 0 on a snapshot
      # that something polls, and nil on one built by hand.
      def initialize(held: {}, axes: {}, prev_held: {}, hold_times: {}, down_since: {}, poll_count: nil)
        @held = held
        @axes = axes
        @prev_held = prev_held
        @hold_times = hold_times
        @down_since = down_since
        @poll_count = poll_count
      end

      # Which poll this snapshot holds, counted from 1 by whatever polls it. It
      # is nil on a snapshot built by hand, which nothing polls.
      attr_reader :poll_count

      # Every action this snapshot can answer for.
      def declared = @held.keys | @axes.keys

      # A snapshot is also a degenerate input *source*: it answers for whichever
      # player is asking, because there is only one answer. That is what lets
      # `node.control(actions)` keep working unchanged — a tree with nobody
      # claiming ownership, or a spec that has only one player in mind, passes
      # the snapshot itself where a Players registry would otherwise go.
      #
      # @api private
      # hot-path
      def actions_for(_player) = self

      # hot-path
      def held?(name)
        @held.fetch(name) { undeclared(name) }
      end

      # True only on the frame the action transitions up→down.
      # hot-path
      def pressed?(name)
        @held.fetch(name) { undeclared(name) } && !@prev_held.fetch(name, false)
      end

      # True only on the frame the action transitions down→up.
      # hot-path
      def released?(name)
        !@held.fetch(name) { undeclared(name) } && @prev_held.fetch(name, false)
      end

      # Analog value in [-1.0, 1.0]; 0.0 for a declared action at rest.
      # hot-path
      def axis(name)
        @axes.fetch(name) { undeclared(name) }
      end

      # Seconds the action's buttons have been down, counted by the mapper from
      # the timestep it polls with. It is 0.0 at rest, and it survives the tick
      # of the release: a caller asking `released?(:door) && held_for(:door) > 1.0`
      # gets the length of the press that just ended. The tick after that, it is
      # 0.0 again.
      #
      # A snapshot built by hand answers only for the actions its `hold_times`
      # names, which is why a spec that reads it passes that hash.
      # hot-path
      def held_for(name)
        @hold_times.fetch(name) { undeclared(name) }
      end

      # The poll the action's buttons went down on, as a `poll_count`, or nil
      # at rest. It lasts until the press has no edge left to report: through
      # the tick of the release, and through the tick after a tap's release,
      # which reports the tap's `released?`. So every edge of a press reads the
      # poll it began on.
      #
      # A snapshot built by hand answers only for the actions its `down_since`
      # names.
      # hot-path
      def down_since(name)
        @down_since.fetch(name) { undeclared(name) }
      end

      # Moves `poll_count` on by one. The mapper that owns this snapshot calls it
      # as it polls.
      #
      # @api private
      def count_poll = @poll_count += 1

      private

      def undeclared(name)
        raise KeyError, "no such action #{name.inspect} — declare it in the InputMap " \
                        "(this snapshot has #{declared.inspect})"
      end
    end
  end
end
