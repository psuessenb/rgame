# frozen_string_literal: true

module Engine
  # Drives an Actor from player input: turns the move_x/move_y actions into a
  # movement intent. NPC controllers implement the same `intent(dt, input)` seam
  # and ignore `input`.
  class PlayerController
    def intent(_dt, input)
      [input.axis(:move_x), input.axis(:move_y)]
    end
  end
end
