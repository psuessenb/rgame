# frozen_string_literal: true

# A scripted moment that interrupts the split.
#
# It lives *outside* the WorldView, so it draws once across the whole window in
# screen space, and it keeps ticking while the world it covers is frozen. It is
# in the `:overlay` band, which is above both the world and either player's HUD
# — the one thing on screen during a cutscene. Three things happen together when
# it opens, and they are separate mechanisms doing separate jobs:
#
#   viewports.solo!(camera)     collapse the split to one screen-wide view
#   world_view.paused = true    stop the world; this node is not under it, so it
#                               carries on and can animate
#   players.accepting_joins = false   nobody joins mid-scene
#
# A real game would trigger this from a trigger volume or a script beat rather
# than a key. It reads a key here so the test project can be driven.
class Cutscene < RGame::Engine::Node2D
  TITLE = 'Something happens on the beach'
  HINT  = 'Tab to carry on'
  PANEL_W = 460
  PANEL_H = 120
  TITLE_COLOR = [40, 30, 20].freeze
  HINT_COLOR  = [90, 78, 62].freeze

  def initialize(world_view:)
    super(band: :overlay)
    @world_view = world_view
    @open = false
    @camera = RGame::Engine::Camera.new
    @elapsed = 0.0
  end

  def on_add
    @players = root.system(RGame::Engine::Players)
    @viewports = root.system(RGame::Engine::Viewports)
    # The cinematic camera is bounded by the map like a player's, so the scene
    # cannot show past the world's edges. A shot that wanted to would leave it
    # unbounded — that is the only decision a camera nobody owns has to make.
    system(RGame::Engine::Components::TileWorld).bound(@camera)
  end

  # Either player can start or end it, so this reads every seat rather than
  # whichever one happens to own this node.
  def on_control(_actions)
    return unless @players.any? { |player| player.actions.pressed?(:cutscene) }

    @open ? close : open
  end

  # It animates while the world does not — which is the whole point of pausing a
  # subtree rather than the tick.
  def on_update(dt)
    @elapsed += dt if @open
  end

  def on_draw(renderer, view)
    return unless @open

    x = view.x + ((view.width - PANEL_W) / 2)
    y = view.y + ((view.height - PANEL_H) / 2)
    renderer.nine_slice(:panel, x, y, PANEL_W, PANEL_H)
    centered(renderer, TITLE, view, y + 34, TITLE_COLOR)
    centered(renderer, HINT, view, y + 74, HINT_COLOR) if @elapsed > 0.4
  end

  private

  def centered(renderer, text, view, y, color)
    x = view.x + ((view.width - renderer.text_width(text)) / 2)
    # z: 1 — above this node's own panel, and that is all it can mean.
    renderer.text(text, x, y, z: 1, color: color)
  end

  def open
    @open = true
    @elapsed = 0.0
    @camera.center_on(*midpoint)
    @viewports.solo!(@camera)
    @world_view.paused = true
    @players.accepting_joins = false
  end

  def close
    @open = false
    @viewports.split!
    @world_view.paused = false
    @players.accepting_joins = true
  end

  # Frame everyone at once. A camera nobody owns has to be pointed at something,
  # and the midpoint of the people playing is the obvious thing for a scene that
  # pulled them out of their own views.
  def midpoint
    active = @players.each_active.to_a
    return [0.0, 0.0] if active.empty?

    [active.sum { |p| p.camera.target_x } / active.size,
     active.sum { |p| p.camera.target_y } / active.size]
  end
end
