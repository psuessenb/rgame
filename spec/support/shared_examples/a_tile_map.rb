# frozen_string_literal: true

# The tile-map interface, stated once and run against every implementation.
#
# `RGame::Core::TileMapRenderer` draws a map it is handed and never names its
# class — it cannot, because a tile map belongs to the layer *above* Core (see
# CLAUDE.md, "The rule points both ways"). That makes this method list a real
# interface with more than one implementation: the parsed `RGame::Engine::TileMap` a
# game loads from a `.tmx`, and the stub a spec builds by hand.
#
# If the stub drifts, `rake spec:core` stays green while the game draws the
# wrong tiles — the same failure the renderer and audio contracts exist to
# prevent, one layer up.
#
# ## What the host must provide
#
#   tile_map { |map| ... }
#
# A map of one exact shape, because a contract can only assert what it knows is
# in there:
#
#   2 x 2 tiles, 16 px each, two layers, layer 1 flagged "above"
#
#   layer 0 (below):  gid 1  gid 2      layer 1 (above):  0      0
#                     0      gid 3                        gid 4  0
#
#   the tileset's firstgid is 1, so those are local ids 0, 1, 2 and 3
#   local id 0 is animated: two frames, tiles 0 then 1, 100 ms each
#
# Building that from a `.tmx` and building it by hand are very different jobs,
# which is the point — the contract says the shape and each host says how.
#
# ## What this group does not check
#
# Parsing. How a `.tmx` becomes this is `RGame::Engine::TileMap`'s own business and is
# covered in its own spec; what is stated here is only what the renderer below
# reads.
RSpec.shared_examples 'a tile map' do
  describe 'geometry' do
    it 'reports its size in tiles' do
      tile_map { |map| expect([map.width, map.height]).to eq([2, 2]) }
    end

    it 'reports its tile size in pixels' do
      tile_map { |map| expect([map.tile_width, map.tile_height]).to eq([16, 16]) }
    end

    it 'reports how many layers it has' do
      tile_map { |map| expect(map.layer_count).to eq(2) }
    end
  end

  describe 'layers' do
    it 'says which layers draw above the actors' do
      # The whole reason the renderer draws in two passes. A map that got this
      # backwards would put every tree canopy behind every character.
      tile_map do |map|
        expect([map.above_layer?(0), map.above_layer?(1)]).to eq([false, true])
      end
    end

    it 'answers a gid per layer, column and row' do
      tile_map do |map|
        expect(map.gid(0, 0, 0)).to eq(1)
        expect(map.gid(0, 1, 0)).to eq(2)
        expect(map.gid(0, 1, 1)).to eq(3)
        expect(map.gid(1, 0, 1)).to eq(4)
      end
    end

    it 'answers zero where a layer has no tile' do
      # Zero is the empty tile, and the renderer skips it. Anything else — nil,
      # or an id that happens to be valid — draws a tile nobody placed.
      tile_map do |map|
        expect(map.gid(0, 0, 1)).to be_zero
        expect(map.gid(1, 0, 0)).to be_zero
      end
    end

    it 'takes its arguments as (layer, column, row)' do
      # Column before row, matching x before y everywhere else. Transposing
      # them is silent on a square map, which is why this one is not square in
      # its contents.
      tile_map do |map|
        expect(map.gid(0, 1, 0)).to eq(2)
        expect(map.gid(0, 0, 1)).to be_zero
      end
    end
  end

  describe 'its tileset' do
    it 'turns a map gid into a tileset-local id' do
      tile_map { |map| expect(map.tileset.local_id(3)).to eq(2) }
    end

    it 'knows which local ids are animated' do
      tile_map do |map|
        expect(map.tileset.animations).to have_key(0)
        expect(map.tileset.animations).not_to have_key(1)
      end
    end

    it 'resolves an animated tile to the frame showing at a given moment' do
      # Two 100 ms frames, so the cycle is 200 ms and it repeats.
      tile_map do |map|
        expect(map.tileset.frame_local_id(0, 0)).to eq(0)
        expect(map.tileset.frame_local_id(0, 150)).to eq(1)
        expect(map.tileset.frame_local_id(0, 250)).to eq(0)
      end
    end

    it 'leaves a tile that is not animated alone' do
      tile_map { |map| expect(map.tileset.frame_local_id(1, 150)).to eq(1) }
    end
  end
end
