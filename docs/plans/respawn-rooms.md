# Respawn across rooms

**Status:** planned at `cee120c`. Steps 0 to 3 are detailed. Steps 4 and 5 are
rough, and get re-planned once step 3 lands. No step is implemented.

A node with a `Respawn` comes back to the room its point is in. In its own room
it comes back at once, as today. From another room, the rooms move it there
under a cover, as a door does.

## Verdict

**A respawn point becomes an object that places the node, and a point in a room
reuses the call a door makes.** `Respawn` holds a point and asks it to place the
node as a fall ends. The engine offers two kinds:

- **`Respawn::Point`**, at world coordinates, is today's behaviour. `pits`,
  `moving_platforms` and `topdownplatformer` keep it unchanged.
- **`Respawn::RoomPoint`**, at a named location in a room. In the node's own room
  it places the node at once. From another room it calls
  `rooms.move(node, to: room, location:)`, and the room's `_arrive` places the
  node as it places any arrival.

Nothing about `Room` changes shape except a parameter's name. The work is five
pull requests, and the first three are worth landing alone (see the roadmap).

## The requirement

As it arrived:

> Rework `Respawn` to take a room's name as additional parameter besides x+y.

Before it: when respawning, `Respawn` places the node at that position, "either
directly in the room or moving the node there". And from the question rounds:

> What if `Respawn` took a named node instead of a position? Then `_arrive`
> would maybe need its parameter renamed (from `entrance` to `location`), but
> apart from that could stay the same.

> Can we add a way to add objects (not nodes) to the object layer, so the lookup
> can stay the same if the checkpoint was added in code or in a map editor?

> Instead of `(x, y, room: nil, location: nil)` we pass an object that responds
> to `move(node)`. The engine can already offer two: a simple one that just sets
> the node to this coordinates, for games without rooms […] A game with rooms
> gets the more complicated one, which takes a room and location […] Is the
> hero in the same room? Then just place it there. Is it in another room? Then
> move to that room and spawn it at the location.

## Hard constraints

1. **Everything here is engine layer.** No Core class, and every spec runs
   headless under `rake spec`.
2. **`Respawn`, `Checkpoint`, `Fall`, `Scene::Rooms`, `Scene::Room` and
   `MapObject` first ship in 0.5.0** (none exists at the `v0.4.0` tag), so their
   API may change freely. `TileWorld` shipped in 0.4.0, and this plan only adds
   to it.
3. **A respawn in the node's own room stays instant.** The node stands on its
   point, and `on_respawned` fires, in the tick the fall ends. No cover, and no
   suspended input.
4. **Each mistake raises, and as early as the facts allow.** Most raise at
   attach: a location name that clashes, or a checkpoint in a room without a
   location. A point at coordinates used from another room raises at the
   respawn, the first moment the mistake shows.
5. **Nothing here runs per frame.** A respawn, an attach and a landing each
   happen once, so no allocation budget moves.

## Decisions already taken

These were settled in two question rounds, and are not reopened inside the
plan.

1. **A point is an object, not keyword arguments.** `set_point` takes one. The
   engine offers a point at coordinates and a point in a room, and a game may
   bring its own. The point objects answer three methods: `room`,
   `place(node)` and `check_ground(world)`. That makes them an interface with
   several implementations, so they pass one shared example group. The keyword
   version, `set_point(x, y, room: nil, location: nil)`, needed a nil room and a
   nil location explained everywhere.
2. **A point in a room stores the room's name, not the `Room`.** `Rooms` frees
   an empty room and builds a new one on the next visit. A stored `Room` would
   be the freed copy.
