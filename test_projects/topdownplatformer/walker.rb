# frozen_string_literal: true

# The NPC: it wanders on the ring, and `blocked_by: :gaps` keeps it there. It
# stands in a hero's way, and a hero in its way stops it. Its Footing is what
# boards it onto the ring, so the ring carries it round.
#
# It draws the word NPC above its head, so a driven run counts it in each view.
class Walker < RGame::Engine::Node2D
  SPEED = 30.0

  LABEL = 'NPC'

  def initialize(**)
    super
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::FeetCollider.new(width: Hero::FEET_WIDTH, height: Hero::FEET_HEIGHT,
                                                              layer: :npc))
    add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED, blocked_by: %i[tiles gaps hero]))
    add_component(RGame::Engine::Components::WanderController.new)
    add_component(RGame::Engine::Components::Footing.new)
  end

  def _draw(renderer, _view)
    renderer.text(LABEL, -10, -36)
  end
end
