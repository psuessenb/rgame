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
      # `held`, `axes` and `prev_held` are mutable hashes the mapper updates in
      # place each poll, so the snapshot stays a single reused, allocation-free
      # object.
      def initialize(held: {}, axes: {}, prev_held: {})
        @held = held
        @axes = axes
        @prev_held = prev_held
      end

      # Every action this snapshot can answer for.
      def declared = @held.keys | @axes.keys

      # A snapshot is also a degenerate input *source*: it answers for whichever
      # player is asking, because there is only one answer. That is what lets
      # `node.control(actions)` keep working unchanged — a tree with nobody
      # claiming ownership, or a spec that has only one player in mind, passes
      # the snapshot itself where a Players registry would otherwise go.
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

      private

      # A block rather than `fetch(name)`'s bare KeyError, for a message that
      # says what to do about it. The block only runs on a miss, so the reading
      # path stays one hash lookup with nothing allocated.
      def undeclared(name)
        raise KeyError, "no such action #{name.inspect} — declare it in the InputMap " \
                        "(this snapshot has #{declared.inspect})"
      end

      # `prev_held` is read with a default on purpose. It is one frame behind, so
      # on the very first poll after an action is added it legitimately has no
      # entry, and "was not held before" is the right answer rather than an
      # error. The current-frame lookup above is what catches a typo.
    end
  end
end
