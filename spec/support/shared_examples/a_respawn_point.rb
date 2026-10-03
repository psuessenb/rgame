# frozen_string_literal: true

# What every respawn point the engine offers promises to the Respawn holding it,
# stated once and run against each: Respawn::Point, and the points that follow.
#
# A Respawn calls a point by three method names and never asks its class, so a
# game may bring its own. The engine's points keep the contract here rather than
# trusting each other's specs, as the shared mover group does.
#
# ## What the host must provide
#
#   it_behaves_like 'a respawn point' do
#     def point_at(place) = ...
#   end
#
# `point_at` returns a point at one of the two places the group's map names:
# `'ground'`, at (8, 8), and `'gap'`, at (24, 24), over a gap cell. The group
# builds the rest: a Scene::Room named `:yard` holding a TileWorld over that map,
# `respawn_world`, and a node standing in the room at (100, 100),
# `respawn_node`. The names are prefixed so they cannot shadow the host's own.
RSpec.shared_examples 'a respawn point' do
  let(:respawn_world) do
    RGame::Engine::Components::TileWorld.new(
      map: WalledTileMap.build(['....', '.~~.', '....'], objects: [['ground', 8, 8], ['gap', 24, 24]]),
      tilemap_id: 'map/yard.tmx'
    )
  end

  let(:respawn_room) do
    RGame::Engine::Scene::Room.new.tap do |room|
      room.name = :yard
      room.scene = room
      room.add_component(respawn_world)
    end
  end

  let(:respawn_node) { respawn_room.add_node(RGame::Engine::Node2D.new(x: 100.0, y: 100.0)) }

  before do
    respawn_node
    RGame::Engine::Node2D.new.add_node(respawn_room)
    respawn_room.root.enter_tree
  end

  it 'names its room with a Symbol, or nil when it has none' do
    expect(point_at('ground').room).to be_nil.or be_a(Symbol)
  end

  it 'raises ArgumentError from check_ground over a gap' do
    expect { point_at('gap').check_ground(respawn_world) }.to raise_error(ArgumentError, /gap/)
  end

  it 'checks nothing over ground' do
    expect { point_at('ground').check_ground(respawn_world) }.not_to raise_error
  end

  it 'places a node standing in its room at once, answering true' do
    landed = point_at('ground').place(respawn_node)

    expect([landed, respawn_node.world_x, respawn_node.world_y]).to eq([true, 8.0, 8.0])
  end

  it 'is a frozen value, so two Respawns may hold the same one' do
    point = point_at('ground')

    expect([point.frozen?, point == point_at('ground')]).to eq([true, true])
  end
end
