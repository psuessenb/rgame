# frozen_string_literal: true

# A stand-in for RGame::Core::Image for specs that care about geometry, not
# pixels.
#
#   sheet = RGame::Core::SpriteSheet.new(StubImage.new(64, 32), descriptor)
#
# The classes that slice an image — SpriteSheet, NineSlice, UiAtlas — only ever
# ask it for `width`, `height` and `subimage`, so this answers those and
# remembers which rectangle each cut came from. That turns "row 1, column 2 is
# taken from (64, 24)" into an assertion, which no amount of looking at a
# rendered frame would give you.
#
# There is no fake for a *drawn* image, because nothing draws one directly —
# FakeRenderer records whatever object it was handed, and these come back out of
# it identifiable by `#region`.
class StubImage
  attr_reader :width, :height, :region, :parent

  # `region` is [x, y, width, height] in the parent's coordinates, or nil for a
  # whole sheet.
  def initialize(width, height, region: nil, parent: nil)
    @width = width
    @height = height
    @region = region
    @parent = parent
  end

  def subimage(x, y, width, height)
    StubImage.new(width, height, region: [x, y, width, height], parent: self)
  end

  def inspect = region ? "#<StubImage #{region.inspect}>" : "#<StubImage #{width}x#{height}>"
end
