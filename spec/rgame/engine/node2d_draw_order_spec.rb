# frozen_string_literal: true

# Draw order, asserted from a headless spec.
#
# It is assertable at all because FakeRenderer records the resolved sort key of
# every call — the number the real renderer's draw queue orders a frame by. So
# "the canopy is above the actor" stops being something only a human looking at
# a window can check, and the property that matters most here — that a subtree
# is *atomic* — becomes a statement about two lists.
RSpec.describe RGame::Engine::Node2D do
  let(:renderer) { FakeRenderer.new }
  let(:root) { described_class.new }

  # tag => the layer that node drew in. One slot per node, so the layer is the
  # node's identity for the frame.
  let(:layers) { {} }

  # A node that draws one rectangle and notes which layer it landed in.
  # `offset` is the rectangle's own `z:` — an offset inside this node's slot,
  # which is a different thing from the node's `z` among its siblings.
  def tagged(tag, offset: 0, **)
    seen = layers
    Class.new(described_class) do
      define_method(:_draw) do |renderer, _view|
        seen[renderer.layer] = tag
        renderer.rect(0, 0, 1, 1, z: offset)
      end
    end.new(**)
  end

  # The tags in the order the frame comes out — by sort key, not by the order
  # the calls happened to be issued in.
  def draw_and_read
    renderer.clear
    layers.clear
    root.draw(renderer, screen_view)
    renderer.calls_to(:rect).sort_by(&:key).map { |call| layers.fetch(call.layer) }
  end

  describe 'siblings' do
    it 'draws them in z order, whatever order they were added in' do
      root.add_node(tagged(:clouds, z: 2))
      root.add_node(tagged(:people, z: 0))
      root.add_node(tagged(:birds, z: 1))

      expect(draw_and_read).to eq(%i[people birds clouds])
    end

    it 'keeps the order they were added in when their z is equal' do
      # Ruby's sort is not stable. Without the insertion tie-break these three
      # would be free to swap between frames, which reads on screen as flicker.
      root.add_node(tagged(:first))
      root.add_node(tagged(:second))
      root.add_node(tagged(:third))

      expect(draw_and_read).to eq(%i[first second third])
    end

    it 'sorts a child added after a draw in among the others by its z' do
      root.add_node(tagged(:people, z: 1))
      draw_and_read

      root.add_node(tagged(:ground, z: 0))
      expect(draw_and_read).to eq(%i[ground people])
    end

    it 're-sorts when a z changes' do
      first = root.add_node(tagged(:first))
      root.add_node(tagged(:second))
      draw_and_read

      first.z = 10
      expect(draw_and_read).to eq(%i[second first])
    end

    it 'compares z and nothing else, so its magnitude means nothing' do
      root.add_node(tagged(:high, z: 1_000_000))
      root.add_node(tagged(:low, z: -4))

      expect(draw_and_read).to eq(%i[low high])
    end
  end

  describe 'a subtree' do
    # The whole reason for the rework. Under additive relative z a child at
    # z 5 inside a parent at z 2 resolved to 7 and overtook a sibling at 4 —
    # part of a node in front of something the node itself was behind.
    it 'is drawn atomically, whatever its children ask for' do
      behind = root.add_node(tagged(:behind, z: 2))
      behind.add_node(tagged(:behind_child, z: 1_000))
      front = root.add_node(tagged(:front, z: 4))
      front.add_node(tagged(:front_child, z: -1_000))

      expect(draw_and_read).to eq(%i[behind behind_child front front_child])
    end

    it 'draws a parent before its children, so a child covers its parent' do
      parent = root.add_node(tagged(:parent))
      parent.add_node(tagged(:child))

      expect(draw_and_read).to eq(%i[parent child])
    end

    it 'orders whole branches by their roots, however deep they go' do
      back = root.add_node(tagged(:back, z: 0))
      back.add_node(tagged(:back_a)).add_node(tagged(:back_b))
      front = root.add_node(tagged(:front, z: 1))
      front.add_node(tagged(:front_a))

      expect(draw_and_read).to eq(%i[back back_a back_b front front_a])
    end
  end

  describe 'a y-sorted parent' do
    let(:sorted) { root.add_node(described_class.new(y_sort: true)) }

    def boxed(tag, box_y:, box_height:, **)
      tagged(tag, **).tap do |node|
        node.add_component(RGame::Engine::Components::BoxCollider.new(width: 8, height: box_height, offset_y: box_y))
      end
    end

    it 'draws a child standing further down after one standing further up' do
      sorted.add_node(tagged(:front, y: 50))
      sorted.add_node(tagged(:back, y: 10))

      expect(draw_and_read).to eq(%i[back front])
    end

    it 'follows a child that walks past another' do
      walker = sorted.add_node(tagged(:walker, y: 10))
      sorted.add_node(tagged(:post, y: 30))
      expect(draw_and_read).to eq(%i[walker post])

      walker.y = 40
      expect(draw_and_read).to eq(%i[post walker])
    end

    it 'draws a higher z later, wherever the children stand' do
      sorted.add_node(tagged(:sparkles, y: 0, z: 1))
      sorted.add_node(tagged(:hero, y: 100))

      expect(draw_and_read).to eq(%i[hero sparkles])
    end

    it 'keeps the order added for children standing level, frame after frame' do
      sorted.add_node(tagged(:first, y: 20))
      sorted.add_node(tagged(:second, y: 20))
      sorted.add_node(tagged(:third, y: 20))

      expect([draw_and_read, draw_and_read]).to all(eq(%i[first second third]))
    end

    it 'stands a child with a box at the bottom edge of the box' do
      # The crate's origin is above the hero's, and its box reaches below it.
      sorted.add_node(boxed(:crate, y: 10, box_y: 0, box_height: 40))
      sorted.add_node(tagged(:hero, y: 30))

      expect(draw_and_read).to eq(%i[hero crate])
    end

    it 'stands a child with no box at its y' do
      sorted.add_node(tagged(:coin, y: 30))
      sorted.add_node(boxed(:crate, y: 0, box_y: 0, box_height: 20))

      expect(draw_and_read).to eq(%i[crate coin])
    end

    it 'draws a lifted child where it stands, not where its picture is' do
      sorted.add_node(tagged(:hero, y: 30)).elevation = 25
      sorted.add_node(tagged(:rock, y: 20))

      expect(draw_and_read).to eq(%i[rock hero])
    end

    it "sorts a child's subtree as one unit, at the child's footing" do
      hero = sorted.add_node(tagged(:hero, y: 10))
      hero.add_node(tagged(:shadow, y: 100))
      sorted.add_node(tagged(:post, y: 30))

      expect(draw_and_read).to eq(%i[hero shadow post])
    end

    it 'draws the same order through every viewport of a frame' do
      sorted.add_node(tagged(:front, y: 50))
      sorted.add_node(tagged(:back, y: 10))
      renderer.clear
      2.times { root.draw(renderer, screen_view) }

      expect(renderer.calls_to(:rect).map { layers.fetch(it.layer) }).to eq(%i[back front back front])
    end

    it 'returns to z order when switched off' do
      sorted.add_node(tagged(:front, y: 50))
      sorted.add_node(tagged(:back, y: 10))
      sorted.y_sort = false

      expect(draw_and_read).to eq(%i[front back])
    end

    it 'sorts the children it already had when switched on' do
      plain = root.add_node(described_class.new)
      plain.add_node(tagged(:front, y: 50))
      plain.add_node(tagged(:back, y: 10))
      plain.y_sort = true

      expect(draw_and_read).to eq(%i[back front])
    end

    it 'stops drawing a child that was removed, and draws one added later in its place' do
      gone = sorted.add_node(tagged(:gone, y: 10))
      sorted.add_node(tagged(:stays, y: 20))
      draw_and_read
      sorted.remove_node(gone)
      sorted.add_node(tagged(:late, y: 0))

      expect(draw_and_read).to eq(%i[late stays])
    end

    # Everything at once: a feet box on a hero mid-hop, a crate's body box and
    # a coin with none, in one sorted gap drawn through two viewports.
    it 'sorts a hero mid-hop, a crate and a coin the same way in both viewports' do
      components = RGame::Engine::Components
      hero = tagged(:hero, y: 0, width: 16, height: 24)
      hero.add_component(components::FeetCollider.new(width: 12, height: 6))
      hop = hero.add_component(components::Hop.new(peak: 30, duration: 0.5, action: nil))
      sorted.add_node(boxed(:crate, y: 4, box_y: 0, box_height: 16))
      sorted.add_node(hero)
      sorted.add_node(tagged(:coin, y: 22))
      root.enter_tree
      hop.jump
      root.update(0.25)
      renderer.clear
      2.times { root.draw(renderer, screen_view) }

      expect(hero.elevation).to be > 0
      expect(renderer.calls_to(:rect).map { layers.fetch(it.layer) }).to eq(%i[crate coin hero] * 2)
    end
  end

  describe 'bands' do
    it 'defaults to the world band' do
      node = root.add_node(described_class.new)
      root.update(0)

      expect(node.abs_band).to eq(:world)
    end

    # Driven with `draw`, because the band is a draw concept: `draw` is the phase
    # that reads it, and so the phase that resolves it. `update` resolves only
    # the transform, and `control` only the input owner.
    it 'inherits down the tree, like the input owner' do
      layer = root.add_node(described_class.new(band: :overlay))
      deep = layer.add_node(described_class.new).add_node(described_class.new)
      root.draw(renderer, screen_view)

      expect(deep.abs_band).to eq(:overlay)
    end

    it 'lets a node inside a band declare its own way out' do
      # The escape hatch, and the only one: explicit and named, where the
      # Integer bases it replaces were neither.
      layer = root.add_node(described_class.new(band: :world))
      escapee = layer.add_node(described_class.new(band: :overlay))
      root.update(0)

      expect(escapee.abs_band).to eq(:overlay)
    end

    it 'refuses a band that is not one' do
      expect { described_class.new(band: :nope) }
        .to raise_error(ArgumentError, /unknown z band/)
    end

    it 'puts a later band above an earlier one, whatever the tree says' do
      # The HUD node is added first and would be drawn first; the band overrules
      # the tree, which is the one thing a band is for.
      root.add_node(tagged(:score, band: :hud))
      root.add_node(tagged(:world_thing, z: 1_000_000))

      expect(draw_and_read).to eq(%i[world_thing score])
    end

    it 'cannot be escaped by any z a node passes' do
      # A node's `z:` is an offset inside its own slot, so the largest one it
      # can express is still far below the next band's first slot.
      root.add_node(tagged(:world_thing, offset: RGame::Util::Z::Z_MAX))
      root.add_node(tagged(:score, offset: RGame::Util::Z::Z_MIN, band: :hud))

      expect(draw_and_read).to eq(%i[world_thing score])
    end
  end
end
