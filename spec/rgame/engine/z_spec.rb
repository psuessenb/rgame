# frozen_string_literal: true

# Nothing enforces the bands — a z is an Integer a caller passes, and no guard
# can tell a HUD apart from a rock. What can be checked is that the numbers
# themselves still say what the vocabulary claims, which is the thing a later
# edit would quietly break.
RSpec.describe RGame::Engine::Z do
  describe 'the order of the bands' do
    it 'puts a player\'s HUD above the world it covers' do
      expect(described_class::HUD).to be > described_class::WORLD
    end

    it 'puts a full-screen overlay above any player\'s HUD' do
      expect(described_class::OVERLAY).to be > described_class::HUD
    end

    it 'puts the debug overlay above everything' do
      expect(described_class::DEBUG).to be > described_class::OVERLAY
    end
  end

  # Bases, not slots: a HUD element three layers up is `HUD + 3`, and the gap to
  # the next band is what a game gets to use. A band separation of one would
  # order correctly and still be useless.
  describe 'the room between them' do
    it 'leaves the world tens of thousands of layers' do
      expect(described_class::HUD - described_class::WORLD).to be >= 10_000
    end

    it 'leaves a HUD room of its own under the overlay band' do
      expect(described_class::OVERLAY - described_class::HUD).to be >= 10_000
    end
  end

  describe 'what uses them' do
    it 'is where the debug overlay draws' do
      expect(RGame::Engine::DebugOverlay::Z).to eq(described_class::DEBUG)
    end

    # The tile map's two bands are world content and belong under the HUD, along
    # with everything else a camera scrolls.
    it 'contains the tile map\'s ground and canopy layers' do
      canopy = RGame::Engine::Components::TileWorld::CANOPY_Z
      ground = RGame::Engine::Components::TileWorld::GROUND_Z
      expect([ground, canopy]).to all(be_between(described_class::WORLD, described_class::HUD))
    end
  end
end
