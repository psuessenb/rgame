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

      include Enumerable

      # Fires when a device is seated, with the player who got it. A scene
      # listens to spawn that player's avatar — which is how a game gains a
      # second character mid-session without polling for one.
      signal :on_joined, Engine::Signal.define(:player)

      attr_reader :list
      attr_accessor :on_unassigned_input, :accepting_joins

      def initialize(players = [])
        super()
        @list = players
        # One seat means there is no second player to become, so an unassigned
        # device is that player picking up a controller. More than one means the
        # game expects company.
        @on_unassigned_input = players.size > 1 ? :join : :takeover
        @accepting_joins = true
        @connected = []
        @confirm_held = {}
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
        owner = player || primary
        raise 'no players are registered, so nothing can read input' if owner.nil?

        owner.actions
      end

      # Every player's input for this tick, in one call. Each has their own
      # mapper and their own previous-frame state, so one player's press cannot
      # consume another's edge.
      # Then the devices nobody holds are checked for someone starting to use
      # one. Here rather than in a hot-plug hook because a *press* is a per-tick
      # idea, and this is the one place that already has the backend and runs
      # once a tick.
      def poll(backend)
        @list.each { |player| player.poll(backend) }
        admit(backend)
        self
      end

      # A controller arrived in a slot. Recorded, not seated: this is what makes
      # the slot *scannable*, and someone using it is what seats it.
      def device_connected(slot)
        @connected << slot unless @connected.include?(slot)
        self
      end

      # A controller left its slot. Whoever was on it loses it; their camera,
      # bindings and UI stay exactly as they were, so plugging back in and
      # pressing confirm resumes rather than restarts.
      #
      # Under `:takeover` there is no second player to become, so the seat falls
      # back to the keyboard rather than the game going dead in someone's hands.
      def device_disconnected(slot)
        @connected.delete(slot)
        device = Controls.gamepad(slot)
        seated = @list.find { |player| player.device == device }
        seated&.device = @on_unassigned_input == :takeover ? Controls::KEYBOARD : nil
        seated
      end

      # Give `device` to whoever should have it, and say who that was. The join
      # path's own last step, and the one call a game running `:ignore` uses to
      # seat devices on its own terms.
      #
      # Refused while `accepting_joins` is false — which covers taking over as
      # well as joining, since both change who is holding what.
      def seat(device)
        return nil unless @accepting_joins

        player = candidate
        return nil if player.nil?

        player.device = device
        on_joined_signal.emit(player)
        player
      end

      private

      # Watch the devices nobody is holding, and seat one when it is used.
      #
      # Costs nothing when there is nobody to seat: with every seat full, or the
      # policy set to ignore, there is no candidate and no device is looked at.
      def admit(backend)
        return if @on_unassigned_input == :ignore || candidate.nil?

        each_unassigned_device do |device|
          down = confirm_down?(backend, device)
          was_down = @confirm_held[device]
          @confirm_held[device] = down
          seat(device) if down && !was_down
        end
      end

      # Who the next unassigned device would go to, and therefore whose bindings
      # decide what counts as a press. Nil when nobody could take one.
      def candidate
        return primary if @on_unassigned_input == :takeover

        @list.find { |player| !player.active? }
      end

      # hot-path
      def confirm_down?(backend, device)
        player = candidate
        return false if player.nil?

        buttons = player.input_map[:ui_confirm]&.buttons
        return false if buttons.nil?

        buttons.any? { |id| backend.down?(id, device: device) }
      end

      # Connected pads nobody holds — plus the keyboard, but only while taking
      # over. The keyboard is always "connected", so under `:join` it would sit
      # waiting to seat whoever pressed Return, which is right for some games and
      # a surprise in most; one that wants a keyboard player seats it explicitly.
      def each_unassigned_device
        @connected.each do |slot|
          device = Controls.gamepad(slot)
          yield device unless assigned?(device)
        end
        return unless @on_unassigned_input == :takeover && !assigned?(Controls::KEYBOARD)

        yield Controls::KEYBOARD
      end

      # hot-path
      def assigned?(device) = @list.any? { |player| player.device == device }
    end
  end
end
