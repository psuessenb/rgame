# frozen_string_literal: true

# Save and load, part two — when the save has to name things.
#
# Run it:
#
#   ruby examples/save_load_ids/main.rb
#
# Arrows walk the dog. **Tab** points it at the next sheep, **Space** shears the
# one it is pointing at, **N** brings in a new one. **F5** saves, **F9** loads,
# **Delete** discards. Every sheep is labelled with its id, and the line from the
# dog shows which one it is watching. It exercises:
#   - Components::Identity — a stable name for a node;
#   - Util::SaveFile — the same one `examples/save_load` uses;
#   - a save that holds records rather than a bare list of positions.
#
# ## Read `examples/save_load` first
#
# That one restores a dog by the variable holding it and a flock by array order,
# and both are correct for what they are. Nothing there needs an id, and adding
# one would have been ceremony.
#
# This is the case it does not cover.
#
# ## A collection is not what forces ids — a reference is
#
# It is tempting to say "the flock changes, so it needs ids", and that is not
# quite true. A collection can always be saved as *records* — each sheep writing
# its own position and wool — and rebuilt from them. Order stops mattering
# because nothing is being matched up: every sheep in the file becomes a sheep in
# the world, and that works whether three died or thirty arrived.
#
# What cannot be written that way is **the line from the dog to one particular
# sheep**. A node reference is a pointer into this run of the program; the next
# run has different objects at different addresses. The only thing that survives
# the gap is a name both runs agree on, and that is what `Identity` is:
#
#     target: Identity.of(@target)     # an id, or nil
#
# On load the flock is rebuilt from records, and then the dog is re-linked by
# looking for that id among the new sheep. That is the shape `Identity.of` is
# built for: it takes a node and answers an id, because what a game holds is
# always the node and what a file can hold is only ever the name.
#
# ## Why this is not `Components::Targeting`
#
# The engine already has a component that holds a target node, and it is the
# wrong tool here — which is worth saying, because "there is a component for
# that" is the first thing a reader will think.
#
# `Targeting` *derives* its target: every update it asks the scene's
# `CollisionWorld` for the nearest collider in range. So it holds a node without
# ever needing to write one down — a save that omitted it entirely would arrive
# at the same answer on the next frame. The dog here is the opposite: **Tab**
# chose this sheep, nothing can recompute that choice, and losing it is the thing
# a player would notice.
#
#   Targeting       proximity picks the target, every frame — derived
#   this example    the player picks it, and it has to survive quitting — chosen
#
# **Derived state is never saved; chosen state always is.** Sorting a game's
# facts into those two piles is most of designing a save file, and the question
# is cheaper than it looks: could the next frame work this out again? The flock's
# positions are chosen (the sheep wandered there), the wool is chosen (it grew),
# the tether is derived from the target — which is why the save holds a target
# and not a line.
#
# ## The allocator is part of the save, and forgetting it is the classic bug
#
# `@next_id` is saved and restored with everything else. It has to be: a counter
# that restarts at 1 on load hands out ids that the restored sheep are already
# using, and nothing complains at the time. What you see is a dog that follows
# the wrong animal, hours later, once a duplicate finally gets picked as a
# target. One number, and the whole scheme rests on it.
#
# Try it: save with a few sheep, quit, run again, press **N**. The new sheep gets
# the next number rather than a duplicate.
#
# ## An id that is no longer there
#
# `restore_target` falls back to any sheep when the saved id matches none of
# them. That is not defensive habit — a save file is the one input a game did not
# produce this run, and it can be hand-edited, copied from another machine, or
# written by an older version of the game with a different flock. Pointing at
# nothing is a legitimate state to arrive in, and picking a new target is a
# better answer than refusing to load.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

Controls = RGame::Util::Controls
Identity = RGame::Engine::Components::Identity

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

