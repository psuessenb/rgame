# frozen_string_literal: true

# Guards the floor's per-frame path with the `allocate_nothing` matcher: every mover declaring
# `blocked_by: [:gaps]` resolves against GapBlockers every frame, and asks TileWorld about the
# floor to do it.
RSpec.describe RGame::Engine::GapBlockers do
  subject(:blockers) { world.gap_blockers }

  let(:world) do
    RGame::Engine::Components::TileWorld.new(
      map: WalledTileMap.build(['......', '..~~..', '..~~..', '......']), tilemap_id: :map
    )
  end

  it 'answers floor_at? without allocating' do
    world.floor_at?(0.0, 0.0)
    expect { world.floor_at?(20.5, 20.25) || world.floor_at?(40.5, 20.25) }.to allocate_nothing
  end

  it 'resolves a step across open floor without allocating' do
    expect { blockers.resolve_x(0.5, 50.25, 12, 6, 1.5) + blockers.resolve_y(0.5, 50.25, 12, 6, 1.5) }
      .to allocate_nothing
  end

  it 'resolves a step into a gap without allocating' do
    expect { blockers.resolve_x(10.5, 30.25, 12, 6, 20.0) + blockers.resolve_x(70.5, 30.25, 12, 6, -20.0) }
      .to allocate_nothing
  end
end
