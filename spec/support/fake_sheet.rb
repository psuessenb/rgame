# frozen_string_literal: true

# A sprite sheet with no image behind it, for specs that animate rather than
# draw.
#
#   sheet = FakeSheet.new(
#     animations: { stand: { row: 0, frames: 1, fps: 1 },
#                   walk_right: { row: 1, frames: 4, fps: 8 } },
#     frame_width: 16, frame_height: 32
#   )
#
# The engine layer never names `RGame::Core::SpriteSheet` — a component is handed
# one by the asset manager and asks it three questions: what the animation table
# says, and how big a frame is (which is how a node sizes itself). That is what
# this answers, so `Engine::Components::AnimatedSprite` cannot tell the
# difference.
#
# It is also a faithful sheet from a *renderer's* side: register one with a
# FakeRenderer and `renderer.sprite(id, row, col, ...)` resolves it and calls
# `#draw` here, exactly as the real renderer resolves the real sheet. The frames
# are StubImages cut from a StubImage of the right size, so what came back out
# of the renderer is identifiable by `#region` — "row 1, column 2 was taken from
# (32, 32)" becomes an assertion.
#
# There is no shared contract for a sheet the way there is for a renderer or an
# audio device, because nothing in `spec_core/` runs the real one against a
# common example group yet. Until there is, keep this in step with
# `RGame::Core::SpriteSheet` by hand: the surface below is deliberately its
# public surface and nothing more.
class FakeSheet
  attr_reader :frame_width, :frame_height, :animations

  # `rows` and `columns` default to whatever the animation table needs — the
  # highest row it names, and the longest run of frames on any of them. A spec
  # describing an animation therefore gets a grid big enough to play it without
  # having to state the grid twice, and drawing a frame the table promised
  # cannot fall off the end.
  def initialize(animations: {}, frame_width: 16, frame_height: 16, rows: nil, columns: nil)
    @animations = animations
    @frame_width = frame_width
    @frame_height = frame_height

    rows ||= animations.values.map { |a| a[:row].to_i + 1 }.max || 1
    columns ||= animations.values.map { |a| a[:frames].to_i }.max || 1
    @frames = slice(rows, columns)
  end

  # How many frames the sheet was cut into, as [rows, columns].
  def grid = [@frames.length, @frames.empty? ? 0 : @frames[0].length]

  # The StubImage at a cell, for asserting on which rectangle a draw used.
  def frame(row, col) = @frames[row][col]

  # Mirrors RGame::Core::SpriteSheet#draw, down to how `flip_x` is expressed: a
  # negative x scale, so a mirrored character occupies the same pixels. Indexing
  # rather than fetching is deliberate — an out-of-range row fails here with the
  # same NoMethodError on nil the real sheet gives, instead of an IndexError no
  # game would ever see.
  def draw(renderer, row, col, x, y, flip_x: false, z: 0)
    renderer.image_at(@frames[row][col], x, y, scale_x: flip_x ? -1 : 1, z: z)
  end

  private

  # One StubImage for the whole sheet, cut up by StubImage#subimage — so the
  # regions are computed by the same slicing a real image goes through rather
  # than restated here.
  def slice(rows, columns)
    image = StubImage.new(columns * @frame_width, rows * @frame_height)
    Array.new(rows) do |row|
      Array.new(columns) do |col|
        image.subimage(col * @frame_width, row * @frame_height, @frame_width, @frame_height)
      end
    end
  end
end
