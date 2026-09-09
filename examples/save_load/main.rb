# frozen_string_literal: true

# Save and load — writing game state to disk, and putting it back.
#
# Run it:
#
#   ruby examples/save_load/main.rb
#
# Arrow keys walk the dog. **F5** saves, **F9** loads, **Delete** throws the save
# away. Quit and run it again: the dog and the sheep are where you left them,
# because a save found at startup is loaded before the first frame. It
# exercises:
#   - Util::SaveFile — one JSON file, written atomically, read forgivingly;
#   - the same Node2D + CharacterBody + controller composition as
#     `examples/walk`, with the flock on a WanderController instead;
#   - `RGAME_SEED`, so a run without a save is reproducible.
#
# ## The tree is not saved, and nothing here tries
#
# This is the shape every comparable engine settles on: **a scene is a recipe
# and a save file is state.** The scene builds itself the same way every time,
# and the save supplies the handful of facts that differ between runs. Godot's
# own guidance is this, and it is why an rgame node has no name, no path and no
# id — nothing needs one.
#
# Two kinds of thing are being restored here, and they need different answers.
#
# **The dog is singular, so a variable is its identity.** `@dog` is set where the
# dog is built, and `load_state` writes straight to it. There is no lookup, no
# name, nothing to match up — the code that made the dog is the code that puts
# it back, and it never lost track of which one it was.
#
# **The sheep are interchangeable, so their order is their identity.** The save
# holds an array of positions; loading walks the flock and the array together.
# If sheep three and seven swapped places nothing observable would change, which
# is exactly what "interchangeable" means, and it is the property that makes an
# array enough.
#
# ## What would break this, and what to do about it
#
# The flock is a fixed size and no sheep can die. That is what lets an array
# index stand in for identity — and it is the assumption to check before copying
# this shape. The moment sheep can be killed, and the survivors must keep their
# own hunger and name across a save, the array stops meaning anything and each
# sheep needs an id of its own.
#
# `Components::Identity` is that id, and `examples/save_load_ids` is where it is
# shown: sheep that can be lost, and a dog chasing one particular sheep — a
# reference between two saved things, which is what genuinely forces a name.
# Unreal's save libraries bolt a GUID onto every actor for the same reason, and
# Unity's community does the same.
#
# ## Position is not the whole of where something is
#
# The sheep resume standing still, because a WanderController's timer is not
# saved. That is a deliberate simplification and worth naming, because the real
# version of this bug is not funny: a game that saves a falling player's position
# and not their velocity restores them hanging in the air.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

Controls = RGame::Util::Controls

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

DOG_SPEED   = 150.0
SHEEP_SPEED = 40.0
SHEEP_COUNT = 8

# Seeded, so a fresh run with no save always lays the flock out the same way and
# two driven runs can be compared.
DEFAULT_SEED = 0x5EED

class Pasture < RGame::Engine::Node2D
  GRASS = RGame::Util::Color.new(96, 140, 84)
  DOG   = RGame::Util::Color.new(70, 50, 40)
  SHEEP = RGame::Util::Color.new(240, 240, 235)
  DOG_R = 11
  SHEEP_R = 9

  KEYS = 'F5 saves   F9 loads   Delete discards the save'

  STATUS = {
    saved: 'saved — quit and run again, or press F9',
    loaded: 'loaded',
    deleted: 'save deleted',
    fresh: 'no save yet — walk the dog, then press F5',
    restored: 'loaded the save from last time'
  }.freeze

  def initialize(save:, **)
    super(**)
    @save = save
    @rng = Random.new(ENV.fetch('RGAME_SEED', DEFAULT_SEED).to_i)
    @flock = []
    @status = :fresh
  end

  def on_add
    # Built first, always, and identically. The save does not decide what exists
    # — only where it is.
    @dog = add_node(build_walker(RGame::Engine::Components::PlayerController.new,
                                 DOG_SPEED, WIDTH / 2, HEIGHT / 2))
    SHEEP_COUNT.times do
      @flock << add_node(build_walker(
                           RGame::Engine::Components::WanderController.new(rng: @rng),
                           SHEEP_SPEED, @rng.rand(WIDTH - 40) + 20, @rng.rand(HEIGHT - 80) + 60
                         ))
    end

    return unless @save.exist?

    load_state
    @status = :restored
  end

  def on_control(actions)
    save_state if actions.pressed?(:save)
    load_state if actions.pressed?(:load)
    drop_save if actions.pressed?(:drop)
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: GRASS)
    @flock.each { |sheep| renderer.circle(sheep.x, sheep.y, SHEEP_R, color: SHEEP) }
    renderer.circle(@dog.x, @dog.y, DOG_R, color: DOG)

    renderer.text('Arrows walk the dog', 12, 12)
    renderer.text(KEYS, 12, 34)
    renderer.text(STATUS.fetch(@status), 12, 56)
  end

  private

  # The whole save: two facts, written as plain numbers.
  #
  # Reading `sheep.x` from outside the node is fine here and is not the thing
  # Game/DrawInLocalSpace forbids — that rule is about a node reading its *own*
  # position while drawing, when its transform has already been applied.
  def save_state
    @save.write(dog: [@dog.x, @dog.y], sheep: @flock.map { |sheep| [sheep.x, sheep.y] })
    @status = :saved
  end

  def load_state
    state = @save.read
    place(@dog, state[:dog])
    # `zip` stops at the shorter of the two, so a save written when the flock
    # was a different size restores what it can instead of raising. That is the
    # cheap half of the versioning problem; the expensive half is a save whose
    # *shape* changed, which needs a version number in the file.
    @flock.zip(state.fetch(:sheep, [])) { |sheep, position| place(sheep, position) }
    @status = :loaded
  end

  def drop_save
    @save.delete
    @status = :deleted
  end

  def place(node, position)
    return if position.nil?

    node.x, node.y = position
  end

  def build_walker(controller, speed, x, y)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    node.add_component(RGame::Engine::Components::CharacterBody.new(speed: speed))
    node.add_component(controller)
    node
  end
end

# `dir:` is normally left out, and the file lands in the platform's own data
# directory — ~/.local/share, Application Support or %APPDATA%. It is overridable
# here so a driven run can write somewhere disposable instead of into the home
# directory of whoever happens to be running it.
save = RGame::Util::SaveFile.new('pasture.json', game: 'rgame-examples',
                                                 dir: ENV.fetch('RGAME_SAVE_DIR', nil))

game = RGame::Game.new(
  root: Pasture.new(save: save),
  caption: 'Save and load',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  # F5 and F9 rather than S and L, and the reason is worth knowing: **a key
  # already in the default map keeps doing its default job too.** `move_y` is
  # bound to W and S, so an action added on S saves *and* walks the dog
  # downwards — both fire, because two actions may read one key. Nothing is
  # broken and nothing warns; the game just moves when you asked it to save.
  #
  # F5 and F9 are free, and are what a player already expects quicksave and
  # quickload to be. F1 and F2 are not free: RGame::Game keeps those for the
  # debug overlay and quit.
  input_map: RGame::Engine::InputMap.default.merge(
    save: { buttons: [Controls::KEY_F5] },
    load: { buttons: [Controls::KEY_F9] },
    drop: { buttons: [Controls::KEY_DELETE] }
  )
)

game.start
