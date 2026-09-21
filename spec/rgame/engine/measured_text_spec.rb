# frozen_string_literal: true

# Engine code measuring text for layout and handing the same typeface to the
# renderer: a node measures a string while updating, then draws it with it.
# spec_core/rgame/core/renderer_spec.rb draws the same thing in a real window
# and checks the ink stays inside the measured box.
RSpec.describe 'a node that lays out text with a typeface' do # rubocop:disable RSpec/DescribeClass -- the subject is two layers used together
  let(:banner_class) do
    Class.new(RGame::Engine::Node2D) do
      def initialize(title, box_width)
        super()
        @title = title
        @box_width = box_width
        @face = RGame::Util::Typeface.default(24)
      end

      def on_update(_dt) = @left = (@box_width - @face.text_width(@title)) / 2

      def on_draw(renderer, _view) = renderer.text(@title, @left, 0, font: @face)
    end
  end

  let(:renderer) { FakeRenderer.new }

  def drawn(title, box_width)
    banner = banner_class.new(title, box_width)
    banner.update(1 / 60.0)
    banner.draw(renderer, screen_view)
    renderer.calls_to(:text).last
  end

  it 'draws with the typeface it measured with' do
    expect(drawn('Hamburgefonstiv', 256).options[:font]).to be(RGame::Util::Typeface.default(24))
  end

  it 'lands the measured string inside its box, centred' do
    call = drawn('Hamburgefonstiv', 256)
    left = call.args[1]
    right = left + renderer.text_width('Hamburgefonstiv', font: call.options[:font])

    expect(left).to be_positive
    expect(256 - right).to be_within(1e-9).of(left)
  end
end
