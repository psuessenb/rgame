# frozen_string_literal: true

# Example 15 — Tiled world walkaround (Node2D/Component architecture).
#
# Rebuilds the tiled-map + collision + follow-camera idea of example 08 on the new
# scene graph: a controllable player and several randomly-walking NPCs roam the larger
# beach map, the camera keeps the player centred (clamping at the map edges), and the
# palm canopies draw over the actors while the trunks stay behind. It exercises:
#   - TileWorld — a scene-scoped system: tile collision, world bounds, map drawing;
#   - CharacterBody + PlayerController / WanderController — collision-checked walking;
#   - AnimatedSprite — directional sprite-sheet animation;
#   - CameraView + renderer.translated — the camera as a draw-time view transform.

# lib/ on the load path, so `require 'rgame/game'` resolves the same way it
# would from an installed gem — which is also how the compiled extensions are
# found.
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'
require_relative 'beach_scene'

WIDTH  = 640
HEIGHT = 480
MEDIA  = File.join(__dir__, '../../media')

# Minimal root: a SceneStack with the single beach scene pushed once it's live.
class Root < RGame::Engine::Node2D
  def initialize
    super
    @stack = add_component(RGame::Engine::Scene::SceneStack.new)
  end

  def on_add = @stack.push(BeachScene.new)
end

# The game owns the asset manager (rooted at media/); the scene and its components
# resolve what they need from it by relative path (via node.root.context.assets), so
# nothing is loaded, registered, or passed down here.
RGame::Game.new(
  root: Root.new,
  caption: 'Example 15 - Tiled World',
  width: WIDTH,
  height: HEIGHT,
  media_root: MEDIA
  # No input_map: :move_x / :move_y are RGame::Engine::InputMap's defaults, on
  # the arrow keys and the left stick alike. Plug in a controller and walk.
).start
