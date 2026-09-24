# frozen_string_literal: true

# A node's opacity fades what it draws and everything under it, the way its
# transform moves them: `draw` applies it, so no `_draw` can leave it out.
RSpec.describe RGame::Engine::Node2D do
  let(:renderer) { FakeRenderer.new }
  let(:root) { described_class.new }
  let(:parent) { root.add_node(box.new) }
  let(:child) { parent.add_node(box.new) }

  # A node that draws one rect, and counts the frames it was driven through.
  def box
    Class.new(described_class) do
      attr_reader :updates, :controls

      def initialize(**)
        super
        @updates = @controls = 0
      end

      def _update(_dt) = @updates += 1
      def _control(_actions) = @controls += 1
      def _draw(renderer, _view) = renderer.rect(0, 0, 4, 4)
    end
  end

  def draw = root.draw(renderer, screen_view)

  def fades_around(call) = call.transforms.select { it.name == :faded }.map { it.args.first }

  it 'is 1 until set' do
    expect(described_class.new.opacity).to eq(1)
  end

  describe 'below 1' do
    before do
      child
      parent.opacity = 0.5
      draw
    end

    it 'fades the node\'s own drawing' do
      expect(fades_around(renderer.calls_to(:rect).first)).to eq([0.5])
    end

    it 'fades every child under it, which no _draw of its own could reach' do
      expect(fades_around(renderer.calls_to(:rect).last)).to eq([0.5])
    end

    it 'opens one fade for the node and its whole subtree' do
      expect(renderer.calls_to(:faded).size).to eq(1)
    end
  end

  it 'fades what the node\'s components draw' do
    part = Class.new(RGame::Engine::Component) do
      def _draw(renderer, _view) = renderer.circle(0, 0, 2)
    end
    parent.add_component(part.new)
    parent.opacity = 0.25
    draw

    expect(fades_around(renderer.calls_to(:circle).first)).to eq([0.25])
  end

  it 'multiplies with the opacity of a node above it' do
    parent.opacity = 0.5
    child.opacity = 0.5
    draw

    expect(fades_around(renderer.calls_to(:rect).last)).to eq([0.5, 0.5])
  end

  it 'pushes nothing at 1' do
    child
    draw

    expect(renderer.drawn?(:faded)).to be(false)
    expect(renderer.calls_to(:rect).size).to eq(2)
  end

  describe 'at 0' do
    let(:sibling) { root.add_node(box.new) }

    before do
      child
      sibling
      parent.opacity = 0
    end

    it 'draws nothing of the node or its children, and leaves its siblings alone' do
      draw

      expect(renderer.calls_to(:rect).size).to eq(1)
      expect(renderer.drawn?(:faded)).to be(false)
    end

    it 'still controls and updates the subtree, since only drawing changes' do
      root.control(RGame::Engine::Actions.new)
      root.update(0.016)

      expect([parent.controls, parent.updates, child.controls, child.updates]).to eq([1, 1, 1, 1])
    end
  end

  describe '#opacity=' do
    it 'refuses what renderer.faded refuses, with the same error' do
      [1.5, -0.1, Float::NAN, '0.5', nil].each do |value|
        expected = begin
          renderer.faded(value) { nil }
        rescue StandardError => e
          e
        end

        expect { parent.opacity = value }.to raise_error(expected.class, expected.message)
      end
    end

    it 'keeps the opacity it had when it refuses one' do
      parent.opacity = 0.5
      expect { parent.opacity = 2 }.to raise_error(ArgumentError)

      expect(parent.opacity).to eq(0.5)
    end
  end

  describe 'drawing' do
    [1, 0.5, 0].each do |opacity|
      it "allocates nothing at #{opacity}" do
        parent.opacity = opacity
        child.opacity = opacity
        quiet = QuietRenderer.new
        view = screen_view

        expect { root.draw(quiet, view) }.to allocate_nothing
      end
    end
  end
end
