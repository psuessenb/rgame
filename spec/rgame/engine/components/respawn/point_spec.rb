# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Respawn::Point do
  it_behaves_like 'a respawn point' do
    def point_at(place)
      location = respawn_world.location(place)
      described_class.new(x: location.x, y: location.y)
    end
  end
end
