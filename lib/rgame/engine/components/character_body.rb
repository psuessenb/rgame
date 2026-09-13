# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Direct, per-step movement for a walking actor (player or NPC). A controller writes a
      # movement intent — each axis in -1..1 — and this component turns it into a real move
      # each update, at a fixed speed and with no inertia (unlike Velocity, which integrates
      # a velocity the controller sets, and ThrustController, which accelerates one).
      #
      # The intent doubles as the facing for AnimatedSprite (move_x / move_y readers), so
      # a character is just CharacterBody + a controller + AnimatedSprite.
      #
      # What may stop a step — `blocked_by:`, `on_blocked` / `on_unblocked`, and the
      # `apply_move` seam — is Mover's, and shared with every other component that moves a
      # node; see its header. What is this class's own is the intent and the speed.
      #
      #   CharacterBody.new(speed: 80)                             # walks wherever the intent points
      #   CharacterBody.new(speed: 80, blocked_by: %i[tiles npc])   # stopped by the map and by NPCs
      class CharacterBody < Mover
        attr_reader :move_x, :move_y

        def initialize(speed:, blocked_by: [])
          super(blocked_by: blocked_by)
          @speed = speed
          @move_x = 0.0
          @move_y = 0.0
        end

        # Set this step's movement intent; each axis is in -1..1.
        def set_intent(intent_x, intent_y)
          @move_x = intent_x
          @move_y = intent_y
        end

        private

        def take_step(dt)
          return if @move_x.zero? && @move_y.zero?

          apply_move(@move_x * @speed * dt, @move_y * @speed * dt)
        end
      end
    end
  end
end
