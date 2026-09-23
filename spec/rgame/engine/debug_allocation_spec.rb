# frozen_string_literal: true

# The debug layer is mounted in every game, including the ones nobody is
# debugging, so its draw path is a per-frame path like any other: with every
# channel off it must cost nothing, and the shapes must cost nothing while on.
RSpec.describe RGame::Engine::Debug do
  subject(:debug) { described_class.new }

  let(:renderer) { QuietRenderer.new }
  let(:view) { screen_view }

  it 'draws nothing, and allocates nothing, with every channel off' do
    expect { debug._draw(renderer, view) }.to allocate_nothing
  end

  it 'allocates nothing with a channel of the game\'s own on' do
    debug.define(:routes) { |r, _v| r.rect(0, 0, 4, 4) }
    debug.show(:routes)

    expect { debug._draw(renderer, view) }.to allocate_nothing
  end

  it 'allocates nothing asking whether a channel is on' do
    expect { debug.shows?(:shapes) }.to allocate_nothing
  end
end
