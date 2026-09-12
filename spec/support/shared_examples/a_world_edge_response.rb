# frozen_string_literal: true

# What every response to the edge of the world promises about *where* that edge is, stated
# once and run against each of them — ScreenWrap, DespawnOffscreen, and a Mover declaring
# `blocked_by: [:bounds]`.
#
# They respond differently (wrap, free, stop) and each has its own spec for that. What they
# share is the frame: the edge is at the world's 0 and the world's width, measured in world
# coordinates, whatever container the node happens to sit in. A response that read the
# node's local position would pass its own spec, where the node's parent sits at the origin,
# and misfire in any scene that groups its entities under an offset node — so the frame is
# checked here, with that offset in place, rather than trusted.
#
# ## What the host must provide
#
#   it_behaves_like 'a world edge response' do
#     def add_response(node, vx:) = ...
#     def responded?(node, from) = ...
#   end
#
# `add_response` adds to an unattached node whatever the response needs, *including the
# motion* — a Velocity at `vx` px/s, or the mover under test moving at it. `responded?` says
# whether the response has happened yet, given the world x the node started from.
#
# The group builds the rest: a scene with a 200x100 `World`, a container at an offset, and a
# node inside it that starts well inside the world while its *local* x is outside it. At 60
# ticks a second the node moves a pixel a step, so it is ten steps from the edge a 10-wide
# box stops at, and twenty from the edge a bare origin passes.
#
# The names below are prefixed so they cannot shadow, or be shadowed by, the host spec's own.
RSpec.shared_examples 'a world edge response' do
  def edge_dt = 1.0 / 60

  let(:edge_scene) do
    RGame::Engine::Node2D.new.tap do |scene|
      scene.scene = scene
      scene.add_component(RGame::Engine::Components::World.new(width: 200, height: 100))
    end
  end

  # A node at `world_x`, placed inside a container at `container_x`, moving at `vx`.
  def enter_edge_node(world_x:, container_x:, vx:)
    container = RGame::Engine::Node2D.new(x: container_x, y: 20.0)
    node = RGame::Engine::Node2D.new(x: world_x - container_x, y: 30.0)
    add_response(node, vx: vx)
    container.add_node(node)
    edge_scene.add_node(container)
    edge_scene.enter_tree
    node
  end

  def run_edge_ticks(count) = count.times { edge_scene.update(edge_dt) }

  # World x 10 is local x -50: inside the world, outside it by the container's reckoning.
  describe 'moving left, under a container offset to the right' do
    let(:edge_node) { enter_edge_node(world_x: 10.0, container_x: 60.0, vx: -60.0) }

    it 'leaves the node alone while it is inside the world' do
      edge_node
      run_edge_ticks(5)
      expect(responded?(edge_node, 10.0)).to be(false)
    end

    it 'responds once it reaches the world’s left edge' do
      edge_node
      run_edge_ticks(20)
      expect(responded?(edge_node, 10.0)).to be(true)
    end
  end

  # World x 180 is local x 280: inside the world, past its width by the container's reckoning.
  describe 'moving right, under a container offset to the left' do
    let(:edge_node) { enter_edge_node(world_x: 180.0, container_x: -100.0, vx: 60.0) }

    it 'leaves the node alone while it is inside the world' do
      edge_node
      run_edge_ticks(5)
      expect(responded?(edge_node, 180.0)).to be(false)
    end

    it 'responds once it reaches the world’s right edge' do
      edge_node
      run_edge_ticks(30)
      expect(responded?(edge_node, 180.0)).to be(true)
    end
  end
end
