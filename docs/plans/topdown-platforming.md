# Top-down platforming

**Status: step 1 is implemented.** Five steps. Each is one branch and
one pull request, and each sub-step is one commit. **Steps 1 to 3 are
detailed.** Step 4, the test project, is rough and gets re-planned once step 3
lands. Step 5 folds the plan back and deletes it.

## Verdict

**Floor has one definition, and everything else asks it.** Floor is ground
wherever the map has no gap, plus the box of any platform over a gap.
`TileWorld#floor_at?` answers it. A node falls when it stands off the floor, a
`:gaps` blocker keeps a mover on it, and a platform carries whoever stands on
it.

The parts:

- **A tile whose class is `gap` makes its cell a gap**, on any layer.
  `TileWorld` reads the gaps once, as it reads solidity.
- **`Components::Footing` makes a node fall.** It watches the centre of the
  node's box. When that centre is off the floor and the node is not mid-hop,
  it allows `coyote` seconds, then drops the node. The node stops and shrinks
  into the gap through a new draw-only `Node2D#scale`.
- **`Components::Respawn` brings a fallen node back.** It places the node on
  its respawn point, returns control at once and flashes the node. A node with
  no `Respawn`, such as a crate, is freed. `Components::Checkpoint` moves the
  point when a hero touches it.
- **`Components::Platform` makes a moving node floor.** Its node's `Mover`
  carries every node standing on it after each step, whatever computed the
  step.
- **`blocked_by: [:gaps]` keeps a mover on the floor**, platforms included. An
  NPC walks around on a moving platform and never walks off it.

**`Hop` does not change.** A hop crosses a gap because a node in the air does
not fall.

## Goal

A test project on a Tiled map shows top-down platforming. It has gaps to fall
into or hop across, and a fall followed by a flashing respawn at the last
checkpoint. It has coyote time, and moving platforms boarded with a timed hop.
Every mechanic is an engine part a game adds as a component. Two small examples
show the mechanics alone.

The requirement, as given:

> Make a plan for a new test project, demonstrating top-down platforming:
>
> * gaps the player falls into when moving into them and can cross with jumps
> * a small fall animation
> * moving platforms the player has to time a jump
> * a respawn point the player gets teleported to after the fall (with a flashing respawn animation)
> * coyote time
> * all of this in a tiled world
>
> All of the concepts should be re-useable outside the test project, so make them engine parts (components etc.). If the concepts can be demonstrated with smaller, more isolated examples (stripped down to the essence of that feaures), add small examples as well.

## Hard constraints

1. **The engine layer may not name `RGame::Core`.** Everything here is
   engine-layer Ruby. The shrink draws through `renderer.scaled`, which the
   real renderer and the recording fake both answer.
2. **A per-frame path allocates nothing.** A footing's check, a floor query, a
   carry, a fall and a flash run every tick. `rake drive:allocations` decides.
3. **`draw` renders state.** The shrink and the flash advance in `update`, and
   nothing reads a clock.
4. **Every feature works with two players.** Two heroes ride one platform, and
   each keeps their own respawn point.
5. **An asset in `examples/assets` is CC0 or drawn here.** That directory ships
   in the gem.
6. **`require "rgame"` stays free of graphics.** Nothing here reaches Core.

## Decisions already taken

These were settled in one round of questions. They are not reopened inside
this plan.

1. **A respawn is its own component, not a `Rooms` move.** A respawn has a
   warp's shape: suspend, cover, place, reveal, resume. But `Rooms` is built
   around a player's region and the lifetime of rooms, and a fall concerns one
   node. Every example, and any game with one map, uses `Respawn` without
   `Rooms`.
2. **The fall shrinks the node toward its feet**, through a draw-only
   `Node2D#scale`. `draw` applies it the way it applies `opacity`. A negative
   `elevation` would slide the picture over the tiles south of the gap, and
   frames in the sheet need art the hero sheet does not have.
3. **Control returns as the node lands on its respawn point.** The flash only
   shows where it is, and the camera cuts there.
4. **A tile class `gap` marks a gap, on any layer**, as a collision shape marks
   a solid tile. A bridge is a floor tile painted where the gap tile was.
5. **The pit art is drawn here.** A script in `tools/` draws the pit tiles into
   `examples/assets`. Platforms draw Tiny Town's wooden tiles through a sheet
   descriptor over `tileset.png`.
6. **The centre of a node's box decides.** The node falls when the centre is
   off the floor, and it rides a platform when the centre is on one.
7. **The test project seats two players.** A second player joins by using a
   device, as in `test_projects/adventure`.
8. **Checkpoints are point objects of class `checkpoint`.** Touching one makes
   it the hero's respawn point. Where the hero starts is the first.
9. **Jump buffering stays out.** Step 5 adds a `possible-todos.md` entry about
   buffering input in general. No part of the engine buffers input today.
10. **`blocked_by: [:gaps]` is in.** The test project has an NPC that walks
    around on a platform. It stands in the way, and it never falls.
11. **A crate falls too.** A `Pushable` with a `Footing` falls like a hero. The
    test project shows one as a demonstration, not as a puzzle.
12. **Two small examples:** `examples/pits` and `examples/moving_platforms`.
    Checkpoints are a composition, so they appear in the test project only.
13. **This plan does not wait for y-sort's step 3.** Nothing here needs its
    one-tile draw.

## Open questions

None blocks steps 1 to 3.

1. **Platforms that wait at their ends.** A platform that pauses at a dock is
   easier to board. *Waits on step 4's map. Add it if a hop onto a platform
   that never stops proves too hard to time.*
2. **Momentum on leaving a platform.** Godot adds the platform's last velocity
   to a body that leaves it. Here a hop off a platform keeps only the node's
   own walk. *Waits on step 3's example. Add it if a hop off a moving platform
   feels wrong without it.*
3. **A pushed platform.** `Pushable` replaces `Mover#_update`, so a raft that a
   hero pushes carries nobody. *Waits on a game with a raft.*
