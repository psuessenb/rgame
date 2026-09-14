# frozen_string_literal: true

# Guards TileBlockers' per-frame path with the `allocate_nothing` matcher: every mover declaring
# `blocked_by: [:tiles]` resolves against it every frame. Built the way a Components::TileWorld
# builds one, over a Util::SolidGrid. A Navigator asks it #travel? while it plans, so that is
# guarded too.
RSpec.describe RGame::Engine::TileBlockers do
  subject(:blockers) { described_class.new(grid: grid, tile_width: 16, tile_height: 16) }

  let(:grid) { RGame::Util::SolidGrid.build(20, 20) { |col, row| col == 5 || row == 5 } }

  it 'resolves a step through open ground without allocating' do
    expect { blockers.resolve_x(16.5, 20.25, 12, 6, 1.5) + blockers.resolve_y(16.5, 20.25, 12, 6, 1.5) }
      .to allocate_nothing
  end

  it 'resolves a step into a wall without allocating' do
    expect { blockers.resolve_x(62.5, 20.25, 12, 6, 3.0) + blockers.resolve_y(20.5, 62.5, 12, 6, 3.0) }
      .to allocate_nothing
  end

  it 'answers a travel without allocating' do
    expect { blockers.travel?(16.5, 20.25, 12, 6, 40.0, 30.0) | blockers.travel?(16.5, 20.25, 12, 6, 90.0, 0.0) }
      .to allocate_nothing
  end
end
