# frozen_string_literal: true

module TiledWorld
  # A scripted moment that interrupts the split.
  #
  # It lives *outside* the WorldView, so it draws once across the whole window in
  # screen space, and it keeps ticking while the world it covers is frozen. It is
  # in the `:overlay` band, which is above both the world and either player's HUD
  # — the one thing on screen during a cutscene.
  #
  # The scene is a `Cutscene::Script` run by a `Components::Cutscene` with a
  # camera, so everybody watches: the component collapses the split onto that
  # camera, suspends the world it is handed in `pause:`, and stops joins, then
  # gives all three back as the script ends. The script only shows the panel and
  # the hint, and waits for Tab.
  #
  # The node is owned by `Players#everyone`, so either player starts it and either
  # carries on.
  #
  # A real game would trigger this from a trigger volume or a script beat rather
  # than a key. It reads a key here so the test project can be driven.
  class Cutscene < Engine::Node2D
    TITLE = 'Something happens on the beach'
    HINT  = 'Tab to carry on'
    PANEL_W = 460
    PANEL_H = 120
    TITLE_COLOR = Util::Color.new(40, 30, 20)
    HINT_COLOR  = Util::Color.new(90, 78, 62)
    HINT_DELAY = 0.4

    SCENE = Engine::Cutscene::Script.build do
      run(&:show_panel)
      wait HINT_DELAY
      run(&:show_hint)
      press :cutscene
    end

    def initialize(world_view:)
      super(band: :overlay)
      @world_view = world_view
      @open = false
      @hint = false
      @camera = Engine::Camera.new
    end

    def _enter_tree
      @players = root.system(Engine::Players)
      self.input_owner = @players.everyone
      system(Components::TileWorld).bound(@camera)
    end

    def _control(actions)
      start if !@open && actions.pressed?(:cutscene)
    end

    def _draw(renderer, view)
      return unless @open

      x = view.x + ((view.width - PANEL_W) / 2)
      y = view.y + ((view.height - PANEL_H) / 2)
      renderer.nine_slice(:panel, x, y, PANEL_W, PANEL_H)
      centered(renderer, TITLE, view, y + 34, TITLE_COLOR)
      centered(renderer, HINT, view, y + 74, HINT_COLOR) if @hint
    end

    def show_panel = @open = true
    def show_hint = @hint = true

    private

    def centered(renderer, text, view, y, color)
      x = view.x + ((view.width - renderer.text_width(text)) / 2)
      renderer.text(text, x, y, z: 1, color: color)
    end

    def start
      remove_component(Components::Cutscene)
      @camera.center_on(*midpoint)
      scene = Components::Cutscene.new(SCENE, context: self, camera: @camera, pause: [@world_view])
      scene.on_ended { close }
      add_component(scene)
    end

    def close
      @open = false
      @hint = false
    end

    def midpoint
      active = @players.each_active.to_a
      return [0.0, 0.0] if active.empty?

      [active.sum { |p| p.camera.target_x } / active.size,
       active.sum { |p| p.camera.target_y } / active.size]
    end
  end
end
