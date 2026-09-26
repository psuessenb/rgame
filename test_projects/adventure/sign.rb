# frozen_string_literal: true

module Adventure
  # The garden's sign, read by the first hero who walks in: a small scene for that
  # player alone.
  #
  # The sign carries the Components::Cutscene that plays it, with no camera, so
  # nothing is soloed and no room stops. It pauses the one hero, and the other
  # player's region goes on showing its own room. The sign answers to that hero's
  # player, so it is their confirm that ends the scene. It stands in the garden's
  # WorldView, so only the regions that show the garden draw it.
  class Sign < Engine::Node2D
    SCENE = Engine::Cutscene::Script.build do
      run { it.text = 'Keep off the flower beds' }
      wait 0.5
      press
      run(&:queue_free)
    end

    attr_accessor :text

    def initialize(hero:)
      super(x: hero.x, y: hero.y - 40, input_owner: hero.input_owner)
      @text = nil
      add_component(Components::Cutscene.new(SCENE, context: self, pause: [hero]))
    end

    def _draw(renderer, _view)
      renderer.text(@text, -60, 0) if @text
    end
  end
end
