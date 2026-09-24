# frozen_string_literal: true

module RGame
  module Engine
    # One person playing: their device, their bindings, their camera, and their
    # own corner of the screen.
    #
    #   player = Player.new(id: 0, device: Controls.gamepad(0))
    #   player.actions.held?(:fire)   # what they are doing this tick
    #   player.camera                 # where they are looking
    #   player.ui                     # their HUD and menus, in screen space
    #
    # ## Why the player owns these and the scene does not
    #
    # A world has one simulation and any number of viewers. Two players share
    # every NPC and every tile, but not a camera, not a set of bindings, and not
    # a menu — so those belong to the viewer. Putting the camera on the scene
    # works exactly until there are two of them, and putting it on a node in the
    # world is worse: it forces the world to know how many times it is drawn.
    #
    # This is the model Unreal calls a LocalPlayer and Unity spreads across
    # PlayerInput plus a camera.
    #
    # ## The action *names* are shared, the bindings are not
    #
    # Every player reads `:fire`. What triggers it is per player: one on Space,
    # one on a pad's X button, and the same InputMap can serve both because a
    # device only answers for its own kind of input. Each player gets their own
    # ActionMapper, so their edge queries are independent — one player's press
    # cannot consume another's.
    #
    # ## Input can be suspended
    #
    # `suspend_input` makes `actions` read as nothing held, for every node that
    # answers to this player, until `resume_input` is called as often. The device
    # is still polled underneath, so a button held throughout reads as held
    # again once input resumes. A node's press gate sees another snapshot come
    # back and refuses any press begun while input was suspended.
    # Scene::Rooms suspends a player's input while it moves them.
    class Player
      Controls = RGame::Util::Controls

      attr_reader :id, :camera, :ui, :mapper
      attr_accessor :name

      # `device` may be nil, meaning "nobody is driving this player yet" — a
      # seat waiting for a controller. Polling one reads as nothing held rather
      # than raising, so a game can show "Player 2: press a button" without a
      # special case.
      def initialize(id: 0, device: Controls::KEYBOARD, input_map: nil, camera: nil)
        @id = id
        @camera = camera || Camera.new
        @mapper = ActionMapper.new(input_map || InputMap.default, device: device)
        @ui = Node2D.new
        @name = nil
        @suspended = 0
        @idle_actions = nil
      end

      def device = @mapper.device
      def active? = !@mapper.device.nil?

      # Reassigning is how a hot-plug lands: the pad that just arrived in a slot
      # becomes this player's, and their bindings and camera carry on unchanged.
      def device=(value)
        @mapper.device = value
      end

      # This player's input for the current tick. Set by #poll, and a reused
      # object — hold the Player, never this. While input is suspended, a
      # snapshot of the same actions with nothing held.
      # hot-path
      def actions = @suspended.zero? ? @mapper.actions : idle_actions

      # Suspends this player's input until a matching #resume_input. Calls
      # count, so two owners may each suspend and resume. Returns the player.
      def suspend_input
        @suspended += 1
        self
      end

      # Ends one #suspend_input. Raises when nothing suspended the input, since
      # a resume with no suspend is one owner ending another's.
      def resume_input
        raise 'resume_input called with no suspend_input to end' if @suspended.zero?

        @suspended -= 1
        self
      end

      def input_suspended? = @suspended.positive?

      def poll(backend, dt) = @mapper.poll(backend, dt)

      # What this player's map can answer for. The vocabulary is the game's, so
      # it is the same for every player; the bindings behind it are not.
      def input_map = @mapper.map

      private

      def idle_actions
        @idle_actions ||= begin
          names = @mapper.map.bindings.keys
          at_rest = ->(value) { names.to_h { [it, value] }.freeze }
          Actions.new(held: at_rest[false], axes: at_rest[0.0], prev_held: at_rest[false],
                      hold_times: at_rest[0.0], down_since: at_rest[nil], poll_count: 0)
        end
      end
    end
  end
end