4. **Routes around gaps.** `NavGrid` plans over solidity only. A `Navigator`
   routes straight through a gap, and a `:gaps` blocker stops it at the edge.
   *Waits on an NPC that plans routes near gaps.*
5. **A respawn point in a room left behind.** A `Rooms` move does not touch
   `Respawn`, so a hero who walked through a door keeps the old room's point.
   *Waits on a game with gaps in two rooms.*
6. **Platforms as Tiled tile objects.** Once y-sort's step 3 draws one tile, a
   platform could draw the tile object a designer placed. *Waits on y-sort's
   step 3.*
7. **"Gap" names two things.** A gap tile is a cell with no floor, and
   `TileMapLayer.mount`'s `gaps:` are the slots between layers where actors
   draw. Step 4's scene uses both in one line:
   `TileMapLayer.mount(view, gaps: { platforms: nil, actors: nil })`.
   `docs/api/tile_maps.md` says the two share only a word. Renaming either one
   (`pit`, `chasm`, or `slots:` for mount) is cheap while rgame has no users.
   *Blocks nothing. Decide before step 2 names `examples/pits` and its tiles.*

## What was measured before planning

At `712dbac`, on Ruby 4.0.5. The timings come from a scratch script outside the
repository.

| What | Result |
|---|---|
| `rake spec` | 3980 examples, 0 failures, 32.3 s |
| How far a hop carries the feet | 40 px. `examples/jump_topdown`'s hop lasts 0.5 s, and its hero walks at 80 px/s, as the heroes of `doors`, `cutscene` and the adventure do: two and a half 16-px tiles |
| Coyote time at Celeste's 0.1 s | 6 ticks at the fixed 60 Hz (`RGAME_TICK_SECONDS`), 8 px of walking |
| Tiles with a Tiled class | 0, in `examples/assets/tileset.tsx` and in `media/`'s beach tileset. `TileMap#tile_class` is read and never used |
| `TileMap.new` calls | 8, in `from_tiled` and the spec support. Gaps derived from `tile_classes` change none of them |
| `Util::SolidGrid#solid?` outside the grid | `false`, so a point off the map is floor |
| Reserved `blocked_by` names | 2, `:tiles` and `:bounds` |
| `Mover` subclasses | 4: `CharacterBody`, `Velocity`, `PathFollow`, `Pushable` |
| What carries a node today | nothing. `pushes:` and `Grab` move another node, but only by the mover's own step |
| Components that stop another node with `suspend` | 2, `Rooms` and `Cutscene`. Each runs on a node it does not stop |
| Components that judge "blocked" by how far the node moved | 1, `WanderController`. A carried NPC always moves, so it would never re-roll at a platform's edge *(read, not run)* |
| `PathFollow` users outside `lib/` and `spec/` | 2, the cutscene example and the adventure's lookout. Neither loops |
| A floor query: one cell lookup, then each platform | 126 ns with no platform, 184 ns with 4, 289 ns with 16. The queries allocate nothing |
| `draw`'s check for a node at scale 1 | 7 ns a node a draw when it shares `opacity`'s check. A method of its own costs about 40 ns |
| `renderer.scaled` | in `Core::Renderer` and in `FakeRenderer`, so the shrink needs no Core work |
| `Node2D` ivars a helper node must avoid | `@footing` among them: y-sort keeps the sorting collider there |

200 actors checking their footing against 16 platforms cost 58 µs a tick,
0.35% of a 60 Hz frame.

## What already resembles this

**Reuse it.**

- `Components::Hop` for the jump, and its `airborne?`, which is what keeps a
  hopping node from falling.
- `Node2D#opacity` for the flash, and `Node2D#suspend` and `#resume` for the
  hold during a fall.
- `Engine::Tween` for the shrink, and `Engine::Timer` for the blink.
- `BoxCollider` and `FeetCollider`: the box whose centre is where a node
  stands.
- `CollisionSystem`. A carried node moves through its own mover's blockers, so
  a wall scrapes a hero off a platform.
- `MapObjects` and `TileMap#objects`, to build platforms, checkpoints, the NPC
  and the crate from the map.
- `Engine::Path`. A polyline's points are already absolute pixels.
- A sprite-sheet descriptor, to draw Tiny Town tiles one at a time with
  `renderer.sprite`.
- `Collectable`'s shape for `Checkpoint`: listen to the node's own collider's
  `on_hit` for one layer.

**Extend or generalise it.**

- **Solidity gains a sibling fact.** `TileMap#solid_tile?` and the new
  `#gap_tile?` answer what a cell does to a walker, for two kinds of tile.
  `TileWorld` reads both once, into a grid each.
- **`:gaps` is the third reserved blocker source**, beside `:tiles` and
  `:bounds`. A mover declares it the same way.
- **`Platform` is `OccupiesCell` for floor.** Both change what the map means
  where a node stands, and both register with `TileWorld`. One makes a cell
  solid. The other makes part of a gap floor.
- **Carrying joins pushing in `Mover`.** A push and a carry both move another
  node because of this mover's step. Mover's header says it owns what happens
  after a step is computed, and a carry is that.
- **`Pushable#stopped?` moves up to `Mover`.** `WanderController` then asks its
  body whether a step was cut short, instead of measuring how far the node
  went.
- **`scale` joins `opacity`** as a drawing-only attribute that `Node2D#draw`
  applies around a node and its children.
- **`PathFollow` learns to loop**: round a closed route, and back and forth
  along an open one.

**Genuinely new.**

- **`Footing`: what a node stands on.** Nothing asks that today. Y-sort asks
  where a node stands, not what is under it.
- **`Respawn`**: a point, and a flash.
- **The fall itself**: a helper node that runs while the falling node is
  stopped.

The respawn closely resembles `Rooms#move`: suspend, cover, place, reveal,
resume. Decision 1 keeps the two apart.