DOG_SPEED   = 150.0
SHEEP_SPEED = 35.0
STARTING_FLOCK = 5
DEFAULT_SEED = 0x5EED2

# One sheep: a position, an id, and wool that grows while it stands there.
#
# The wool is what makes this a *record* rather than a coordinate pair. A save
# that wrote only positions would restore a flock of freshly shorn sheep, and
# nobody would notice until they wondered why shearing never seemed to pay.
class Sheep < RGame::Engine::Node2D
  FLEECE = RGame::Util::Color.new(240, 240, 235)
  INK    = RGame::Util::Color.new(30, 40, 30)
  MIN_R  = 7.0
  MAX_WOOL = 9.0
  GROWTH = 1.4 # radius per second

  attr_reader :id
  attr_accessor :wool

  def initialize(id:, wool: 0.0, **)
    super(**)
    @id = id
    @wool = wool
    # Built once, on the way in. `renderer.text(@id.to_s, …)` would allocate a
    # String every frame for every sheep, which is what
    # Game/NoInterpolationInHotPath is about even though `to_s` is not
    # interpolation.
    @label = id.to_s
    add_component(Identity.new(id: id))
  end

  def on_update(dt)
    @wool = [@wool + (dt * GROWTH), MAX_WOOL].min
    self.x = x.clamp(0, WIDTH)
    self.y = y.clamp(40, HEIGHT)
  end

  def on_draw(renderer, _view)
    renderer.circle(0, 0, MIN_R + @wool, color: FLEECE)
    renderer.text(@label, MIN_R + MAX_WOOL + 4, -8, color: INK)
  end
end

