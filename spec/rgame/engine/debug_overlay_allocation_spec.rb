# frozen_string_literal: true

# Guards the overlay's load-bearing promise: the stats it shows change every frame, so
# it draws numbers digit-by-digit from cached glyph strings rather than building a String
# per frame. Drawing must therefore allocate nothing in steady state.
#
# It measures against QuietRenderer rather than a fake of its own, because the
# overlay's cost is not all in the overlay. A renderer coerces every colour it is
# handed, so what a draw *passes* costs as much as what it builds, and a fake
# that ignores its `color:` cannot see that half. QuietRenderer coerces, as
# RGame::Core::Renderer#packed does.
RSpec.describe RGame::Engine::DebugOverlay do
  subject(:overlay) { described_class.new }

  # One view, built once: the platform reuses its Views frame to frame, and
  # building a fresh one per call here would measure this spec instead.
  let(:renderer) { QuietRenderer.new }
  let(:view) { screen_view }

  it 'draws without allocating per frame' do
    overlay.restart

    expect { overlay.draw(renderer, view, 59.94) }.to allocate_nothing
  end
end
