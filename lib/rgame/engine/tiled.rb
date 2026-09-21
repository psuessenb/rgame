# frozen_string_literal: true

require 'rexml/document'

module RGame
  module Engine
    # The faithful parse of a Tiled file: one class per element, keeping every
    # unit and coordinate the file states. `TileMap` turns it into what a game
    # reads at runtime, and nothing else names it.
    #
    # @api private — a game reads a file with `Tiled::Map.load` and hands the
    # result straight to `TileMap.from_tiled`; nothing else here is for a game.
    module Tiled
      # A file Tiled wrote that rgame refuses to read, or cannot. The message
      # names the element and, where it is known, the file.
      class FormatError < StandardError; end

      PARSER_VERSION = 1

      GID_MASK = 0x0FFFFFFF

      FLIP_BITS = 0xE0000000

      # A gid as the parse keeps it: the tile and the three flip flags. Bit 29,
      # Tiled's hexagonal rotation, is cleared. Tiled keeps it across a change of
      # orientation, so a map that is orthogonal now can still carry it.
      def self.gid(raw) = raw & (FLIP_BITS | GID_MASK)

      # The root element of the XML in `string`, which must be `<name>`. Raises
      # `FormatError` naming `source_path` for anything else, and for XML that
      # is not well-formed.
      def self.root(string, name, source_path)
        root = REXML::Document.new(string).root
        return root if root&.name == name

        where = source_path ? "#{source_path} " : ''
        raise FormatError, "#{where}is not a Tiled #{name}: its root element is not <#{name}>"
      rescue REXML::ParseException => e
        raise FormatError, "#{source_path || "the #{name}"} is not well-formed XML: #{e.message.lines.first}"
      end
    end
  end
end
