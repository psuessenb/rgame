# frozen_string_literal: true

module RGame
  module Engine
    # The faithful parse of a Tiled file: one class per element, keeping every
    # unit and coordinate the file states. `TileMap` turns it into what a game
    # reads at runtime, and nothing else names it.
    #
    # @api private — until the runtime view hands its parts to a game, nothing
    # outside the engine can reach one.
    module Tiled
      # A file Tiled wrote that rgame refuses to read, or cannot. The message
      # names the element and, where it is known, the file.
      class FormatError < StandardError; end
    end
  end
end
