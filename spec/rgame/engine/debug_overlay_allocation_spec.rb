# frozen_string_literal: true

# Guards the overlay's load-bearing promise: the stats it shows change every frame, so
# it draws numbers digit-by-digit from cached glyph strings rather than building a String
# per frame. Drawing must therefore allocate ~nothing in steady state.
RSpec.describe RGame::Engine::DebugOverlay do
  # A faithful, allocation-free stand-in for RGame::Core::Renderer: explicit keyword
  # params (like the real #text) so a call doesn't collect a keyword Hash, and a plain
  # object rather than an RSpec double (doubles allocate per call).
  let(:renderer) do
    Class.new do
      def text(string, x, y, z: 0, color: nil); end
      def text_width(_string) = 10
      def text_height = 16
    end.new
  end

  it 'draws without allocating per frame' do
    overlay = described_class.new
    overlay.toggle
    # One view, built once: the platform reuses its Views frame to frame, and
    # building a fresh one per call here would measure this spec instead.
    view = screen_view
    overlay.draw(renderer, view, 60) # warm up: measure and cache digit/label widths

    before = GC.stat(:total_allocated_objects)
    1000.times { overlay.draw(renderer, view, 60) }
    after = GC.stat(:total_allocated_objects)

    expect(after - before).to be < 100
  end
end
