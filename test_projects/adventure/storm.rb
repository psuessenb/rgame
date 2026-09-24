# frozen_string_literal: true

# A storm over the whole window: a pale flash every few seconds.
#
# It is a ScreenFade at the root, so it draws once a frame across the window
# rather than once per player's region, over the world and both bags. A
# Components::Timer paces it, so it keeps time with the game's ticks and stops
# with them.
class Storm < RGame::Engine::ScreenFade
  EVERY = 4.0
  FLASH = 0.25
  GLARE = RGame::Util::Color.new(220, 230, 255, 90)

  def initialize
    super(color: GLARE)
    add_component(RGame::Engine::Components::Timer.new(EVERY)).on_elapsed { flash(FLASH) }
  end
end
