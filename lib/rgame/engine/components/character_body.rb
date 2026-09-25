# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Direct, per-step movement for a walking actor (player or NPC). A controller writes a
      # movement intent — each axis in -1..1 — and this component turns it into a real move
      # each update, at a fixed speed and with no inertia (unlike Velocity, which integrates
      # a velocity the controller sets, and ThrustController, which accelerates one).
      #
      # The intent doubles as the mover's heading, which is what AnimatedSprite faces by, so
      # a character is just CharacterBody + a controller + AnimatedSprite.
      #
      # What may stop a step — `blocked_by:`, `on_blocked` / `on_unblocked`, and the
      # `apply_move` seam — is Mover's, and shared with every other component that moves a
      # node; see its header. What is this class's own is the intent and the speed.
      #
      #   CharacterBody.new(speed: 80)                             # walks wherever the intent points
      #   CharacterBody.new(speed: 80, blocked_by: %i[tiles npc])   # stopped by the map and by NPCs
      class CharacterBody < Mover
        sealed_reader :move_x, :move_y

        def initialize(speed:, blocked_by: [], pushes: [])
          super(blocked_by:, pushes:)
          @rgame_speed = speed
          @rgame_move_x = 0.0
          @rgame_move_y = 0.0
        end

        # Stands the body still as its node enters the tree, so a node carried
        # into a scene, or taken from a pool again, does not walk on with the
        # intent it had. A game that wants a walk-in sets one after placing it.
        def _attach
          @rgame_move_x = 0.0
          @rgame_move_y = 0.0
          super
        end

        # The heading is the intent as set, blocked or not.
        def heading_x = @rgame_move_x
        def heading_y = @rgame_move_y

        # Set this step's movement intent; each axis is in -1..1.
        def set_intent(intent_x, intent_y)
          @rgame_move_x = intent_x
          @rgame_move_y = intent_y
        end

        private

        def take_step(dt)
          return if @rgame_move_x.zero? && @rgame_move_y.zero?

          apply_move(@rgame_move_x * @rgame_speed * dt, @rgame_move_y * @rgame_speed * dt)
        end
      end
    end
  end
end