## What a game writes

This is the composition that step 3's spec builds and step 4's project plays: a
hero, a platform, an NPC riding it and a crate. The sketch uses the names this
plan introduces, with the `Components::` prefix shortened.

```ruby
class Hero < RGame::Engine::Node2D
  def initialize(camera:, **)
    super(**)
    add_component(AnimatedSprite.new(sheet: 'hero.json'))
    add_component(FeetCollider.new(width: 12, height: 6, layer: :hero))
    add_component(CharacterBody.new(speed: 80, blocked_by: %i[tiles npc]))
    add_component(PlayerController.new)
    add_component(Hop.new(peak: 18, duration: 0.5))
    add_component(Footing.new(coyote: 0.1))
    add_component(Respawn.new(flash: 1.0))
    add_component(CameraFollow.new(camera:))
  end
end

class Raft < RGame::Engine::Node2D
  def initialize(route:, width:, height:)
    super()
    add_component(BoxCollider.new(width:, height:, offset_x: -width / 2.0,
                                  offset_y: -height / 2.0, layer: :platform))
    add_component(Platform.new)
    add_component(PathFollow.new(speed: 40, path: route, loop: true))
  end
end

class Walker < RGame::Engine::Node2D          # stands in the way, never falls
  def initialize(**)
    super(**)
    add_component(FeetCollider.new(width: 12, height: 6, layer: :npc))
    add_component(CharacterBody.new(speed: 30, blocked_by: %i[tiles gaps hero]))
    add_component(WanderController.new)
    add_component(Footing.new)
  end
end

class Crate < RGame::Engine::Node2D            # falls, and comes back where it started
  def initialize(**)
    super(**)
    add_component(BoxCollider.new(width: 16, height: 16, offset_x: -8, offset_y: -16, layer: :crate))
    add_component(Pushable.new(blocked_by: %i[tiles hero crate]))
    add_component(Footing.new(coyote: 0))
    add_component(Respawn.new(flash: 0.5))
  end
end
```

The scene mounts a `TileWorld` and a `CollisionWorld`, and leaves a slot for
the platforms under the actors:
`TileMapLayer.mount(view, gaps: { platforms: nil, actors: nil })`.

### The rules, in one place

1. **Floor** is ground where no layer has a gap tile, plus the box of every
   platform over a gap. A point off the map is floor, as a point off the map is
   not solid.
2. **A node stands at the centre of its `BoxCollider` box.**
3. **A node falls** once it has stood off the floor, on the ground, for more
   than `coyote` seconds after walking off. A node that lands on a gap falls at
   once. A node in the air never falls.
4. **A falling node stops**, shrinks over `fall` seconds, and then respawns, or
   is freed if it has no `Respawn`.
5. **A node rides the platform under its centre** where the cell is a gap,
   whether it is in the air or not. Where there is ground, it stands on the
   ground.
6. **A platform's mover carries its riders after each step**, front first along
   the step. Each rider goes through its own mover's blockers. A carry is not
   the rider's step, so it fires no `on_blocked`.
7. **`blocked_by: [:gaps]` keeps the centre of a mover's box on the floor.** A
   step that starts off the floor is free.
8. **Add order moves a result by at most one tick.** Nothing depends on which
   component was added first.

## Prior art

