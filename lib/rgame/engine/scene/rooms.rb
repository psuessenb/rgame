# frozen_string_literal: true

module RGame
  module Engine
    module Scene
      # The rooms of one world, each running while a player stands in it, so two
      # players can stand in two rooms at once.
      #
      #   class World < RGame::Engine::Node2D     # the scene the stack holds
      #     def initialize
      #       super
      #       @rooms = add_component(RGame::Engine::Scene::Rooms.new)
      #       @rooms.define(:town) { Town.new }
      #       @rooms.define(:garden) { Garden.new }
      #       @rooms.transition = RGame::Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)
      #     end
      #   end
      #
      #   rooms.move(hero, to: :garden, entrance: 'gate_in')   # one hero, under its player's cover
      #   rooms.move(heroes, to: :town, entrance: 'square')    # every hero given, from whichever room
      #   rooms.room_of(player)                                # => the Room they stand in, or nil
      #   rooms[:garden]                                       # => the running Room of that name, or nil
      #   rooms.hold(:garden)                                  # runs with nobody in it, until released
      #
      # Each room is a Scene::Room, built by the block given to #define, and
      # built anew each time it starts running. What should outlast a visit
      # lives in `FactsDatabase`, as a loaded save's state does.
      #
      # **A move lands in the sweep**, as a SceneStack's switch does. `move`
      # records what was asked, suspends each node it names and each moving
      # player's input, and covers each moving player's region. Once a player's
      # cover is complete, the sweep takes each of their nodes from its parent,
      # builds the room if it is not running, and hands the node to the room's
      # `_arrive`. Then the cover reveals. Once the reveal ends, the node and
      # its player's input resume. The move never touches a node's `paused`,
      # so a bag that pauses its hero, or a cutscene that suspends it, keeps
      # its hold whenever the move ends. A move to the
      # room a node stands in is a warp: `_arrive` places the node again and
      # nothing leaves the tree.
      #
      # **A moving player reads no input anywhere**, as no scene does under a
      # stack's transition. A bag or a pause menu of theirs outside the rooms
      # reads nothing held until the reveal ends, and refuses a press begun
      # under the cover, so nothing of theirs acts on a screen they cannot see.
      #
      # **A node's player** is the one its `input_owner` names, looked up
      # through its parents, and the primary player when none does. A move
      # covers that player's region only, and makes them stand in the room the
      # node goes to. A node owned by `Players#everyone` has no one player: it
      # moves under no cover, and stands nobody anywhere.
      #
      # **A room runs while a player stands in it, or while #hold holds it.**
      # The sweep frees one that has neither, and nothing on its way to it.
      # Each running room is controlled, updated and drawn once a tick, in the
      # order the rooms were built. The rooms live off the host's child list,
      # each naming the host as its parent and marked as its own scene.
      #
      # **A player's camera takes the limits of the room they stand in.** As a
      # move lands, each player's camera is bounded by their room's TileWorld,
      # whichever cameras that room handed its own.
      #
      # **A room defined with `music:` claims its song** on the AudioOut, at the
      # room's `priority:`, while a player stands in it or is on their way to
      # it:
      #
      #   rooms.define(:town, music: 'town.ogg', priority: 1) { Town.new }
      #   rooms.define(:garden, music: 'garden.ogg', priority: 2) { Garden.new }
      #
      # The claims change as a move is asked for, so a new song crossfades over
      # the move's cover and reveal together, or over the reveal alone for a
      # player in no room, whose cover is complete from the start. The key a
      # room claims under is its own, and no game can release it. The rooms
      # release every claim at once as their node leaves the tree.
      class Rooms < Engine::Component
        # Fired once for each node a move names, as the move is asked for, with
        # the node and the name of the room it goes to.
        signal :requested, :node, :name

        # Fired once for each node as its move lands, after the room's
        # `_arrive` placed it.
        signal :arrived, :node, :room

        Move = Data.define(:node, :name, :entrance, :player)
        Held = Data.define(:node, :player)
        Song = Data.define(:key, :id, :priority)
        private_constant :Move, :Held, :Song

        # The key a room's song is claimed under. No game holds one, so no game
        # can release a room's claim.
        class Claim
          def initialize(name) = @name = name
          def inspect = "the room #{@name.inspect}"
        end
        private_constant :Claim

        # One player's region, covered by a curtain of its own.
        class Cover < Engine::PlayerLayer
          sealed_reader :curtain

          def initialize(player:)
            super
            @rgame_curtain = Curtain.new(self)
          end

          def _draw(renderer, view) = @rgame_curtain.draw(renderer, view)
        end
        private_constant :Cover

        # The Scene::Fade a move runs unless it names its own, or nil, the
        # default, for none.
        sealed_reader :transition

        def initialize
          super
          @rgame_builders = {}
          @rgame_running = []
          @rgame_by_name = {}
          @rgame_room_of = {}
          @rgame_holds = {}
          @rgame_moves = []
          @rgame_held = []
          @rgame_suspended = {}
          @rgame_covers = {}
          @rgame_transition = nil
          @rgame_players = nil
          @rgame_songs = {}
          @rgame_claimed = {}
          @rgame_out = nil
        end

        # Sets the transition every move runs unless it names its own. Anything
        # but a Scene::Fade or nil raises `TypeError`.
        def transition=(transition)
          @rgame_transition = checked_transition(transition)
        end

        # See SceneStack#_attach: the rooms need the input source, not the one
        # snapshot a component is handed.
        def _attach = @rgame_players = node.system(Engine::Players)

        # Releases every song the rooms claim, at once, and resumes every node
        # and every player's input a move had suspended.
        def _detach
          @rgame_held.each { it.node.resume }
          @rgame_held.clear
          @rgame_suspended.each_key(&:resume_input)
          @rgame_suspended.clear
          @rgame_out&.release_music(*@rgame_claimed.keys.map { @rgame_songs[it].key })
          @rgame_claimed.clear
          @rgame_out = nil
        end

        # Names a room. The block builds a new Scene::Room each time the room
        # starts running, and takes no parameters. A name is defined once.
        #
        # `music:` is the song the room claims at `priority:` while a player
        # stands in it or is on their way to it. nil, the default, claims
        # nothing.
        def define(name, music: nil, priority: 0, &builder)
          raise TypeError, "a room's name is a Symbol, not #{name.inspect}" unless name.is_a?(Symbol)
          raise ArgumentError, "define(#{name.inspect}) needs a block that builds the room" unless builder
          raise ArgumentError, "a room named #{name.inspect} is already defined" if @rgame_builders.key?(name)
          unless builder.parameters.empty?
            raise ArgumentError, "the builder for #{name.inspect} takes parameters, and a room's builder takes " \
                                 'none. What a room needs to know lives in the facts database, or reaches it in _arrive'
          end

          raise TypeError, "a room's priority is a number, not #{priority.inspect}" unless priority.is_a?(Numeric)

          @rgame_builders[name] = builder
          @rgame_songs[name] = Song.new(Claim.new(name), music, priority) if music
          self
        end

        # Asks for `nodes`, one node or an Array of them, to go to the room named
        # `to`, at `entrance`, which reaches the room's `_arrive` as it is. A name
        # the rooms were not given raises `KeyError` here.
        #
        # `transition:` is a Scene::Fade for this move in place of the rooms',
        # or nil for none. A second move asked for a node before its first
        # lands replaces the first.
        def move(nodes, to:, entrance: nil, transition: @rgame_transition)
          named_for(to)
          transition = checked_transition(transition)
          if nodes.is_a?(Array)
            nodes.all? { checked_node(it) }
            claim_songs(nodes.map { ask(it, to, entrance, transition) }.max || 0)
            nodes.each { requested_signal.emit(node: it, name: to) }
          else
            claim_songs(ask(checked_node(nodes), to, entrance, transition))
            requested_signal.emit(node: nodes, name: to)
          end
          self
        end

        # The room `player` stands in, or nil.
        def room_of(player) = @rgame_room_of[player]

        # The running room named `name`, or nil.
        def [](name) = @rgame_by_name[name]

        # The running rooms, in the order they were built. The rooms keep the
        # list: read it, and leave it alone.
        sealed_reader :running

        # Keeps the room named `name` running with nobody in it, from the next
        # sweep until #release. Builds it then if it is not running.
        def hold(name)
          named_for(name)
          @rgame_holds[name] = true
          self
        end

        # Ends a #hold. A room nobody stands in is freed in the next sweep.
        def release(name)
          @rgame_holds.delete(name)
          self
        end

        # Whether a move was asked for and has not landed.
        def pending? = !@rgame_moves.empty?

        # Whether any player's cover is covering or revealing.
        def transitioning? = @rgame_covers.any? { |_, cover| cover.curtain.running? }

        # hot-path
        def _control(actions)
          input = @rgame_players || actions
          @rgame_running.each { it.control(input) }
        end

        # hot-path
        def _update(dt)
          @rgame_covers.each_value { it.curtain.update(dt) }
          restore_moved unless @rgame_held.empty? && @rgame_suspended.empty?
          @rgame_running.each { it.update(dt) }
        end

        # hot-path
        def _draw(renderer, view)
          @rgame_running.each { it.draw(renderer, view) }
          @rgame_covers.each_value { it.draw(renderer, view) }
        end

        # The sweep reaches into each running room, lands every move whose
        # cover is complete, then builds the rooms a hold asks for and frees the
        # rooms nobody needs.
        def _sweep_freed
          @rgame_running.each(&:sweep_freed)
          land_ready unless @rgame_moves.empty?
          settle_rooms if settling?
        end

        private

        def ask(moving, name, entrance, transition)
          player = player_of(moving)
          @rgame_moves.delete_if { it.node.equal?(moving) }
          @rgame_moves << Move.new(moving, name, entrance, player)
          hold_still(moving, player)
          suspend(player) if player
          at_once = player && @rgame_room_of[player].nil?
          cover = transition ? cover_for(player) : @rgame_covers[player] if player
          cover&.curtain&.close(transition, at_once:)
          return 0 unless transition

          at_once ? transition.reveal : transition.cover + transition.reveal
        end

        def claim_songs(fade)
          return if @rgame_songs.empty?

          @rgame_out ||= node.system!(Engine::AudioOut)
          @rgame_songs.each do |name, song|
            next if @rgame_claimed.key?(name) || !wanted?(name)

            @rgame_claimed[name] = true
            @rgame_out.claim_music(song.key, song.id, priority: song.priority, fade:)
          end
          left = @rgame_claimed.keys.reject { wanted?(it) }
          left.each { @rgame_claimed.delete(it) }
          @rgame_out.release_music(*left.map { @rgame_songs[it].key }, fade:) unless left.empty?
        end

        def wanted?(name)
          @rgame_moves.any? { |move| move.player && move.name == name } ||
            @rgame_room_of.any? { |player, room| room.name == name && @rgame_moves.none? { it.player.equal?(player) } }
        end

        def player_of(moving)
          owner = nil
          at = moving
          while at && owner.nil?
            owner = at.input_owner
            at = at.parent
          end
          owner ||= @rgame_players&.primary
          owner.is_a?(Engine::Players::Everyone) ? nil : owner
        end

        def cover_for(player)
          @rgame_covers[player] ||= Cover.new(player:).tap do |cover|
            cover.parent = node
            cover.enter_tree
          end
        end

        def hold_still(moving, player)
          return if @rgame_held.any? { it.node.equal?(moving) }

          @rgame_held << Held.new(moving, player)
          moving.suspend
        end

        def suspend(player)
          @rgame_suspended[player] = player.suspend_input unless @rgame_suspended.key?(player)
        end

        def restore_moved
          @rgame_held.delete_if do |entry|
            next false if moving?(entry.node) || covered?(entry.player)

            entry.node.resume
            true
          end
          @rgame_suspended.delete_if do |player, _|
            next false if @rgame_moves.any? { it.player.equal?(player) } || covered?(player)

            player.resume_input
            true
          end
        end

        def moving?(moving) = @rgame_moves.any? { it.node.equal?(moving) }

        def covered?(player) = !player.nil? && @rgame_covers[player]&.curtain&.running? == true

        def land_ready
          @rgame_moves.delete_if do |move|
            next false unless ready?(move)

            land(move)
            true
          end
          bound_cameras
          @rgame_covers.each do |player, cover|
            cover.curtain.open unless @rgame_moves.any? { it.player.equal?(player) }
          end
          restore_moved
        end

        def ready?(move)
          move.player.nil? || @rgame_covers[move.player].nil? || @rgame_covers[move.player].curtain.ready?
        end

        def land(move)
          room = @rgame_by_name[move.name] || build(move.name)
          moving = move.node
          moving.parent&.remove_node(moving) unless inside?(moving, room)
          room._arrive(moving, move.entrance)
          unless inside?(moving, room)
            raise "#{room.class}#_arrive left #{moving.class} outside the room. Add it to a node in the room"
          end

          stand(move.player, room) if move.player
          arrived_signal.emit(node: moving, room:)
        end

        def inside?(moving, room)
          at = moving.parent
          at = at.parent until at.nil? || at.equal?(room)
          !at.nil?
        end

        def stand(player, room)
          @rgame_room_of[player]&.players&.delete(player)
          room.players << player unless room.players.include?(player)
          @rgame_room_of[player] = room
        end

        def build(name)
          room = @rgame_builders.fetch(name).call
          unless room.is_a?(Room)
            raise TypeError, "the builder for #{name.inspect} built a #{room.class}, and a room is a #{Room}"
          end

          room.name = name
          @rgame_running << room
          @rgame_by_name[name] = room
          room.parent = node
          room.scene = room
          room.enter_tree
          room
        end

        def free(room)
          @rgame_running.delete(room)
          @rgame_by_name.delete(room.name)
          room.exit_tree
          room.scene = nil
          room.parent = nil
        end

        def settling?
          @rgame_running.any? { |room| !needed?(room) } || @rgame_holds.any? { |name, _| !@rgame_by_name.key?(name) }
        end

        def settle_rooms
          @rgame_holds.each_key { |name| build(name) unless @rgame_by_name.key?(name) }
          @rgame_running.dup.each { |room| free(room) unless needed?(room) }
        end

        def needed?(room)
          !room.players.empty? || @rgame_holds.key?(room.name) || @rgame_moves.any? { it.name == room.name }
        end

        def bound_cameras
          @rgame_room_of.each do |player, room|
            world = room.get_component(Components::TileWorld)
            world&.bound(player.camera) if player.camera
          end
        end

        def named_for(name)
          @rgame_builders.fetch(name) do
            raise KeyError.new("there is no room named #{name.inspect}. Name it first: " \
                               "define(#{name.inspect}) { ... }", receiver: @rgame_builders, key: name)
          end
        end

        def checked_node(moving)
          return moving if moving.respond_to?(:enter_tree)

          raise TypeError, "a move takes a node or an Array of nodes, not #{moving.inspect}"
        end

        def checked_transition(transition)
          return transition if transition.nil? || transition.is_a?(Fade)

          raise TypeError, "a transition is a #{Fade} or nil, not #{transition.inspect}"
        end
      end
    end
  end
end
