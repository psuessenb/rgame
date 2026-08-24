# frozen_string_literal: true

# What FakeRenderer#record hands back: the calls a block baked, plus a record of
# every time it was later replayed.
#
#   ground = renderer.record { tiles.each { |t| renderer.image(t.img, t.x, t.y) } }
#   ground.draw(-camera.x, -camera.y)
#
#   expect(ground.calls.size).to eq(tiles.size)
#   expect(ground.draws.map(&:args)).to eq([[-camera.x, -camera.y]])
#
# The two lists answer different questions, and a scene can get one right while
# getting the other wrong: `calls` is what was baked, `draws` is where it was
# put. A layer baked every frame instead of once shows up in the first; a layer
# baked correctly and then never drawn shows up in the second.
# One deliberate difference from RGame::Core::Recording, found by comparing the
# two: the real class refuses `.new` outright (NoMethodError — a recording comes
# from Renderer#record), and this one does not. Nothing a scene writes ever
# constructs one, so the guard would be surface with no caller behind it.
class FakeRecording
  attr_reader :calls, :draws

  def initialize(renderer)
    @renderer = renderer
    @calls = []
    @draws = []
  end

  # The replay. Recorded rather than performed — a fake draws nothing — and the
  # call is noted on the renderer too, so a spec that only cares about the order
  # things happened in can read one list.
  def draw(x = 0, y = 0, z: 0, color: nil)
    @renderer.send(:number, x)
    @renderer.send(:number, y)
    @renderer.send(:z_arg, z)
    @renderer.send(:color_arg, color)
    @draws << FakeRenderer::Call.new(:draw, [x, y], { z: z, color: color }, [], @renderer.layer)
    @renderer.send(:remember, :recording_draw, [self, x, y], z: z, color: color)
    self
  end

  # Mirrors FakeRenderer#calls_to, because a spec asserting on a bake wants the
  # same question answered about the recording.
  def calls_to(name) = @calls.select { |call| call.name == name }

  def empty? = @calls.empty?
end