**Celeste** allows a jump for 0.1 s after the player leaves the ground:
`private const float JumpGraceTime = 0.1f;` in
[`Player.cs`](https://github.com/NoelFB/Celeste/blob/master/Source/Player/Player.cs).
The timer refills every tick the player is on the ground and runs down
otherwise. The actor answers whether it rides a solid: `Player` overrides
`IsRiding(Solid)` for each of its states. `LiftSpeed` passes a platform's
motion into a jump that leaves it.

**Godot 4**'s
[`CharacterBody2D`](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html)
follows moving platforms on the layers in `platform_floor_layers`, which the
rider declares. `platform_on_leave` decides what a body keeps on leaving one.
The default adds "the last platform velocity".

**The Zelda series** puts a player who falls into a pit "back at the beginning
of the room at the cost of a heart", from A Link to the Past on
([TV Tropes, Bottomless Pits](https://tvtropes.org/pmwiki/pmwiki.php/Main/BottomlessPits)).

**What they agree on.** A platform carries a rider when the rider says it is on
the platform. The grace time before a fall is short, and 0.1 s is the figure a
shipped game uses.

**What none of them gives us.** Celeste's and Godot's platforms are side-view.
Gravity holds a rider on top, so riding means touching the top edge. A top-down
platform has no top. Standing on it means standing over it where there is no
ground, so the platform is floor that the map lacks. That makes falling,
blocking and riding one question about the floor.

## Considered and rejected

- **A respawn as a `Rooms` move** (question 1, B). One mechanism would move
  every node to every spot. But every game with gaps would mount `Rooms`, and
  `Rooms` would learn a transition scoped to a node rather than a region.
- **A respawn as a cutscene script.** `run`, `wait` and `hold` can express
  "fall, place, flash", and `Cutscene` already suspends what it pauses. But the
  shrink's tween would need a host outside the hero and a copy into its scale
  every tick. The player press and skip that a cutscene is built around mean
  nothing here.
- **The fall run by a scene system**, on `TileWorld` or a new one. The scene
  keeps running while a game pauses its `WorldView`, so a fall under a pause
  menu would finish and respawn the hero behind it. It would also be one more
  system to mount. A helper node in the falling node's own parent pauses with
  the world, and needs mounting nowhere.
- **Holding the falling node's own components** instead of suspending it.
  Nothing in the engine gates a node's components but not its node, and an
  NPC's controller would keep steering while it shrank.
- **Riders pulling themselves along** by reading their platform's last step.
  Which updates first would decide whether a rider moves this tick or the next,
  so a rider would trail its platform in one add order and not the other.
- **Parenting the rider to the platform**, the common Unity answer. The rider
  would leave its y-sorted gap, inherit the platform's `input_owner`, and change
  its place in the update order each time it boarded.
- **`carries:` on a mover**, parallel to `pushes:`. The platform would declare
  which layers it carries, and the rider would still need `Footing` to know it
  stands there. Two declarations would have to agree, and one forgotten would
  leave a rider sliding off in silence.
- **`:gaps` as a `TileBlockers` over the gap grid**, which stops any box that
  would overlap a gap cell. A node on a platform stands inside gap cells, so it
  could not move at all.
- **A scale in the transform**, as Godot's `Node2D.scale` is. Children's world
  positions and every collider would scale with it, and the fall needs only
  the picture.
- **A scale the sprites read**, as they read `elevation`. A child, such as a
  hat, and the node's own `_draw`, such as a shadow, would stay full size.
- **Holes in a floor layer** (question 4, B), **falling on the whole box**
  (question 6, B) and **the last ground stood on as the respawn point**
  (question 8, C).

## What this does not deliver

- Buffered input, a jump pressed early included.
- Momentum from a platform on leaving it (open question 2).
- Platforms that wait, or that something pushes (open questions 1 and 3).
- Routes planned around gaps (open question 4).
- Damage or lives for a fall. `Footing#on_fell` is the seam for them.
- A pit that drops a node into the room below. That is a door, and `Rooms`
  moves it.
- A hop over a wall, or a hop that draws over the scenery it rises past. Both
  are as `examples/jump_topdown` describes them.

---

## Roadmap

### Dependency shape

```
1 floor and gaps ─→ 2 fall and respawn ─→ 3 moving platforms ─→ 4 test project (rough) ─→ 5 fold back
                          │                       │
                          └─ examples/pits        └─ examples/moving_platforms
```

Step 1 comes first because every later step asks `floor_at?`. Platforms come
after falling because carrying a rider is only visible once leaving the
platform means falling.

> **Floor has one definition.** `TileWorld#floor_at?` decides where a node may
> stand. `Footing`, the `:gaps` blocker and a platform's riders all ask it, and
> nothing else answers it.

Step 3's composition spec backs this: along a line across ground, a gap and a
platform, the three agree at every point.

Each detailed step is worth landing alone:

| Step | Defect it closes |
|---|---|
| 1 | A map cannot say where its floor ends, and an NPC walks into a chasm with nothing to stop it |
| 2 | A hop crosses nothing. `examples/jump_topdown` leaves crossing a chasm to every game |
| 3 | Nothing can carry a node, and a route is walked once |

### Step 1 — the floor: gaps in the map, and the `:gaps` blocker *(pure)*

Every later step asks where the floor is, so the question comes first, with its
cheapest user. `blocked_by: [:gaps]` is useful on its own: it keeps an NPC or a
crate out of a chasm.

#### 1a — `TileMap#gap_tile?`

`TileMap` derives the gaps from the tile classes it already holds, so no caller
of `TileMap.new` changes.

```ruby
# TileMap

# The class a designer gives a tile in Tiled to make its cell a gap.
GAP = 'gap'

# in initialize, beside @solid:
@gap = @tile_classes.map { it == GAP }.freeze

# Whether `tile` is a gap: its class in Tiled is `gap`. Tile 0, the empty
# cell, never is.
def gap?(tile) = @gap.fetch(tile)

# A gap if any layer has a gap tile at (col, row), as `solid_tile?` reads
# solidity. Out of bounds is not a gap.
def gap_tile?(col, row)
  # ...the loop solid_tile? has, over @gap
end
```

#### 1b — `TileWorld`: the gaps and the floor

`TileWorld` reads the gaps once, into a second `Util::SolidGrid`, and answers
three questions about them.

```ruby
# TileWorld

def gap?(col, row) = gap_grid.solid?(col, row)

# Whether a node standing at the world point (x, y) stands on the floor.
# Step 3 adds the platforms.
# hot-path
def floor_at?(x, y) = !gap?(col_at(x), row_at(y))

# How far a point on the floor at (x, y) can move `dx` along x and stay on it:
# `dx` itself, or up to the last point before the floor ends. A point already
# off the floor moves the whole way.
# hot-path
def floor_reach_x(x, y, dx)
  return dx if dx.zero? || !floor_at?(x, y) || floor_at?(x + dx, y)

  # A step is under a tile, as TileBlockers assumes, so it crosses at most one
  # cell edge. Moving right, the point stops just before the gap cell's left
  # edge (`prev_float`), because a point on an edge is in the cell to its right.
  # Moving left, it stops on the gap cell's right edge.
end

def floor_reach_y(x, y, dy) # the same along y
end

# The :gaps blocker source, shared by every mover on the map.
def gap_blockers = @gap_blockers ||= Engine::GapBlockers.new(world: self)

private

def gap_grid
  @gap_grid ||= Util::SolidGrid.build(@map.width, @map.height) { |col, row| @map.gap_tile?(col, row) }
end
```

#### 1c — `Engine::GapBlockers`, and `:gaps` in `Mover`

A blocker source over the floor. `CollisionSystem` needs no change: it takes
the most restrictive landing from every source, so a mover declaring `:tiles`
and `:gaps` stops at whichever comes first.

```ruby
module RGame
  module Engine
    # The edge of the floor as a blocker source. A step may not take the centre
    # of a mover's box off the floor that TileWorld#floor_at? describes.
    class GapBlockers
      # What a GapBlockers reports as having stopped a step, as TileBlockers
      # reports TILES.
      class Gaps
        def layer = :gaps
        def node = nil
      end

      GAPS = Gaps.new.freeze

      def initialize(world:)
        @world = world
      end

      # hot-path
      def resolve_x(x, y, w, h, dx) = x + @world.floor_reach_x(x + (w / 2.0), y + (h / 2.0), dx)

      # hot-path
      def resolve_y(x, y, w, h, dy) = y + @world.floor_reach_y(x + (w / 2.0), y + (h / 2.0), dy)

      def blocker = GAPS

      def moved(_actor, _from_x, _from_y, _w, _h) = nil
    end
  end
end
```

`Mover` reserves the name:

```ruby
# Mover
GAPS = :gaps
RESERVED = [TILES, BOUNDS, GAPS].freeze

# resolve_blockers:
sources << gap_blockers if @blocked_by.include?(GAPS)

def gap_blockers
  world = node.system(TileWorld) ||
          raise("#{mover_name} is blocked_by :gaps, and the scene has no TileWorld to read the " \
                'gaps from. Mount one, or drop :gaps.')
  world.gap_blockers
end
```

`pushes:` already refuses every reserved name, so it refuses `:gaps`. Its
message says "the map or the edge of the world", and gains "or its gaps".

#### Rules the tests pin

1. A tile of class `gap` makes its cell a gap on any layer. An empty cell, a
   cell off the map and a tile of another class do not.
2. `floor_at?` is false exactly where `gap?` is true for the cell holding the
   point. A point on a cell's left or top edge is in that cell.
3. A step toward a gap stops with the centre on the last point that is floor.
   A step along the gap's edge is not stopped.
4. A diagonal step into a gap keeps its free axis, as against a wall.
5. A step that starts off the floor is not stopped.
6. `on_blocked` reports `:gaps` and a nil node, once per edge pressed against.
7. A mover declaring `:gaps` on a scene with no `TileWorld` raises at attach,
   naming the mover.
8. A floor query and a blocked step allocate nothing.

#### Tests

- `spec/rgame/engine/tile_map_spec.rb`: rule 1.
- `spec/rgame/engine/components/tile_world_spec.rb`: rule 2, and `floor_reach_x`
  and `floor_reach_y` at both edges of a gap.
- `spec/rgame/engine/gap_blockers_spec.rb`, new: rules 3–5, through a
  `CollisionSystem` holding the source, beside a `TileBlockers` for the
  most-restrictive case.
- `spec/support/shared_examples/a_mover.rb`: rules 6 and 7 for every mover, and
  a mover declaring `%i[tiles gaps]` stopping at whichever edge comes first.
- `spec/rgame/engine/components/mover_spec.rb`: `pushes: [:gaps]` raises.
- `spec/rgame/engine/tile_blockers_allocation_spec.rb` gains a gap step, or a
  `gap_blockers_allocation_spec.rb` beside it: rule 8.

#### Verify

A `CharacterBody` declaring `blocked_by: [:gaps]` stops at a gap's edge with
the centre of its box on the floor, and slides along the edge.

- `rake spec`.
- `docs/api/tile_maps.md` says what a `gap` tile does. `docs/api/components.md`
  lists `:gaps` wherever it lists `:tiles` and `:bounds`, and
  `docs/api/systems.md` gives `TileWorld`'s new methods, per
  [write-docs](../../.claude/skills/write-docs/SKILL.md). `CHANGELOG.md` has an
  entry.

**Landed.** Four commits on `floor-and-gaps`: the plan, then 1a, 1b and 1c
as sketched. `rake spec` 4024 examples, 0 failures (3980 before, 44 new).
`rake spec:core` 517, 0 failures. `make test` 412 checks. `rake
drive:allocations` ok for every project. A scratch `CharacterBody` with
`blocked_by: [:gaps]`, walking diagonally for 1 s into a gap column at
x = 80, ends with its centre at 79.999999999, on the floor, having slid
80 px down the edge.

Where the sketch was wrong:

- **Stopping exactly at the edge does not survive rounding.** The sketch
  stopped a point at `prev_float` moving right and on the edge moving left.
  But a landing travels from centre to box to node and back, and a point one
  ulp from the edge can land across it. The point then starts off the floor
  next step, and walks free into the gap. `floor_reach_x` and `_y` stop
  `TileWorld::FLOOR_EDGE` (1e-9 px, `TileSweep`'s `EDGE_EPS`) short of the
  gap, in both directions.
- **The reach walks every cell of the step**, instead of assuming it
  crosses one edge. It costs a loop over at most one cell at walking speeds,
  and a step longer than a tile still stops at the first gap.
- **`gap_blockers` landed in 1c, not 1b**, beside the class it builds.
- **`TileWorld` is documented in `docs/api/components.md`**, not
  `systems.md`. `systems.md` got the fourth blocker source and a row in its
  table, `internals.md` a `GapBlockers` section.
- **`floor_at?` measures about 225 ns**, not 126. The planning benchmark
  inlined the arithmetic, and the method makes four calls: `gap?`,
  `col_at`, `row_at` and the grid. 200 actors cost 45 µs a tick, 0.3% of a
  frame. `resolve_x` into a gap measures about 700 ns.
- **The commit hook strips a comment above a constant.** `FLOOR_EDGE`'s
  explanation lives in `floor_reach_x`'s comment.
- `spec/support/walled_tile_map.rb` draws a gap tile as `~`.
  `spec/spec_style_spec.rb` pins an exempted helper in `a_mover.rb` by line
  number, and the number moved.

Open question 7 is new: "gap" now names a tile and a draw slot.

### Step 2 — falling, and coming back *(pure, with the pit art and `examples/pits`)*

A hop crosses a gap once walking into one makes a node fall. This step adds the
fall, the respawn and the art, and ships the first example.

#### 2a — `Node2D#scale`, drawing only

```ruby
# Node2D

# How large this node and everything under it draws, about its origin: 0
# draws none of it, and 1, the default, changes nothing.
#
#   node.scale = 0.5   # the node, its components and its children, at half size
#
# `draw` applies it around the node's own drawing and its children's, as it
# applies `opacity`, so a `_draw` cannot miss it and a child cannot escape
# it. A child's own scale multiplies with it.
#
# Only drawing changes. Positions, colliders and footing keep their size.
attr_reader :scale

# Refuses anything but a number of 0 or more.
def scale=(value)
  # raise ArgumentError unless value.is_a?(Numeric) && value >= 0
  @scale = value
end

def draw(renderer, view)
  return if @opacity.zero? || @scale.zero?

  rgame_resolve_inherited
  rgame_in_local_space(renderer) do
    rgame_as_shown(renderer) do
      renderer.layered(@abs_band) { rgame_draw_content(renderer, view) }
      draw_children(renderer, view)
    end
  end
end

private

# Scale, then opacity, in one method, so a node at 1 and 1 pays one
# comparison: 7 ns measured, against 40 for a method of its own.
# hot-path
def rgame_as_shown(renderer, &)
  return yield if @scale == 1 && @opacity == 1
  # renderer.scaled(@scale) around renderer.faded(@opacity), each skipped at 1
end
```

`rgame_as_shown` replaces `rgame_at_opacity`. `Sprite` and `AnimatedSprite`
multiply the footprint they cull by `node.scale`, about the origin, so a node
scaled past 1 does not pop out at the edge of a view.

#### 2b — `Components::Footing`, and the fall

`Footing` watches the centre of its node's box and decides when the node falls.
It reads the node's `Hop` and `Mover`, if it has them, and finds both on its
first update, so neither needs adding before it.

```ruby
module RGame
  module Engine
    module Components
      # What its node stands on, and the fall when that is nothing ...
      class Footing < Engine::Component
        # Fired once as the node starts to fall, before it shrinks.
        signal :fell

        # Seconds the node may stand off the floor after walking off it, and
        # still hop. 0 drops it on the first tick.
        attr_accessor :coyote

        # Seconds the fall takes, from the drop to the respawn.
        attr_reader :fall

        def initialize(coyote: 0.1, fall: 0.4)

        # Raises when the node has no BoxCollider, or the scene no TileWorld.
        def _attach

        # Whether the centre of the node's box is on the floor.
        def standing?

        # Seconds of coyote time left: `coyote` while standing, counting down
        # off the floor, 0 in the air.
        def coyote_left

        def falling?

        # hot-path
        def _update(dt)
      end
    end
  end
end
```

**The fall runs outside the falling node.** A suspended node stops its
components too, so `Footing` cannot animate its own node's fall. It keeps one
`Engine::Fall` node for the life of the component, and lends it to the falling
node's parent for each fall. That node pauses with the world, which a scene
system would not, and a fall allocates nothing.

```ruby
module RGame
  module Engine
    # The fall of one node, run from beside it: stops the node, shrinks it over
    # the footing's `fall` seconds, then respawns or frees it. Footing keeps one
    # and adds it to the falling node's parent for each fall.
    #
    # @api private
    class Fall < Node2D
      def initialize(owner)  # not @footing: that ivar is Node2D's
      def start(node)        # suspends node, joins its parent
      def _update(dt)        # node.scale = the shrink's value; lands when done
    end
  end
end
```

At the end of the fall, `Fall` sets the node's scale back to 1 and resumes it.
It then calls the node's `Respawn#respawn`, or frees the node if it has no
`Respawn`, and frees itself for the next fall. A node that left its parent
mid-fall, because a door moved it or a game freed it, ends the fall at once
with its scale restored.

#### 2c — `Components::Respawn`

```ruby
module RGame
  module Engine
    module Components
      # Where a node comes back after a fall, and the flash that shows it has ...
      class Respawn < Engine::Component
        # Fired once the node stands on its respawn point, as the flash starts.
        signal :respawned

        # Seconds one blink shows the node, and seconds it hides it.
        BLINK = 0.1

        attr_reader :point_x, :point_y, :flash

        def initialize(flash: 1.0)

        # The first attach records where the node stands as its point. Later
        # attaches, such as a door's move, keep the point.
        def _attach

        # A new respawn point, in world pixels. A Checkpoint calls it.
        def set_point(x, y)

        # Places the node on its point and starts the flash. A game may call it
        # without a fall, as a death that is not one.
        def respawn

        def flashing?

        # hot-path. Blinks `opacity` until `flash` has passed, then gives back
        # the opacity it found.
        def _update(dt)

        # Stops a flash and gives the opacity back.
        def _detach
      end
    end
  end
end
```

#### 2d — the pit art, and `pits.tmx`

- `tools/draw_pit_tiles.rb` writes `examples/assets/pits.png`: two 16×16 tiles,
  a dark pit and a north edge showing the drop. It needs only Ruby and `zlib`,
  which ship with Ruby, and stays in `tools/` so the art can be drawn again.
- `examples/assets/pits.tsx` gives both tiles the class `gap`.
- `examples/assets/pits.tmx`, 40×30 tiles to fit the window, over
  `tileset.tsx` and `pits.tsx`. It has a row of one-tile gaps to hop and a
  wider chasm to walk into. A short Ruby script writes it, as `puzzle.tmx` was
  written.
- `examples/assets/README.md` records all three, per
  [write-example](../../.claude/skills/write-example/SKILL.md)'s asset rules.
  `spec/example_assets_spec.rb` holds `pits.tsx` to every tile being a gap, and
  `pits.tmx` to its start standing on floor.

#### 2e — `examples/pits`

A hero with `Hop`, `Footing` and `Respawn` on `pits.tmx`. Space hops, C turns
coyote time on and off, and a bar under the help lines shows `coyote_left`
running out. The bar is a rect, so the example builds no string per frame. The
drive script walks into the chasm and respawns, then hops a gap. It walks off
an edge and hops four ticks later, across with coyote time and into the gap
without it.

#### Rules the tests pin

1. A node at scale 1 draws exactly as before, and at 0 draws nothing. Between
   them, its own drawing and its children's draw scaled about its origin, and
   a child's scale multiplies with it.
2. `scale=` refuses a negative number and anything that is not a number.
3. A node standing on the floor never falls, however long it stands.
4. A node walking off the floor falls once it has been off it for more than
   `coyote` seconds. With 0.1 s at 60 Hz, a hop pressed in any of the six ticks
   after the step off counts.
5. A node that lands on a gap falls on the tick it lands.
6. A node in the air never falls, and never counts coyote time.
7. A falling node is suspended, its scale runs from 1 to 0 over `fall`
   seconds, and `on_fell` fires once as it starts.
8. After the fall, a node with a `Respawn` stands on its point at scale 1,
   resumed, and flashing. A node without one is freed.
9. The flash blinks `opacity` for `flash` seconds, then gives back the opacity
   it found. `on_respawned` fires once.
10. A fall pauses with its parent: a paused `WorldView` holds a falling node
    mid-shrink.
11. A node taken from its parent mid-fall ends the fall at once, unscaled and
    resumed.
12. `Footing` and `Hop` give the same results in either add order, at most a
    tick apart. A `Hop` added after `Footing`, from `_enter_tree`, still keeps
    the node from falling.
13. A footing's check, a fall and a flash allocate nothing once warm.

#### Tests

- `spec/rgame/engine/node2d_scale_spec.rb`, new, beside
  `node2d_opacity_spec.rb`: rules 1 and 2. `culling_spec.rb` gains a node
  scaled past 1 at the edge of a view.
- `spec/rgame/engine/components/footing_spec.rb`, new: rules 3–8, 10–12. It
  holds the step's composition: a hero with `CharacterBody`, `Hop`, `Footing`
  and `Respawn` in both add orders, walking off an edge, hopping in the
  coyote window and landing on a gap.
- `spec/rgame/engine/components/respawn_spec.rb`, new: rule 9, and `respawn`
  called without a fall.
- `spec/rgame/engine/components/footing_allocation_spec.rb`, new: rule 13.

#### Verify

A hero walks into a gap and falls, hops across one, and comes back flashing on
the spot they started from.

- `rake spec`, and `rake drive:allocations`, which now drives `examples/pits`.
- `ruby tools/drive_test_project.rb examples/pits/main.rb` shows the fall's
  `scaled` calls shrinking to 0, the flash's `faded` calls, and the hop with
  coyote time landing where the hop without it fell. The script's header says
  so, read off a real run.
- `docs/api/scene_graph.md` has `scale` beside `opacity`, and
  `docs/api/components.md` has `Footing` and `Respawn`. `Hop`'s paragraph "The
  game decides what a hop crosses" points at `Footing`, and
  `examples/jump_topdown`'s "What this does not solve" names `examples/pits`.
  `docs/api/examples.md` and `README.md` list the example, and `CHANGELOG.md`
  has an entry.

### Step 3 — moving platforms *(pure, with `examples/moving_platforms`)*

The platform, the carry, and the composition this whole plan exists for.

#### 3a — routes that loop

```ruby
# Path
# `closed: true` walks back to the first waypoint from the last, as a Tiled
# polygon does.
def initialize(points, closed: false)

# The route a polyline or polygon object on a map describes. Raises
# ArgumentError for any other shape.
def self.from_object(object)

# PathFollow
# `loop: true` never finishes: it goes round a closed path, and back and
# forth along an open one, carrying each step's overshoot past the end.
def initialize(speed:, path: nil, loop: false, blocked_by: [], pushes: [])
```

A looping follower never emits `on_finished`, and its heading turns round at
each end of an open path.

#### 3b — `Components::Platform`, and the floor over it

```ruby
module RGame
  module Engine
    module Components
      # Makes its node's box floor over the map's gaps, and carries whoever
      # stands on it ...
      class Platform < Engine::Component
        # Raises when the node has no BoxCollider, or the scene no TileWorld.
        # Registers with the TileWorld, as OccupiesCell does.
        def _attach

        # Lets every rider go, and leaves the TileWorld.
        def _detach

        # Whether the world point (x, y) lies on the platform's box.
        # hot-path
        def covers?(x, y)

        # The footings standing on it now.
        attr_reader :riders
      end
    end
  end
end
```

`TileWorld` gains the platforms over its gaps:

```ruby
# TileWorld

# @api private: Platform calls these, as OccupiesCell calls occupy and vacate.
def bridge(platform)
def unbridge(platform)

# The platform a node standing at (x, y) rides: the first registered one
# covering the point, where the cell is a gap. nil on ground.
# hot-path
def platform_under(x, y)

# hot-path
def floor_at?(x, y) = !gap?(col_at(x), row_at(y)) || !platform_under(x, y).nil?
```

`floor_reach_x` and `floor_reach_y` also stop at the edge of the platform a
point stands on, where no ground and no other platform continues the floor.

#### 3c — the carry

**Boarding is the rider's question.** `Footing` asks `platform_under` each
update and tells the platform when it boards and when it leaves. It leaves as
it falls and as it detaches.

**Carrying is the platform's mover's job.** `Mover#_update` finds a sibling
`Platform` on its first update after attaching. With one, it measures the
node's world position around `take_step` and hands the difference to the
platform. The step's own shape does not matter, so a `PathFollow` that places
its node directly carries as well as a `Velocity`. A mover with no `Platform`
pays one nil check.

```ruby
# Platform
# Carries every rider by (dx, dy), front first along the step, so no rider
# runs into one this step has not moved yet.
# @api private
def carry(dx, dy)

# Footing
# Moves the node by what its platform moved: through its Mover when it has
# one, directly when it has not.
# @api private
def ride(dx, dy)

# Mover
# Moves the node by (dx, dy) as far as `blocked_by:` allows, and reports
# nothing: being carried is not a step of this mover's.
# @api private
def ride(dx, dy)

# Whether the last step was cut short by something in the way. Moved up from
# Pushable, which keeps answering it.
def stopped? = last_move_blocked?
```

Three more changes come with the carry:

- **`:gaps` needs a `Footing`.** The floor now moves, so a mover kept on it has
  to ride it. A mover declaring `:gaps` on a node with no `Footing` raises at
  attach.
- **`WanderController` reads `@body.stopped?`** instead of how far the node
  moved. A carried NPC always moves, so it would never re-roll at the
  platform's edge. The class comment's "Blocked is measured as the node did not
  move" changes with it.
- **The composition spec**, below.

#### 3d — `examples/moving_platforms`

- `examples/assets/tiles.json`, a sheet over `tileset.png` in 16×16 frames with
  no animations. A platform draws its wooden tiles with `renderer.sprite`.
- `examples/assets/platforms.tmx`: one chasm, and one platform object whose
  polyline shuttles across it. Its ends stop short of each bank by less than a
  hop, so boarding takes a timed hop. The platform's object carries its size in
  custom properties.
- `examples/pits`' hero, and the platform built from the map with
  `MapObjects`. The drive script waits for the platform, hops on, rides across
  and hops off, then mistimes a hop and falls.

#### Rules the tests pin

1. A closed path loops without a jump, an open one goes back and forth, and a
   looping follower never finishes. `Path.from_object` refuses a rectangle.
2. `floor_at?` is true over a gap where a platform covers the point, and
   `platform_under` is nil wherever the cell is ground.
3. A node whose centre stands on a platform over a gap rides it. In the air it
   still rides, and over ground it does not.
4. A platform carries every rider by exactly its own step, whatever computed
   the step, and in either order of the platform's and the rider's updates.
5. Two riders flush against each other stay flush through a carry, whichever
   boarded first.
6. A wall stops a rider but not its platform, so the rider leaves the platform,
   and falls unless it hops.
7. A carry fires no `on_blocked` and changes no `stopped?`.
8. A mover blocked by `:gaps` on a platform stays on the platform, and steps
   onto ground where the platform meets it.
9. A `:gaps` declaration on a node with no `Footing` raises at attach.
10. `WanderController` re-rolls against a gap's edge while carried.
11. A platform leaving the tree lets its riders go. A rider leaving the tree
    leaves its platform.
12. Carrying, boarding and a looping walk allocate nothing once warm.

#### Tests

- `spec/rgame/engine/path_spec.rb` and
  `spec/rgame/engine/components/path_follow_spec.rb`: rule 1.
- `spec/rgame/engine/components/platform_spec.rb`, new: rules 2–6 and 11.
- `spec/support/shared_examples/a_mover.rb`: rules 4 and 7 for every mover as
  the platform's mover, and rule 9.
- `spec/rgame/engine/components/wander_controller_spec.rb`: rule 10.
- `spec/rgame/engine/components/platforming_spec.rb`, new: **the composition.**
  One scene holds a hero (`CharacterBody`, `Hop`, `Footing`, `Respawn`), a
  looping platform, an NPC blocked by `%i[tiles gaps hero]` riding it, and a
  crate with `Footing` and `Respawn`. Two heroes ride the platform while the
  NPC wanders on it. One hero hops off into the chasm and respawns, while the
  other rides on. The crate is pushed into a gap and comes back. It runs with
  each node's components in both add orders. Rule 8 lives here, and so does
  the invariant: along a line across ground, a gap and a platform, `floor_at?`,
  the `:gaps` blocker and boarding agree at every point.
- `spec/rgame/engine/components/platform_allocation_spec.rb`, new: rule 12.

#### Verify

A hero rides a platform across a chasm, and an NPC wanders on it without ever
walking off.

- `rake spec`, and `rake drive:allocations`, which now drives
  `examples/moving_platforms`.
- The drive script's report shows the hero's camera travelling with the
  platform, and one fall.
- `docs/api/components.md` has `Platform`, `PathFollow`'s `loop:`, `Mover#ride`
  under the carry, `stopped?`, and `WanderController`'s new measure.
  `docs/api/toolbox.md` has `Path`'s `closed:` and `from_object`.
  `docs/api/examples.md` and `README.md` list the example, and `CHANGELOG.md`
  has an entry.

### Step 4 — the test project *(rough)*

`test_projects/chasms`, on a map of its own that composes everything. Re-plan
after step 3 lands.

- **`Components::Checkpoint`**, Collectable-shaped. Touched by a collider on
  its `by` layer, it calls that node's `Respawn#set_point` with its own
  position and emits `reached`. Whether a `by` node without `Respawn` raises
  is for the re-plan.
- **The map** lives in the project's directory and does not ship. It names
  `examples/assets`' tilesets by relative path, and the game loads it by
  absolute path while `media_root` stays `examples/assets`.
  `AssetManager#resolve` expands a path against the root, so an absolute one
  passes through *(read, not run)*.
- **The course**: one-tile gaps to hop, a shuttle platform to board with a
  timed hop, and a checkpoint. Then a looping platform in the middle of a
  chasm, never touching a bank, with the NPC walking around on it. A crate
  stands beside a gap, and a last checkpoint ends the course.
- **Two players**, the second joining by using a device. The drive script plays
  two devices: both ride one platform, and one falls while the other rides on.
- An allocation budget in the drive script, with a reason if it goes over the
  default.

### Step 5 — fold the plan back and delete it

- Read `docs/api/` for anything this plan says that the pages do not: the
  floor rule, the rules in one place, the fall's timing and add order. Add
  what is missing.
- Add a `docs/plans/possible-todos.md` entry for **buffering input**: a press
  remembered for a moment, so an action refused now happens when it can. A hop
  pressed just before landing is one case, and an attack queued during
  another is a second. Its trigger is a game whose players press early, and
  whose actions are refused for a few ticks at a time. Move every open question
  still open there too, each with what it waits on.
- Delete `docs/plans/topdown-platforming.md`.

#### Verify

`CHANGELOG.md` covers everything steps 1–4 shipped, per
[update-changelog](../../.claude/skills/update-changelog/SKILL.md). `rake spec`
passes, including the docs link checks. `docs/plans/topdown-platforming.md` is
gone.
