# frozen_string_literal: true

# A renderer for `allocate_nothing`, and for nothing else.
#
#   expect { button._draw(QuietRenderer.new, nil) }.to allocate_nothing
#
# FakeRenderer records every call, which allocates, so it cannot measure a draw;
# an RSpec double allocates per call too. This one answers the drawing methods a
# UI draw uses with explicit keyword parameters, so a call collects no Hash, and
# keeps nothing. What it does do is run each colour through
# RGame::Util::Color.coerce, as Core::Renderer#packed does — so a draw that hands
# over an Array colour allocates a Color per call here exactly as it would in
# the game, and the matcher sees it.
#
# `layered`, `translated` and `clipped` only yield, so a whole subtree's `draw`
# can be measured as well as one node's `_draw` — a WorldView's included, which
# opens a clip per viewport.
#
# It refuses nothing and records nothing, so it says nothing about *what* was
# drawn. That is FakeRenderer's job, checked against the renderer contract.
class QuietRenderer
  def rect(_x, _y, _width, _height, z: 0, color: nil) = coerce(z, color)
  def triangle(_x1, _y1, _x2, _y2, _x3, _y3, z: 0, color: nil) = coerce(z, color)
  def circle(_cx, _cy, _radius, z: 0, color: nil) = coerce(z, color)
  def debug_box(_x, _y, _width, _height, z: 0) = coerce(z, nil)
  def debug_circle(_cx, _cy, _radius, z: 0) = coerce(z, nil)
  def line(_x1, _y1, _x2, _y2, thickness: 1.0, z: 0, color: nil) = coerce(z + thickness, color)
  def nine_slice(_id, _x, _y, _width, _height, z: 0, tint: nil) = coerce(z, tint)
  def text(_string, _x, _y, z: 0, color: nil, font: nil, bytes: nil) = coerce(z, color, font, bytes)
  def image(_image, _cx, _cy, scale: 1, z: 0, color: nil) = coerce(z + scale, color)

  def layered(_band) = yield
  def translated(_dx, _dy) = yield
  def clipped(_x, _y, _width, _height) = yield

  def typeface = RGame::Util::Typeface.default
  def text_width(string, font: nil) = (font || typeface).text_width(string)
  def text_height(font: nil) = (font || typeface).height

  private

  def coerce(_z, color, _font = nil, _bytes = nil) = RGame::Util::Color.coerce(color)
end
