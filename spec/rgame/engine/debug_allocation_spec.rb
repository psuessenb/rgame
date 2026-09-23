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

  # The one channel that draws every frame of every session somebody is
  # debugging, and the one whose own numbers a leak here would spoil. It is
  # measured through the system rather than against the overlay directly,
  # because that is the path a game runs, and `fps` arrives as the Float
  # RGame::Game hands over.
  it 'allocates nothing with the stats overlay on' do
    debug.show(:stats)
    debug.fps = 59.94

    expect { debug._draw(renderer, view) }.to allocate_nothing
  end

  # The shapes are the one thing here that draws every frame in a real game, so
  # they are measured with the channel on as well as off.
  describe 'the :shapes channel' do
    let(:root) do
      RGame::Engine::Node2D.new.tap do |node|
        node.add_component(debug)
        collider = node.add_node(RGame::Engine::Node2D.new(x: 40, y: 60))
        collider.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16))
        collider.add_component(RGame::Engine::Components::CircleCollider.new(radius: 8))
        node.enter_tree
      end
    end

    it 'allocates nothing while it is off' do
      expect { root.draw(renderer, view) }.to allocate_nothing
    end

    it 'allocates nothing while it is on' do
      debug.show(:shapes)

      expect { root.draw(renderer, view) }.to allocate_nothing
    end
  end

  # A WorldView walks the cells its viewport covers every frame the channel is
  # on, which is the loop most likely to build a Range or an Array by accident.
  describe 'the solid cells a WorldView draws' do
    let(:players) { RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0)]) }
    let(:viewports) { RGame::Engine::Viewports.new(players, width: 320, height: 240) }

    let(:root) do
      RGame::Engine::Node2D.new.tap do |node|
        node.add_component(players)
        node.add_component(viewports)
        node.add_component(debug)
        scene = node.add_node(RGame::Engine::Node2D.new)
        scene.scene = scene
        scene.add_component(RGame::Engine::Components::TileWorld.new(
                              map: WalledTileMap.build(['....', '.##.', '....']), tilemap_id: 'walls.tmx'
                            ))
        scene.add_node(RGame::Engine::WorldView.new)
        node.enter_tree
        viewports.refresh
      end
    end

    it 'allocates nothing while the channel is on' do
      debug.show(:shapes)

      expect { root.draw(renderer, view) }.to allocate_nothing
    end
  end
end
