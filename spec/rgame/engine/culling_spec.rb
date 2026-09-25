# frozen_string_literal: true

# A renderer that records nothing, for the allocation example alone.
# FakeRenderer allocates by design — it records every call it receives, and a
# draw path now pushes a transform through it as well as issuing draws — so it
# cannot be on the other end of an allocation measurement. This one only has to
# be call-compatible with what the draw path uses.
class SpecSilentRenderer
  def layered(_band) = yield
  def translated(_dx, _dy) = yield
  def rotated(_angle, _pivot_x, _pivot_y) = yield
  # Never reached: the node under measurement is culled.
  def image(*, **) = nil
end

# Exercised through the two components that use it, because what it decides is
# inseparable from how each of them anchors what it draws.
RSpec.describe RGame::Engine::Culling do
  # The fake refuses an image id it has never been shown, like the real one.
  let(:renderer) { FakeRenderer.new.tap { |r| r.register_image(:rock, StubImage.new(20, 20)) } }
  let(:camera)   { RGame::Engine::Camera.new.center_on(500, 500).resolve(100, 100) }

  # A world view 100x100 wide looking at (450, 450)..(550, 550).
  def world_view = screen_view(width: 100, height: 100, camera: camera)

  # A node under a root, so its absolute position means something.
  def node_at(x, y, width: 20, height: 20, angle: 0)
    root = RGame::Engine::Node2D.new
    root.add_node(RGame::Engine::Node2D.new(x: x, y: y, width: width, height: height,
                                            angle: angle))
  end

  describe 'a Sprite, centred on its node' do
    def drew?(node, anchor: :center)
      node.add_component(RGame::Engine::Components::Sprite.new(id: :rock, anchor: anchor))
      node.parent.enter_tree
      node.parent.draw(renderer, world_view)
      renderer.drawn?(:image)
    end

    it 'draws one inside the view' do
      expect(drew?(node_at(500, 500))).to be(true)
    end

    it 'skips one well outside it' do
      expect(drew?(node_at(5000, 500))).to be(false)
    end

    # Centred, so half of it is still showing when its origin is on the edge.
    it 'draws one straddling the edge' do
      expect(drew?(node_at(555, 500))).to be(true)
    end

    # A node that never set a size reads as 0x0, and culling on that would skip
    # everything instantly, and nothing requires a node to set one.
    it 'draws one that never declared a size' do
      expect(drew?(node_at(5000, 5000, width: 0, height: 0))).to be(true)
    end

    # Its origin is 5px below the view, so only a picture standing on it shows.
    it 'measures the footprint where the anchor put it' do
      expect(drew?(node_at(500, 555), anchor: :bottom)).to be(true)
    end

    it 'skips one hanging below an origin just below the view' do
      expect(drew?(node_at(500, 555), anchor: :top_left)).to be(false)
    end

    it 'measures the scaled footprint, not the unscaled one' do
      node = node_at(560, 500)
      node.add_component(RGame::Engine::Components::Sprite.new(id: :rock, scale: 6.0))
      node.parent.enter_tree
      node.parent.draw(renderer, world_view)
      expect(renderer.drawn?(:image)).to be(true)
    end

    # Its unscaled footprint ends 20px left of the view; four times the size
    # about its origin, it reaches 10px in.
    it 'measures a node scaled past 1 at that size, about its origin' do
      node = node_at(420, 500)
      node.scale = 4
      expect(drew?(node)).to be(true)
    end

    # 5px of it shows at full size, and none at a quarter.
    it 'skips a node shrunk out of the view that its full size would reach' do
      node = node_at(445, 500)
      node.scale = 0.25
      expect(drew?(node)).to be(false)
    end
  end

  describe 'an AnimatedSprite, standing on its node' do
    let(:sheet) do
      instance_double(FakeSheet, animations: { stand: { row: 0, frames: 1, fps: 1 } },
                                 frame_width: 20, frame_height: 20, draw: nil)
    end

    # It sizes the node from its sheet on attach, so its footprint is exactly
    # the node's box — no guessing needed. The renderer hands a sprite draw
    # straight to the sheet, so that is where the call lands.
    def drew?(node, anchor: :bottom)
      node.root.context = FakeGame.new(assets: instance_double(FakeAssets, sheet: sheet))
      renderer.register_sheet(:hero, sheet)
      node.add_component(RGame::Engine::Components::CharacterBody.new(speed: 1.0))
      node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: :hero, anchor: anchor))
      node.parent.enter_tree
      node.parent.draw(renderer, world_view)
      begin
        expect(sheet).to have_received(:draw)
        true
      rescue RSpec::Expectations::ExpectationNotMetError
        false
      end
    end

    it 'draws one inside the view' do
      expect(drew?(node_at(500, 500))).to be(true)
    end

    it 'skips one well outside it' do
      expect(drew?(node_at(500, 5000))).to be(false)
    end

    # Its origin is 5px below the view, so only a picture standing on it shows.
    it 'measures the footprint where the anchor put it' do
      expect(drew?(node_at(500, 555))).to be(true)
    end

    it 'skips one hanging below an origin just below the view' do
      expect(drew?(node_at(500, 555), anchor: :top_left)).to be(false)
    end
  end

  # Node2D rotates a node's own drawing about its absolute origin, so a rotated
  # footprint reaches further than its box in every direction. Culling one frame
  # too eagerly is a sprite popping in at the edge of the screen, which is worse
  # than the draw it saved — so a rotated node is measured generously.
  describe 'a rotated node' do
    def drew?(angle)
      node = node_at(440, 500, angle: angle)
      node.add_component(RGame::Engine::Components::Sprite.new(id: :rock))
      node.parent.enter_tree
      node.parent.draw(renderer, world_view)
      renderer.drawn?(:image)
    end

    it 'skips an unrotated node just outside the view' do
      expect(drew?(0)).to be(false)
    end

    it 'keeps drawing the same node once it is rotated' do
      expect(drew?(Math::PI / 4)).to be(true)
    end
  end

  # It runs once per drawable per viewport — the most-repeated test in a frame,
  # and four times as often with four players as it ever was with one.
  #
  # Measured on a node that *is* culled, so nothing but the test itself runs,
  # and through SpecSilentRenderer rather than FakeRenderer — see the note on
  # that class. What is being measured is the engine: the cull test, and the
  # transform push that wraps it.
  it 'costs no allocation' do
    silent = SpecSilentRenderer.new
    node = node_at(50_000, 50_000)
    node.add_component(RGame::Engine::Components::Sprite.new(id: :rock))
    node.parent.enter_tree
    view = world_view
    node.parent.draw(silent, view)

    expect { node.parent.draw(silent, view) }.to allocate_nothing
  end
end
