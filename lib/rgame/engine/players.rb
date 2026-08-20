# frozen_string_literal: true

module RGame
  module Engine
    # Who is playing, as a root-scoped system.
    #
    #   players = node.system(Players)
    #   players.primary.camera
    #   players.each_active { |player| ... }
    #
    # A Component on the root node, so any node reaches it by walking the tree
    # rather than having it threaded through a constructor — the same shape
    # CollisionWorld and TileWorld use (see docs/api/systems.md).
    #
    # It owns the list, polls every player's mapper once per tick, and hands out
    # controllers as they are plugged in. It does **not** own the screen
    # rects — those come from the layout, because they depend on how many
    # players are active and change without the players doing so.
    class Players < Component
      Controls = RGame::Util::Controls

      include Enumerable

      attr_reader :list

      def initialize(players = [])
        super()
        @list = players
      end

      # The player a single-player game means, and the one an unowned node reads
      # from. Always present: a game with no players declared still has this one,
      # which is what keeps single-player free of ceremony.
      def primary = @list.first

      def each(&) = @list.each(&)

      # Players with a device driving them. An empty seat waiting for a
      # controller is in `list` but not here, so a viewport loop skips it.
      def each_active(&) = @list.select(&:active?).each(&)

      def active_count = @list.count(&:active?)

      def [](id) = @list.find { |player| player.id == id }

      def add(player)
        @list << player
        player
      end

      # The input a node owned by `player` should read this tick.
      #
      # Nobody in particular means the primary player, which is what makes the
      # single-player path free: no node claims ownership, every node resolves
      # to nil, and every nil resolves to the one player there is.
      # hot-path
      def actions_for(player)
        seat = player || primary
        raise 'no players are registered, so nothing can read input' if seat.nil?

        seat.actions
      end

      # Every player's input for this tick, in one call. Each has their own
      # mapper and their own previous-frame state, so one player's press cannot
      # consume another's edge.
      def poll(backend)
        @list.each { |player| player.poll(backend) }
        self
      end

      # Hand a newly connected controller to the first player waiting for one.
      #
      # Only seats with no device are filled, so a controller arriving never
      # takes the game away from someone already playing. A game that wants
      # "use the pad if there is one" starts its player with `device: nil`.
      # Returns the player who got it, or nil if nobody was waiting.
      def claim_gamepad(slot)
        waiting = @list.find { |player| !player.active? }
        waiting&.device = Controls.gamepad(slot)
        waiting
      end

      # A controller left its slot: whoever was on it becomes an empty seat
      # again. Their camera, bindings and UI stay exactly as they were, so
      # plugging back in resumes rather than restarts.
      def release_gamepad(slot)
        device = Controls.gamepad(slot)
        seated = @list.find { |player| player.device == device }
        seated&.device = nil
        seated
      end
    end
  end
end
