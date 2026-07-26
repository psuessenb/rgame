# frozen_string_literal: true

require 'json'

module Platform
  # Loads a texture atlas (image + JSON descriptor) and draws one frame.
  #
  # Frames live on a grid of `cell_width` x `cell_height` cells, but the drawn
  # frame can be smaller than its cell and offset within it (`frame_width/height`
  # + `origin_x/y`). This lets a sheet whose cells are sized for the widest pose
  # (e.g. an attack) still expose a tight, centred box for walking. Defaults make
  # frame == cell, so simple sheets need only `frame_width`/`frame_height`.
  #
  # The animation *table* is exposed raw so the engine core can build a
  # (Gosu-free) AnimationSet from it.
  class SpriteSheet
    attr_reader :frame_width, :frame_height, :animations

    # Load standalone: parse the descriptor and its image. The AssetManager instead
    # calls .new with an image it has already loaded + cached (so the PNG is shared),
    # mirroring Platform::TileMapRenderer.load.
    def self.load(atlas_path)
      atlas = JSON.parse(File.read(atlas_path), symbolize_names: true)
      dir   = File.dirname(File.expand_path(atlas_path))
      new(Gosu::Image.new(File.join(dir, atlas[:image]), retro: true), atlas)
    end

    # `atlas` is the parsed descriptor hash; `image` the already-loaded sheet image.
    def initialize(image, atlas)
      @frame_width  = atlas[:frame_width]
      @frame_height = atlas[:frame_height]
      @animations   = atlas[:animations]

      cell_w   = atlas[:cell_width]  || @frame_width
      cell_h   = atlas[:cell_height] || @frame_height
      origin_x = atlas[:origin_x] || 0
      origin_y = atlas[:origin_y] || 0

      columns = image.width  / cell_w
      rows    = image.height / cell_h
      @frames = Array.new(rows) do |r|
        Array.new(columns) do |c|
          image.subimage(c * cell_w + origin_x, r * cell_h + origin_y, @frame_width, @frame_height)
        end
      end
    end

    def draw(row, col, x, y, flip_x: false, z: 0)
      frame = @frames[row][col]
      if flip_x
        frame.draw(x + @frame_width, y, z, -1, 1)
      else
        frame.draw(x, y, z)
      end
    end
  end
end
