# frozen_string_literal: true

require 'rexml/document'

module RGame
  module Engine
    # Tile-type data parsed from a Tiled .tsx (pure; no graphics). Knows tile geometry,
    # sheet columns, per-tile animations, and which tiles are solid. Solidity is
    # *baked into the asset*: a tile is solid when it carries a Tiled collision shape
    # (a per-tile `<objectgroup>` with at least one object), authored in Tiled's
    # collision editor — so the map owns its collision, not the engine. `solid_ids`
    # stays writable for games that want to override or augment it.
    # Animation frames resolve from elapsed time so the renderer stays a thin layer.
    class Tileset
      Frame = Struct.new(:tile_id, :duration)

      attr_reader :firstgid, :columns, :tile_width, :tile_height, :image_source, :animations
      attr_accessor :solid_ids # Set of *local* tile ids treated as solid

      def self.parse(tsx_string, firstgid:)
        root = REXML::Document.new(tsx_string).root

        animations = {}
        solid = Set.new
        root.each_element('tile') do |tile_el|
          id = tile_el.attributes['id'].to_i
          animations[id] = parse_animation(tile_el)
          solid << id if collision_shape?(tile_el)
        end
        animations.compact!

        new(
          firstgid: firstgid,
          columns: root.attributes['columns'].to_i,
          tile_width: root.attributes['tilewidth'].to_i,
          tile_height: root.attributes['tileheight'].to_i,
          image_source: root.elements['image'].attributes['source'],
          animations: animations,
          solid_ids: solid
        )
      end

      # Frames for an animated tile, or nil (compacted away) for a static one.
      def self.parse_animation(tile_el)
        anim = tile_el.elements['animation']
        return unless anim

        anim.get_elements('frame').map do |f|
          Frame.new(f.attributes['tileid'].to_i, f.attributes['duration'].to_i)
        end
      end

      # A tile is solid if it carries a Tiled collision shape — an `<objectgroup>`
      # with at least one object (the per-tile collision editor's output).
      def self.collision_shape?(tile_el)
        group = tile_el.elements['objectgroup']
        !group.nil? && !group.elements['object'].nil?
      end

      def initialize(firstgid:, columns:, tile_width:, tile_height:, image_source:, animations:, solid_ids: Set.new)
        @firstgid = firstgid
        @columns = columns
        @tile_width = tile_width
        @tile_height = tile_height
        @image_source = image_source
        @animations = animations
        @solid_ids = solid_ids
      end

      def animated_ids
        @animations.keys
      end

      def local_id(gid)
        gid - @firstgid
      end

      def solid?(gid)
        return false if gid.zero?

        @solid_ids.include?(local_id(gid))
      end

      # The local tile id to draw for `local` at time `ms`, following its animation
      # (or `local` itself if the tile isn't animated).
      def frame_local_id(local, ms)
        frames = @animations[local]
        return local unless frames

        total = frames.sum(&:duration)
        t = ms % total
        frames.each do |frame|
          return frame.tile_id if t < frame.duration

          t -= frame.duration
        end
        frames.last.tile_id
      end
    end
  end
end
