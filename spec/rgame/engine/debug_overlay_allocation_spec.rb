# frozen_string_literal: true

# Guards the overlay's load-bearing promise: it counts the game's allocations, so it
# must make none of its own. It samples once a tick and draws once a frame, and each
# number it shows changes once a second, so it draws them digit by digit from cached
# glyph strings rather than building a String each time one changes.
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

  # A thousand ticks at 60 a second close sixteen seconds, so the tick that
  # publishes a second is measured as well as the ticks that only sample. The
  # warm-up closes one first, because Ruby fills that path's caches on its
  # first run.
  it 'samples without allocating per tick' do
    expect { overlay.update(1.0 / 60) }.to allocate_nothing.after_warmup(61)
  end
end
