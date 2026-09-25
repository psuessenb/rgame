# frozen_string_literal: true

# A node's scale sizes what it draws and everything under it, about its origin,
# the way its opacity fades them: `draw` applies it, so no `_draw` can leave it
# out, and nothing but drawing changes.
RSpec.describe RGame::Engine::Node2D do
  let(:renderer) { FakeRenderer.new }
  let(:root) { described_class.new }
  let(:parent) { root.add_node(box.new(x: 10, y: 20)) }
  let(:child) { parent.add_node(box.new(x: 4)) }

  # A node that draws one rect, and counts the frames it was driven through.
  def box
    Class.new(described_class) do
      attr_reader :updates

      def initialize(**)
        super
        @updates = 0
      end

      def _update(_dt) = @updates += 1
      def _draw(renderer, _view) = renderer.rect(0, 0, 4, 4)
    end
  end

  def draw = root.draw(renderer, screen_view)

  def around(call, name) = call.transforms.select { it.name == name }.map(&:args)

  it 'is 1 until set' do
    expect(described_class.new.scale).to eq(1)
  end

  describe 'between 0 and 1' do
    before do
      child
      parent.scale = 0.5
      draw
    end

    it 'scales the node\'s own drawing, inside its move to its origin' do
      transforms = renderer.calls_to(:rect).first.transforms.map(&:name)

      expect(transforms).to eq(%i[translated scaled])
      expect(around(renderer.calls_to(:rect).first, :scaled)).to eq([[0.5, 0.5]])
    end

    it 'scales every child under it, which no _draw of its own could reach' do
      expect(around(renderer.calls_to(:rect).last, :scaled)).to eq([[0.5, 0.5]])
    end

    it 'opens one scale for the node and its whole subtree' do
      expect(renderer.calls_to(:scaled).size).to eq(1)
    end
  end

  it 'scales what the node\'s components draw' do
    part = Class.new(RGame::Engine::Component) do
      def _draw(renderer, _view) = renderer.circle(0, 0, 2)
    end
    parent.add_component(part.new)
    parent.scale = 2
    draw

    expect(around(renderer.calls_to(:circle).first, :scaled)).to eq([[2, 2]])
  end

  it 'multiplies with the scale of a node above it' do
    parent.scale = 0.5
    child.scale = 0.5
    draw

    expect(around(renderer.calls_to(:rect).last, :scaled)).to eq([[0.5, 0.5], [0.5, 0.5]])
  end

  it 'scales outside a fade, so a node at both opens both' do
    parent.scale = 0.5
    parent.opacity = 0.5
    draw

    names = renderer.calls_to(:rect).first.transforms.map(&:name)
    expect(names).to eq(%i[translated scaled faded])
  end

  it 'pushes nothing at 1' do
    child
    draw

    expect(renderer.drawn?(:scaled)).to be(false)
    expect(renderer.calls_to(:rect).size).to eq(2)
  end

  describe 'at 0' do
    let(:sibling) { root.add_node(box.new) }

    before do
      child
      sibling
      parent.scale = 0
    end

    it 'draws nothing of the node or its children, and leaves its siblings alone' do
      draw

      expect(renderer.calls_to(:rect).size).to eq(1)
      expect(renderer.drawn?(:scaled)).to be(false)
    end

    it 'still updates the subtree, since only drawing changes' do
      root.update(0.016)

      expect([parent.updates, child.updates]).to eq([1, 1])
    end
  end

  it 'leaves positions alone, the children\'s included' do
    child
    parent.scale = 0.25

    expect([parent.world_x, parent.world_y, child.world_x]).to eq([10, 20, 14])
  end

  describe '#scale=' do
    it 'refuses a negative number, NaN and infinity' do
      [-0.1, Float::NAN, Float::INFINITY].each do |value|
        expect { parent.scale = value }.to raise_error(ArgumentError, /scale/)
      end
    end

    it 'refuses anything that is not a number' do
      ['0.5', nil].each do |value|
        expect { parent.scale = value }.to raise_error(TypeError)
      end
    end

    it 'keeps the scale it had when it refuses one' do
      parent.scale = 0.5
      expect { parent.scale = -1 }.to raise_error(ArgumentError)

      expect(parent.scale).to eq(0.5)
    end

    it 'takes a scale past 1' do
      parent.scale = 3

      expect(parent.scale).to eq(3)
    end
  end

  describe 'drawing' do
    [[1, 1], [0.5, 1], [0.5, 0.5], [0, 1]].each do |scale, opacity|
      it "allocates nothing at scale #{scale}, opacity #{opacity}" do
        parent.scale = scale
        parent.opacity = opacity
        child.scale = scale
        quiet = QuietRenderer.new
        view = screen_view

        expect { root.draw(quiet, view) }.to allocate_nothing
      end
    end
  end
end
