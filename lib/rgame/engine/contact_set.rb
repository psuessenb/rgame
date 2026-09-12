# frozen_string_literal: true

module RGame
  module Engine
    # The colliders one collider is touching, this step and last. CollisionWorld owns
    # one of these per registered collider and drives it, and together they are what
    # turns a per-step overlap test into the two edges a game actually wants: the step
    # a contact starts and the step it ends. Pure logic; no graphics.
    #
    # Nothing here is about overlapping, though, and it has a second user:
    # Components::CharacterBody keeps one of *what stopped its step*, and gets on_blocked
    # and on_unblocked out of it on exactly the same terms. What this class is, underneath
    # its names, is "the set of things that were true this step and last".
    #
    # Two arrays, swapped rather than reallocated. `begin_frame` makes this step's list
    # into last step's and empties the other one for refilling, so after the first few
    # frames nothing here allocates — `Array#clear` keeps the capacity it grew to, the
    # same trick SpatialHash#clear relies on.
    #
    # Membership is a linear scan by identity, and deliberately so. A Set or a Hash
    # allocates on insert, and both are slower than scanning a handful of entries; a
    # collider touching more than a handful of things at once is a design problem
    # somewhere else, not a reason to index this.
    class ContactSet
      def initialize
        @current = []
        @previous = []
      end

      # Start a step: this step's contacts become the ones to compare against, and the
      # list being filled is emptied. Swapped through a temporary rather than by
      # `@current, @previous = @previous, @current`, which would allocate an Array every
      # step — see .rubocop.yml on Style/SwapValues.
      def begin_frame
        filled = @current
        @current = @previous
        @previous = filled
        @current.clear
      end

      # Forget everything, both steps. CollisionWorld calls this when a collider
      # registers, so a pooled entity that died mid-contact cannot come back still
      # holding the contacts it had in its previous life — which would otherwise
      # surface as one spurious `on_separated` on its first step.
      def reset
        @current.clear
        @previous.clear
      end

      # Record a contact for this step.
      def add(other) = @current << other

      # Already recorded this step? The broadphase offers a pair once per cell the two
      # share, so this is what keeps one overlap from being counted twice.
      def touching?(other) = @current.include?(other)

      # Is this the *start* of a contact — a pair that was not touching last step? It
      # reads only last step's list, so it gives the same answer either side of #add,
      # and asking before recording is what reads as a guard.
      def started?(other) = !@previous.include?(other)

      # Yield every collider that was in contact last step and is not in contact now —
      # the ending edge. Call it once every pair for the step has been recorded.
      def each_ended
        i = 0
        while i < @previous.size
          other = @previous[i]
          i += 1
          yield other unless @current.include?(other)
        end
      end
    end
  end
end
