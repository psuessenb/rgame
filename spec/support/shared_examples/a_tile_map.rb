# frozen_string_literal: true

# The tile-map interface, stated once and run against every implementation.
#
# `RGame::Core::TileMapRenderer` draws a map it is handed and never names its
# class — it cannot, because a tile map belongs to the layer *above* Core
# (see "The rule points both ways"). `TileWorld` and `TileMapLayer` read the
# same map from the engine side. That makes this method list a real interface
# with more than one implementation: the `RGame::Engine::TileMap` a game builds
# from a `.tmx`, and the stub a spec builds by hand.
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
#   layer 0 (below):  tile 1  tile 2      layer 1 (above):  0       0
#                     0       tile 3                        tile 4  0
#
#   tile 2 in layer 0 is turned a quarter clockwise
#   tile 3 is solid
#   tile 1 is animated: two frames, tiles 1 then 2, 0.1 s each
#
# Building that from a `.tmx` and building it by hand are very different jobs,
# which is the point — the contract says the shape and each host says how.
#
# ## What this group does not check
#
# Parsing and the transform. How a `.tmx` becomes this is
# `RGame::Engine::TileMap`'s own business and is covered in its own spec; what
# is stated here is only what the readers of a map call.
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
      # A map that got this backwards would put every tree canopy behind every
      # character.
      tile_map { |map| expect([map.layer(0).above?, map.layer(1).above?]).to eq([false, true]) }
    end
  end

  describe 'cells' do
    it 'answers a tile per layer, column and row' do
      tile_map do |map|
        expect([map.tile(0, 0, 0), map.tile(0, 1, 0), map.tile(0, 1, 1), map.tile(1, 0, 1)]).to eq([1, 2, 3, 4])
      end
    end

    it 'answers zero where a layer has no tile' do
      # Zero is the empty tile, and the renderer skips it. Anything else — nil,
      # or an id that happens to be valid — draws a tile nobody placed.
      tile_map { |map| expect([map.tile(0, 0, 1), map.tile(1, 0, 0)]).to all(be_zero) }
    end

    it 'takes its arguments as (layer, column, row)' do
      # Column before row, matching x before y everywhere else. Transposing
      # them is silent on a square map, which is why this one is not square in
      # its contents.
      tile_map { |map| expect([map.tile(0, 1, 0), map.tile(0, 0, 1)]).to eq([2, 0]) }
    end

    it 'says how a turned tile is turned' do
      tile_map do |map|
        orientation = map.orientation(0, 1, 0)
        expect([orientation.quarter_turns, orientation.mirrored?, orientation.identity?]).to eq([1, false, false])
      end
    end

    it 'answers the identity for a tile that is not turned' do
      tile_map { |map| expect(map.orientation(0, 0, 0).identity?).to be(true) }
    end
  end

  describe 'tiles' do
    it 'says which tiles are solid, and never the empty one' do
      tile_map { |map| expect([map.solid?(0), map.solid?(1), map.solid?(3)]).to eq([false, false, true]) }
    end

    it 'lists the tiles that animate' do
      tile_map { |map| expect(map.animated_tiles).to eq([1]) }
    end

    it 'resolves an animated tile to the frame showing after so many seconds' do
      # Two 0.1 s frames, so the loop is 0.2 s long and repeats.
      tile_map { |map| expect([0.0, 0.15, 0.25].map { map.frame_tile(1, it) }).to eq([1, 2, 1]) }
    end

    it 'leaves a tile that is not animated alone' do
      tile_map { |map| expect(map.frame_tile(2, 0.15)).to eq(2) }
    end
  end
end