class Pasture < RGame::Engine::Node2D
  GRASS  = RGame::Util::Color.new(96, 140, 84)
  DOG    = RGame::Util::Color.new(70, 50, 40)
  TETHER = RGame::Util::Color.new(250, 240, 180)
  DOG_R  = 11

  KEYS = 'F5 saves   F9 loads   Delete discards the save'

  STATUS = {
    fresh: 'no save yet — shear a few, add one, then press F5',
    restored: 'loaded the save from last time',
    saved: 'saved — quit, run again, then press N for a fresh id',
    loaded: 'loaded',
    deleted: 'save deleted'
  }.freeze

  def initialize(save:, **)
    super(**)
    @save = save
    @rng = Random.new(ENV.fetch('RGAME_SEED', DEFAULT_SEED).to_i)
    @flock = []
    @next_id = 1
    @status = :fresh
  end

  def on_add
    @dog = add_node(build_dog)
    STARTING_FLOCK.times { spawn_sheep }
    @target = @flock.first

    return unless @save.exist?

    load_state
    @status = :restored
  end

  def on_control(actions)
    target_next if actions.pressed?(:target_next)
    shear if actions.pressed?(:shear)
    spawn_sheep if actions.pressed?(:spawn)

    save_state if actions.pressed?(:save)
    load_state if actions.pressed?(:load)
    drop_save if actions.pressed?(:drop)
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: GRASS)
    # Between two nodes, so the scene draws it: it is the only thing that knows
    # both. The sheep draw themselves, over this.
    renderer.line(@dog.x, @dog.y, @target.x, @target.y, color: TETHER) if @target
    renderer.circle(@dog.x, @dog.y, DOG_R, color: DOG)

    renderer.text('Arrows walk   Tab targets   Space shears   N adds a sheep', 12, 12)
    renderer.text(KEYS, 12, 34)
    renderer.text(STATUS.fetch(@status), 12, 56)
  end

  private

  # --- the save ----------------------------------------------------------
  #
  # Records, not coordinates: each sheep writes everything about itself that the
  # next run cannot work out for itself.

  def save_state
    @save.write(
      next_id: @next_id,
      dog: [@dog.x, @dog.y],
      target: Identity.of(@target), # a node becomes an id, here and nowhere else
      sheep: @flock.map { |sheep| { id: sheep.id, x: sheep.x, y: sheep.y, wool: sheep.wool } }
    )
    @status = :saved
  end

  def load_state
    state = @save.read
    return if state.empty?

    @flock.each(&:queue_free)
    @flock = []
    state.fetch(:sheep, []).each { |record| restore_sheep(record) }
    # After the flock, because the target has to be found among the sheep that
    # now exist rather than the ones that used to.
    restore_target(state[:target])
    @dog.x, @dog.y = state[:dog] if state[:dog]
    # Restored, not recomputed. A counter that started again from the flock size
    # would collide with any id belonging to a sheep that has since been sheared.
    @next_id = state.fetch(:next_id, @flock.size + 1)
    @status = :loaded
  end

  def restore_sheep(record)
    @flock << add_node(build_sheep(record.fetch(:id), record.fetch(:x), record.fetch(:y),
                                   wool: record.fetch(:wool, 0.0)))
  end

  # The re-link, and the whole reason ids are here. `find` rather than an index:
  # the flock that comes back is a different set of objects in whatever order the
  # file listed them.
  def restore_target(id)
    @target = @flock.find { |sheep| sheep.id == id } || @flock.first
  end

  def drop_save
    @save.delete
    @status = :deleted
  end

  # --- the game ----------------------------------------------------------

  def target_next
    return if @flock.empty?

    index = @flock.index(@target) || -1
    @target = @flock[(index + 1) % @flock.size]
  end

  def shear
    return if @target.nil?

    @target.wool = 0.0
    sheared = @target
    @flock.delete(sheared)
    sheared.queue_free
    # The removed sheep leaves a hole in the middle of the flock, and every id
    # after it keeps the number it had. That is the property an array index
    # cannot give you.
    @target = @flock.first
  end

  def spawn_sheep
    id = @next_id
    @next_id += 1
    @flock << add_node(build_sheep(id, @rng.rand(WIDTH - 80) + 40, @rng.rand(HEIGHT - 120) + 80))
    @target = @flock.first if @target.nil?
  end

  def build_sheep(id, x, y, wool: 0.0)
    sheep = Sheep.new(id: id, wool: wool, x: x, y: y)
    sheep.add_component(RGame::Engine::Components::CharacterBody.new(speed: SHEEP_SPEED))
    sheep.add_component(RGame::Engine::Components::WanderController.new(rng: @rng))
    sheep
  end

  def build_dog
    dog = RGame::Engine::Node2D.new(x: WIDTH / 2, y: HEIGHT / 2)
    dog.add_component(RGame::Engine::Components::CharacterBody.new(speed: DOG_SPEED))
    dog.add_component(RGame::Engine::Components::PlayerController.new)
    dog
  end
end

save = RGame::Util::SaveFile.new('flock.json', game: 'rgame-examples',
                                               dir: ENV.fetch('RGAME_SAVE_DIR', nil))

game = RGame::Game.new(
  root: Pasture.new(save: save),
  caption: 'Save and load with ids',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  # F5 and F9 rather than S and L: **a key already in the default map keeps
  # doing its default job too.** `move_y` is bound to W and S, so a save action
  # on S would save *and* walk the dog downwards — two actions may read one key,
  # both fire, and nothing warns. F1 and F2 are not free either; RGame::Game
  # keeps them for the debug overlay and quit.
  #
  # Space is a deliberate exception: the default map has it on `fire` and
  # `ui_confirm`, and nothing here reads either, so sharing it costs nothing.
  input_map: RGame::Engine::InputMap.default.merge(
    target_next: { buttons: [Controls::KEY_TAB] },
    shear: { buttons: [Controls::KEY_SPACE] },
    spawn: { buttons: [Controls::KEY_N] },
    save: { buttons: [Controls::KEY_F5] },
    load: { buttons: [Controls::KEY_F9] },
    drop: { buttons: [Controls::KEY_DELETE] }
  )
)

game.start
