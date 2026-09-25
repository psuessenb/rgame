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
    # It owns the list, polls every player's mapper once per tick, and decides
    # who a newly used controller belongs to. It does **not** own the screen
    # rects — those come from the layout, because they depend on how many
    # players are active and change without the players doing so.
    #
    # ## Seats, and how a device comes to occupy one
    #
    # Every seat exists from the start; the unfilled ones are inactive and draw
    # no viewport. So the number of seats is also the maximum number of players,
    # rather than a separate cap that could disagree with the list.
    #
    # **A device is seated when someone uses it, not when it is plugged in.** A
    # connect says something about hardware; seating a player creates a camera, a
    # viewport and a screen split, and that should follow a statement of intent.
    # Seating on connect drops a pad a solo player plugs in (no seat is free),
    # splits the screen when a spare pad wakes up, and cannot be refused during a
    # cutscene.
    #
    #   players.on_unassigned_input = :join   # :join | :takeover | :ignore
    #   players.accepting_joins = false       # temporarily refuse either
    #
    # - `:join` — a press on an unassigned device fills the next free seat.
    #   Couch co-op, and the default when a game asks for more than one seat.
    # - `:takeover` — it becomes the *primary* player's device instead. Single
    #   player, where picking up a controller is not a second person arriving,
    #   and the default when there is one seat.
    # - `:ignore` — the game seats devices itself, with #seat.
    #
    # The trigger is a **`ui_confirm` press**, read through the map of whoever
    # would receive the device. One action rather than "any input", because a
    # stick resting slightly off centre must never seat a player, and an edge
    # rather than held so one press does one thing.
    class Players < Component
      extend Engine::Signal::DSL

      Controls = RGame::Util::Controls

      include Collection.of(:@rgame_list)

      # Fires when a device is seated, with the player who got it. A scene
      # listens to spawn that player's avatar — which is how a game gains a
      # second character mid-session without polling for one.
      signal :joined, :player

      sealed_reader :list
      sealed_accessor :on_unassigned_input, :accepting_joins

      def initialize(players = [])
        super()
        @rgame_list = players
        @rgame_on_unassigned_input = players.size > 1 ? :join : :takeover
        @rgame_accepting_joins = true
        @rgame_connected = []
        @rgame_confirm_held = {}
        @rgame_everyone = Everyone.new(self)
      end

      # The player a single-player game means, and the one an unowned node reads
      # from. Always present: a game with no players declared still has this one,
      # which is what keeps single-player free of ceremony.
      def primary = @rgame_list.first

      def each(&) = @rgame_list.each(&)

      # Players with a device driving them. An empty seat waiting for a
      # controller is in `list` but not here, so a viewport loop skips it.
      def each_active
        return enum_for(:each_active) unless block_given?

        @rgame_list.each { |player| yield player if player.active? }
        self
      end

      def active_count = @rgame_list.count(&:active?)

      def [](id) = @rgame_list.find { |player| player.id == id }

      # An input owner standing for every active player: one controller whose
      # buttons are the OR of theirs. For a node no one player owns, such as a
      # dialogue box or a pause menu during `solo!`. See Players::Everyone.
      sealed_reader :everyone

      def add(player)
        @rgame_list << player
        player
      end

      # The input a node owned by `player` should read this tick.
      #
      # Nobody in particular means the primary player, which is what makes the
      # single-player path free: no node claims ownership, every node resolves
      # to nil, and every nil resolves to the one player there is.
      #
      # @api private
      # hot-path
      def actions_for(player)
        owner = player || primary
        raise 'no players are registered, so nothing can read input' if owner.nil?

        owner.actions
      end

      # Every player's input for this tick, in one call. `dt` is the timestep the
      # holds and taps in each player's map are measured against. Each player has
      # their own mapper and their own previous-frame state, so one player's
      # press cannot consume another's edge. `everyone` folds theirs together afterwards.
      # Then the devices nobody holds are checked for someone starting to use
      # one. Here rather than in a hot-plug hook because a *press* is a per-tick
      # idea, and this is the one place that already has the backend and runs
      # once a tick.
      def poll(backend, dt)
        @rgame_list.each { |player| player.poll(backend, dt) }
        @rgame_everyone.poll
        admit(backend)
        self
      end

      # A controller arrived in a slot. Recorded, not seated: this is what makes
      # the slot *scannable*, and someone using it is what seats it.
      #
      # @api private
      def device_connected(slot)
        @rgame_connected << slot unless @rgame_connected.include?(slot)
        self
      end

      # A controller left its slot. Whoever was on it loses it; their camera,
      # bindings and UI stay exactly as they were, so plugging back in and
      # pressing confirm resumes rather than restarts.
      #
      # Under `:takeover` there is no second player to become, so the seat falls
      # back to the keyboard rather than the game going dead in someone's hands.
      #
      # @api private
      def device_disconnected(slot)
        @rgame_connected.delete(slot)
        device = Controls.gamepad(slot)
        seated = @rgame_list.find { |player| player.device == device }
        seated&.device = @rgame_on_unassigned_input == :takeover ? Controls::KEYBOARD : nil
        seated
      end

      # Give `device` to whoever should have it, and say who that was. The join
      # path's own last step, and the one call a game running `:ignore` uses to
      # seat devices on its own terms.
      #
      # Refused while `accepting_joins` is false — which covers taking over as
      # well as joining, since both change who is holding what.
      def seat(device)
        return nil unless @rgame_accepting_joins

        player = candidate
        return nil if player.nil?

        player.device = device
        joined_signal.emit(player)
        player
      end

      private

      def admit(backend)
        return if @rgame_on_unassigned_input == :ignore || candidate.nil?

        each_unassigned_device do |device|
          down = confirm_down?(backend, device)
          was_down = @rgame_confirm_held[device]
          @rgame_confirm_held[device] = down
          seat(device) if down && !was_down
        end
      end

      def candidate
        return primary if @rgame_on_unassigned_input == :takeover

        @rgame_list.find { |player| !player.active? }
      end

      # hot-path
      def confirm_down?(backend, device)
        player = candidate
        return false if player.nil?

        buttons = player.input_map[:ui_confirm]&.buttons
        return false if buttons.nil?

        buttons.any? { |id| backend.down?(id, device: device) }
      end

      def each_unassigned_device
        @rgame_connected.each do |slot|
          device = Controls.gamepad(slot)
          yield device unless assigned?(device)
        end
        return unless @rgame_on_unassigned_input == :takeover && !assigned?(Controls::KEYBOARD)

        yield Controls::KEYBOARD
      end

      # hot-path
      def assigned?(device) = @rgame_list.any? { |player| player.device == device }
    end
  end
end