3. **A respawn into another room is the call a door makes.**
   `rooms.move(node, to: room, location:)` lands it, and `_arrive` places it.
   This rejects splitting `_arrive` into two hooks (see "Considered and
   rejected").
4. **A door leaves the point where it was set** (question 3). A hero who falls
   in room B before touching a checkpoint there comes back in room A. This is
   Hollow Knight's bench. A game that wants "back to this room's entrance",
   A Link to the Past's pit, calls `set_point` in `on_arrived`.
5. **A warp keeps the point.** Nothing in this design resets it.
6. **Code-built checkpoints get their names from `TileWorld`** (question 1). A
   `TileWorld` keeps a registry of location names beside its platforms, rebuilt
   with the room. Its lookup searches the map's named objects and the
   registered names alike. Rooms built over a map look entrances up there
   instead of on the `TileMap`.
7. **A point at coordinates, used from another room, raises at the respawn**
   (question 2). `Respawn` records the room the node stood in as the point was
   set, and the raise names both rooms. A game that sets its point on every
   arrival never trips it.
8. **`on_respawned` fires as the node lands; `Fall#on_finished` fires as the
   fall ends** (question 4). That matches how `on_finished` already treats a
   free: it fires when the free is queued, before the sweep frees the node.
9. **`entrance` becomes `location`** in `Rooms#move` and `Room#_arrive`
   (question 6). A checkpoint is not an entrance. The doors' Tiled property
   `entrance` and the map class `entrance` keep their names: a door's target
   is an entrance.
10. **Each place in the engine picks its kind of point from what it already
    knows** (question 8):
    - `Rooms` hands a node's `Respawn` a `RoomPoint` on the node's first
      landing, before `_arrive`, if it has no point.
    - The first attach outside rooms takes a `Point` where the node stands.
    - `Checkpoint` takes `location:`. One standing in a room without a location
      raises at attach.
11. **No `Respawn` connection to `Rooms#on_arrived`** (question 7). The node
    attaches in the point's room as it lands, and `Respawn` ends the respawn
    there. "A connection that ends with its node" in `possible-todos.md` stays
    open, and this plan adds no fourth hand-written disconnect.
12. **A spec tests the composition, and no project does.** No project mounts
    `Respawn` beside `Rooms`. One spec composes `Rooms`, `Respawn`, `Fall` and a
    `TileWorld` with gaps in two rooms.

## What was measured before planning

At commit `cee120c`, on Ruby 4.0.5.

| | |
|---|---|
| `rake spec` | 4763 examples, 0 failures, 42.3 s |
| Examples in the specs this plan touches | `respawn` 13, `checkpoint` 10, `fall` 45, `platforming` 21, `rooms` 37, `rooms_move` 14, `rooms_music` 15, `rooms_allocation` 2 |
| Projects mounting `Respawn` beside `Rooms` | 0. `Respawn` is in `moving_platforms`, `pits` and `topdownplatformer`; `Rooms` in `doors` and `adventure` |
| `set_point` callers outside specs and docs | 1: `checkpoint.rb:75` |
| `point_x`/`point_y` readers outside `respawn.rb` | 1 game (`topdownplatformer/course.rb:49`, placing a joining hero), 2 specs (8 lines), 1 doc line |
| `on_respawned` | 4 connections in games and examples, 7 in specs, 4 mentions in docs |
| `Fall#on_finished` connections in games and examples | 0 |
| `Checkpoint.new` | 1 in a game (`topdownplatformer/flag.rb`), 3 in docs and comments |
| `Room#_arrive` implementations | 8: 3 in code (`doors`, `adventure`'s town and garden), 2 in specs (`spec_room.rb`, `rooms_spec.rb:285`), 3 in docs (`room.rb`'s header, `scene_graph.md`, `tile_maps.md`) |
| `_arrive`s that look up `@map.object_named` | 4: the 3 in code and `tile_maps.md:464` |
| `entrance` as `move`'s keyword or `_arrive`'s parameter | 118 lines in 18 files. 64 of them are in the three `rooms_*_spec.rb` files |
| Entrances in the example maps | 7, all point objects of class `entrance` |
| `_arrive`s with a side effect beyond placing | 1: `garden.rb`'s `read_the_sign`, guarded by a fact so it runs once ever |

## Today

`Respawn` holds two floats. Its first attach records where the node stands, and
every attach checks the point for a gap in the node's scene
(`respawn.rb:52-58`).

**A door move into a room with a gap under the old point crashes the game.**
`Rooms#land` takes the node out of its room and calls the new room's `_arrive`.
That adds the node, which runs `Respawn#_attach`. The attach checks room A's
point against room B's `TileWorld`, and raises `ArgumentError` inside the sweep.
The message tells the author to call `set_point` before adding the node, which
is the wrong fix. *(Traced through the code.)*

**Otherwise a fall in room B comes back at A's coordinates inside B.** Every room
shares the host's origin, so the numbers land somewhere in B. Only gaps are
checked, so the spot may be inside a wall or off B's map, which counts as
ground. *(Traced through the code.)*

A handler on `on_arrived` cannot fix the point, because the raise comes first.
`possible-todos.md` records this as "A respawn point in a room left behind".

## What it resembles

**Reuse it.**

- `Rooms#move`: a respawn into another room is a door's move.
- `Room#_arrive`: it already places an arrival, before adding it, in all 8
  implementations.
- `TileWorld`'s registries. `Platform` bridges and unbridges as it attaches and
  detaches, and `OccupiesCell` occupies and vacates. Named locations register
  the same way.
- The map builder's `name:`. `Flag` already receives its object's name, and the
  course names its flags `first`, `second` and `last`.

**Extend or generalize it.**

- **An entrance and a checkpoint answer the same question:** where in this room
  does a node stand when it comes here? That is why `entrance` becomes
  `location`, and why one lookup serves both.
- **`MapBuilder#origin_x`/`origin_y` become `MapObject#origin_x`/`origin_y`.** The
  builder and the new location lookup both need the point a node built from an
  object stands on. Today the builder keeps it private.
- **`TileMap#object_named` becomes `TileWorld#location`** for rooms. The map
  stays frozen. The `TileWorld` answers for the map's named objects and for the
  names registered in code.
- **`Respawn`'s two floats become an interface.** It is the same move the
  renderer made: a method list with several implementations, held to one shared
  example group.
- **`Scene::Room.of(node)`** follows `Identity.of(node)`. It names the room a
  node stands in, which `Respawn`, `RoomPoint` and `Checkpoint` all ask.

**Genuinely new.** `RoomPoint` is the one piece that joins `Respawn` to `Rooms`.
Nothing else in the engine places a node in a room it does not stand in, except
`Rooms` itself, and `RoomPoint` hands that job to `Rooms`.

## Prior art

Games split the question two ways:

- **A pit sends you back into the current room.** In A Link to the Past, a pit
  returns Link to the entrance of the current room, with damage
  ([Zelda Wiki, Pit](https://zeldawiki.wiki/wiki/Pit)).
- **Death sends you back to the last save point, wherever it is.** In Hollow
  Knight, you return to the last bench, and a region has only two or three
  ([Hollow Knight: Mechanics and Dynamics](https://mechanicsofmagic.com/2021/04/08/hollow-knight-mechanics-and-dynamics/)).

Decision 4 makes the second the default, and the first one line of game code.
The reverse has no line of code that gets the second.

Godot and Unity ship no respawn or checkpoint component, so a game writes its
own. What neither engine gives us is the pairing this plan relies on: a room
system that can place a node by a name the designer wrote.

## Considered and rejected

- **`Rooms` resets the point on every landing** (the research's option B). It
  is simple, and the reset happens where the position is final. But the point
  is then always in the node's own room, so the room name goes unused, and a
  checkpoint is forgotten at every door. Decision 4 keeps it as one line in
  `on_arrived`.
- **`Respawn#_attach` takes where the node stands, on an attach in another
  room** (the research's option A). It depends on every `_arrive` placing the
  node before adding it, which nothing enforces. It forgets checkpoints too.
- **Splitting `_arrive` into two hooks, so `Rooms` can land a node at
  coordinates.**
  - It changed `Room`'s hook in 8 places.
  - It made `Rooms` place a node after picking its parent and before adding it.
    `Node2D#world_x=` does nothing on a node with no parent
    (`node2d.rb:140-141`), and a node's first attach reads its position.
  - A named location reuses the door's call unchanged.
- **Adding `MapObject`s to the `TileMap` from code.**
  - `TileMap` is frozen, pure data (`tile_map.rb:166`).
  - The asset manager caches one per map (`asset_manager.rb:182`), so an object
    added on one visit is still there on the next. That visit adds it again,
    and `object_named` raises on the duplicate.
  - The map would hold state the room is rebuilt to throw away.
- **Remembering the entrance each room was entered by**, and landing there before
  moving to the point. It needs no API change. But it fails for a node the room
  built, and it places every such node twice.
- **A point at coordinates refused in a rooms game, at `set_point`.** It fires
  early, but it refuses a game that sets its point on every arrival. That game
  needs no room, and `on_arrived` does not carry the entrance a `RoomPoint`
  would need.
- **A fallback to the last entrance, for a point without a location.** It never
  raises, so a forgotten location brings the node back at the wrong place in
  silence.
- **`Fall#on_finished` waiting for the landing.** A cutscene holding on a fall
  would wait for the node. But nothing listens to `on_finished` in a game here,
  and `Fall` would have to learn of the landing from `Respawn`.
- **The game hands `Checkpoint` its point at construction.** A flag from the map
  is built before it enters the tree, so it knows neither its room nor its
  world position.
- **The scene makes points**, through a hook on `Room`. No caller would branch,
  but every call still needs a location that only `Checkpoint` and `Rooms`
  know.
- **`Respawn` listening to `Rooms#on_arrived`** for its landing. It works, and it
  is a fourth hand-written disconnect (see decision 11).

## Design

### The point interface

Every point answers three methods. `spec/support/shared_examples/a_respawn_point.rb`
holds the contract both engine points pass.

| Method | Answers |
|---|---|
| `room` | the Symbol of the room the point is in, or nil for a point that has none |
| `place(node)` | places the node, and returns true when it stands on the point now, or false when a move lands it later |
| `check_ground(world)` | raises `ArgumentError` when `world`, a `TileWorld`, has no ground under the point |

### `Respawn`

`Respawn` decides *whether* a point belongs to the room the node stands in, and
the point decides *how* to place the node. The point's room is `point.room`. For
a point with none, it is the room the node stood in as the point was set,
which `Respawn` records.

- **The first attach** takes `Point.new(x: node.world_x, y: node.world_y)` when no
  point is set. In a rooms game, `Rooms` has already handed it a `RoomPoint`
  (decision 10).
- **Every attach and every `set_point` while attached** checks the point, but
  only while the node stands in the point's room. An attach in another room
  checks nothing, and that removes today's crash.
- **`respawn`** raises for a point with no room while the node stands in another
  room (decision 7). Otherwise it calls `place`. When `place` returns true,
  `on_respawned` fires at once. When it returns false, the respawn waits: the
  next attach in the point's room ends it and fires `on_respawned`, and a landing
  anywhere else ends it with no signal.

### `RoomPoint`

In the room the node stands in, `place` calls that room's `_arrive` at once, as
a warp lands, minus the cover. It raises as `Rooms#land` does if `_arrive` leaves
the node outside the room. From another room, `place` calls
`node.system!(Scene::Rooms).move(node, to: room, location:)` with the rooms'
transition.

`check_ground` reads the location from `world.location(location)`. A
`RoomPoint` knows its position only while its room runs. That is enough: a
respawn in the same room has its room running, and a respawn into another room
needs no position. A point in a room that is not running is checked when the
node attaches there.

### Named locations on `TileWorld`

`TileWorld#location(name)` answers where a named place is, in world pixels. A
name comes either from the map, as the origin a node built from that object
would stand on, or from `add_location(name, node)`, as where that node stands
now. `MapObject#origin_x`/`origin_y` compute the first, moved out of
`MapBuilder`.

### `Checkpoint`

A checkpoint takes `location:`. In a room, a touch hands the toucher's `Respawn`
`RoomPoint.new(room: Room.of(node).name, location:)`. Elsewhere it hands a `Point`
at its node, as today. A checkpoint built in code registers its location with
the `TileWorld`. One built from the map passes its object's name, which the map
already answers. This is step 4, and stays rough.

## Traps

1. **A respawn in its own room runs the room's `_arrive`**, side effects
   included, as a warp does. `garden.rb`'s `read_the_sign` runs on such a
   respawn too, and its fact keeps it to once ever. The docs say a same-room
   respawn is a warp without the cover.
2. **`on_respawned` after a room change fires inside `_arrive`'s `add_node`**,
   because the attach ends the respawn. An `_arrive` that added the node before
   placing it would fire the signal with the old position. All 8 place first.
   `Blink`, the one listener in the examples, reads no position.
3. **A box-shaped object's location is its bottom centre**, where the map builder
   stands its node, and not the top-left corner `object_named` returns. Every
   entrance in the example maps is a point, so no arrival moves.
4. **`adventure`'s `_arrive` offsets a hero by `SPACING * hero.input_owner.id`.**
   A node with no input owner raises there. Today only heroes arrive, and only
   a node a move or a checkpoint touched gets a `RoomPoint`, so only heroes
   reach that line.
5. **A node attached once outside the rooms, then moved into them, keeps its
   `Point`.** `Rooms` hands a `RoomPoint` only to a `Respawn` with no point. That
   node's first fall in another room raises (decision 7), which names the fix:
   set a `RoomPoint`. `adventure` builds its heroes outside the tree, so they
   arrive with no point.

## Open questions

1. **A transition of its own for a respawn into another room.** A `RoomPoint`
   uses the rooms' transition, as a door does. A game may want a different one
   for coming back than for walking through a door. It waits on a game that
   asks, and the answer would be a `transition:` on `RoomPoint`. It blocks
   nothing.
2. **Whether `spec/example_assets_spec.rb` checks checkpoint locations**, as it
   checks every door's entrance. It waits on step 4, and on a map with
   checkpoints in a room.

## What this does not deliver

- **A point per room.** The point stays where it was set (decision 4). A game
  that remembers a checkpoint per room keeps that table itself.
- **Saving the point.** A `RoomPoint` is two values a save could write, but this
  plan writes no save code.
- **A project that uses the pair.** No example or test project mounts
  `Respawn` beside `Rooms`, before or after (decision 12).
- **Lives, game over, or death that is not a fall.** These stay the game's, as
  `Fall#on_fell` documents today.

---

## Roadmap

```
0 location ─→ 1 named locations ─┐
                                   ├─→ 3 a point in a room ─→ 4 checkpoint location ─→ 5 fold back
          2 respawn takes a point ─┘
```

Step 2 does not depend on steps 0 and 1, and can land in either order with them.
Step 3 needs `TileWorld#location` from step 1 and the point interface from step
2.

> **A respawn in the node's own room is instant: the node stands on its point,
> and `on_respawned` fires, in the tick the fall ends.** Every step keeps
> `respawn_spec.rb`'s and `fall_spec.rb`'s examples for a scene without rooms
> passing, with only `set_point`'s argument changed.

Three steps are worth landing even if the plan stops after them:

| Step | Closes |
|---|---|
| 0 | `entrance` names a checkpoint wrongly, once one reaches `_arrive` |
| 1 | a code-built place has no name a room can find, and a box-shaped entrance lands at its corner |
| 2 | the crash at a door move: a point from another room is no longer checked there, and a fall from there raises naming both rooms |

### 0. `location` in `Rooms#move` and `Room#_arrive`

**Why first.** Every later step writes `location`, and a rename done first keeps
their diffs about behaviour. It is mechanical, and it is one commit.

```ruby
module RGame
  module Engine
    module Scene
      class Rooms < Engine::Component
        Move = Data.define(:node, :name, :location, :player)

        def move(nodes, to:, location: nil, transition: @rgame_transition)
      end

      class Room < Engine::Node2D
        # Places `node`, which a move brought to this room at `location`.
        def _arrive(node, location); end
      end
    end
  end
end
```

The doors in `examples/doors` and `adventure` keep their Tiled property
`entrance`, and pass it on as `location:`. The map class `entrance` and
`examples/assets/README.md` keep theirs.

**Tests.** The 118 lines in 18 files, renamed: chiefly `rooms_spec.rb`,
`rooms_move_spec.rb`, `rooms_music_spec.rb`, `rooms_allocation_spec.rb`,
`scene_stack_spec.rb`, `cutscene_spec.rb`, `spec_room.rb` and
`spec/tools/drive_test_project/report_spec.rb`. No example changes meaning.

**Verify.** `rake spec` and `rake spec:core` pass.
`grep -rn "entrance:" lib spec examples test_projects docs/api` lists only the
doors' Tiled property. `ruby tools/drive_test_project.rb examples/doors/main.rb`
and the same for `test_projects/adventure/main.rb` enter the same scenes as
before.

### 1. Named locations on `TileWorld` (pure)

**Why here.** Step 3's `RoomPoint` checks its ground through this lookup, and
step 4's code-built checkpoints register here. The map stays frozen (decision 6).

#### 1a. `MapObject#origin_x` and `#origin_y`

Moved out of `MapBuilder#origin_x`/`origin_y` (`map_builder.rb:134-144`), which
then calls them.

```ruby
MapObject = Data.define(...) do
  # Where a node built from this object stands, in pixels: the object's own
  # point for a point, a polygon or a polyline, and the bottom centre of its
  # box, turned by `rotation`, for any other shape.
  def origin_x
  def origin_y
end
```

**Tests.** `map_builder_spec.rb` passes unchanged. A new
`spec/rgame/engine/map_object_spec.rb` covers the origin of a point, of a box,
of a rotated box, and of a polygon and a polyline, which the builder leaves
unboxed (`MapBuilder::UNBOXED`).

#### 1b. `TileWorld#location`, `#add_location` and `#remove_location`

```ruby
class TileWorld < Engine::Component
  # A place a room can name, in world pixels.
  Location = Data.define(:x, :y)

  # Where the place named `name` is: the origin of the map's object of that
  # name, or where the node added under it stands now. Raises KeyError listing
  # the names it knows when none has it, and ArgumentError when two of the
  # map's objects share it.
  def location(name)

  # Names the place `node` stands as `name`, until #remove_location. Raises
  # ArgumentError for a name already added, and for a name the map gives an
  # object other than `node`'s own.
  def add_location(name, node)

  def remove_location(name)
end
```

Rules:

1. A map object's location is its origin (1a).
2. An added name answers where its node stands when asked, not where it stood
   when added.
3. A node built from the map's object of that very name (its `map_object_id`)
   adds nothing and raises nothing: the map answers for it.
4. A name the map gives another object, or a name added twice, raises as it is
   added, naming the name and both owners.
5. An unknown name raises `KeyError` listing the map's names and the added ones.
6. The registry belongs to the `TileWorld` instance, so a room built again starts
   with none.

**Tests.** `tile_world_spec.rb`, one case for each rule. `WalledTileMap.build`
gains an `objects:` keyword so a spec map can name places.

#### 1c. The rooms built over a map look up through their `TileWorld`

`examples/doors/main.rb:161`, `adventure`'s `town.rb:99` and `garden.rb:42`, and
`tile_maps.md:464` change `@map.object_named(location)` to
`get_component(Components::TileWorld).location(location)`. `scene_graph.md:971`
says the same in prose. `SpecRoom` keeps its table.

**Verify.** `rake spec`, which runs `tile_maps.md`'s example, and `rake spec:core`,
which needs the three new `TileWorld` methods documented. Driving `doors` and
`adventure` with `--seed 1 --texts` prints the same strings as before the step,
since every entrance is a point.

### 2. `Respawn` takes a point

**Why now.** It closes the crash on its own, and step 3 adds the second kind of
point to an interface that already exists. It adds no room behaviour beyond
decision 7's raise.

```ruby
module RGame
  module Engine
    module Scene
      class Room < Engine::Node2D
        # The room `node` stands in: its nearest enclosing scene that is a
        # Room, or nil.
        def self.of(node)
      end
    end

    module Components
      class Respawn < Engine::Component
        # A respawn point at world coordinates.
        Point = Data.define(:x, :y) do
          # None: Respawn keeps the room the node stood in as it set the point.
          def room = nil

          # Places `node` on the point. Returns true: the node stands there now.
          def place(node)

          # Raises ArgumentError when `world` has no ground under the point.
          def check_ground(world)
        end

        signal :respawned

        # The point, nil until the first attach.
        sealed_reader :point

        # A new point, answering `room`, `place` and `check_ground`. Returns
        # self. Once attached, raises ArgumentError for a point over a gap in
        # the room the node stands in, and keeps the point it had.
        def set_point(point)

        # Places the node on its point. Raises for a point with no room while
        # the node stands in another room than the one it stood in as the point
        # was set.
        def respawn
      end
    end
  end
end
```

Rules:

1. The first attach with no point takes a `Point` where the node stands.
2. `set_point` raises `TypeError` for an object missing `room`, `place` or
   `check_ground`.
3. A point with no room belongs to the room the node stood in as it was set. For
   a point set before the first attach, that is the room of the first attach.
4. A point is checked for a gap only while the node stands in its room. An
   attach in another room checks nothing.
5. `respawn` with a point that has no room, while the node stands in another
   room, raises and names both rooms. The message says to set a room point.
6. Outside rooms, behaviour is today's: `Room.of` is nil at the set and at the
   respawn.

`Checkpoint#reach` passes `Respawn::Point.new(x: node.world_x, y: node.world_y)`.
`topdownplatformer/course.rb:49` reads the primary hero's `respawn.point.x`
and `.y`. The docs for `Respawn` and `Checkpoint` in `components.md` follow.

**Tests.**

- `respawn_spec.rb`: the point readers become `point.x`/`point.y`, and every
  existing case passes. A new case for each of rules 2 to 5 builds two
  `Scene::Room` nodes as scenes.
- `a_respawn_point.rb`, the new shared example group, run for `Point`.
- `checkpoint_spec.rb`'s `point` helper reads the object.
- `fall_spec.rb` and `platforming_spec.rb` pass with `set_point`'s argument
  changed.

**Verify.** `rake spec` and `rake spec:core`. Driving `topdownplatformer`,
`pits` and `moving_platforms` with `--seed 1` reports the same draw counts and
sounds as before the step.

### 3. A point in a room

**Why now.** This is the step the plan exists for. It lands the composed spec
that CLAUDE.md asks for when two systems have never met.

#### 3a. The spec that composes both, pending

`spec/rgame/engine/components/respawn_across_rooms_spec.rb` builds rooms `:a` and
`:b`, each over a `WalledTileMap` with gaps and named places. A hero with
`Footing`, `Fall` and `Respawn` lands in `:a` at `gate`, moves to `:b`, and
walks into a gap. The spec expects the fall to end with the hero in `:a` at
`gate`, its player standing in `:a`, and `on_respawned` fired once as it
landed. RSpec's `pending` keeps the branch green while it fails, and raises
once it passes, which forces 3c to remove it.

#### 3b. `RoomPoint`, and `Rooms` hands the first one

```ruby
class Respawn < Engine::Component
  # A respawn point at a named location in a room of the scene's Scene::Rooms.
  RoomPoint = Data.define(:room, :location) do
    # Places `node` at the location. In the room the node stands in, the
    # room's _arrive places it at once, and this returns true. From another
    # room, the rooms move it there, and this returns false.
    def place(node)

    # Raises ArgumentError when `world` has no ground under the location.
    def check_ground(world)
  end

  # Scene::Rooms calls it as a move lands the node, before the room's
  # _arrive. A Respawn with no point takes a RoomPoint there.
  # @api private
  def take_landing(room, location)
end
```

`Rooms#land` calls it between taking the node from its old parent and calling
`_arrive`:

```ruby
moving.get_component(Components::Respawn)&.take_landing(move.name, move.location)
room._arrive(moving, move.location)
```

Rules:

1. A node's first landing hands its `Respawn`, if it has no point, a `RoomPoint`
   at the landing's room and location. A later landing changes nothing
   (decision 4), and neither does a warp (decision 5).
2. A respawn whose `RoomPoint` is in the node's own room places it through
   `_arrive` at once. `on_respawned` fires in that tick, and nothing is
   suspended.
3. A respawn into another room moves the node with the rooms' transition.
   `on_respawned` fires once, as the node attaches in that room.
4. `Fall#on_finished` fires as the fall ends, before that landing (decision 8).
5. A respawn whose move another move replaces ends with no `on_respawned`.
6. A `RoomPoint` is checked for a gap as the node attaches in its room, and the
   raise names the room and the location.

**Tests.** `respawn_spec.rb` covers rules 2, 3, 5 and 6. `a_respawn_point.rb`
runs for `RoomPoint`. `rooms_spec.rb` covers rule 1, including the warp.
`fall_spec.rb` covers rule 4.

#### 3c. The composed spec passes, and the docs follow

`pending` comes out of 3a's spec. `components.md` documents `RoomPoint` and the
new timing of `on_respawned`, and `Fall`'s `on_finished` wording.
`scene_graph.md` says a move hands a `Respawn` its first point, and that a
respawn in its own room runs `_arrive` as a warp does. `CHANGELOG.md`'s
unreleased `Respawn` entry follows.

**Verify.** The composed spec passes without `pending`, and `rake spec` and
`rake spec:core` pass. Driving `doors` and `adventure` with `--seed 1 --texts`
prints the same strings as before the step: their heroes carry no `Respawn`.

### 4. A checkpoint's location *(rough)*

`Checkpoint.new(by:, location: nil)`. In a room, a touch hands the toucher a
`RoomPoint` at its room and location, and a checkpoint in a room without a
location raises at attach. One built in code registers its location with the
`TileWorld` (step 1b), and removes it as it detaches. `Flag` passes its name as
its location. The composed spec gains the checkpoint case: touch one in `:a`,
walk into `:b`, fall, and come back at the checkpoint in `:a`.

To settle when this is re-planned:

- What a `location:` means outside rooms: ignored, or refused.
- Whether `example_assets_spec.rb` checks checkpoint locations (open question 2).

### 5. Fold the plan back, and delete it *(rough)*

- `docs/api/components.md` (`Respawn`, `Checkpoint`, `Fall`),
  `scene_graph.md` (`Rooms`, `Room`) and `tile_maps.md` say what the code does,
  with nothing of this plan's history.
- `possible-todos.md` loses "A respawn point in a room left behind".
- Anything still true in "Traps" moves into the class comments it belongs to.
- This file is deleted.

**Verify.** `CHANGELOG.md`'s unreleased entries for `Respawn`, `Checkpoint` and
`Rooms`, and a new one for `TileWorld#location`, match what shipped, by the
[update-changelog](../../.claude/skills/update-changelog/SKILL.md) skill.
`rake spec` and `rake spec:core` pass, and `grep -rn "respawn-rooms" docs`
finds nothing.
