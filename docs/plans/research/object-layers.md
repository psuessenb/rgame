# Object layers and draw order

Where in the draw order does something from a Tiled object layer go, and who
decides? Today the scene decides for every object, and the layer the object sits
in plays no part. Tile objects cannot draw until the engine answers this once for
every object. This document collects what is known, read off the code at
`0c7dc18`.

This is research, not a plan. It schedules nothing. It started as step 3 of the
y-sort plan, "Tiled tile objects as sorted nodes". It left that plan because the
step could not be built without settling the question for every object.

## The step it came from

The y-sort plan sketched it like this:

> A designer places a tree as a tile object, and it sorts like an actor. `mount`
> builds a node for each tile object in an object layer and adds it to the slot
> above that layer. The node draws its tile anchored at the feet, as step 2 made
> the sprites do. `MapObject` already carries the tile and its top-left corner,
> and an object layer gets no node today.
>
> This needs a renderer call that draws one tile of a tileset, which is Core
> work the engine reaches by name (hard constraint 1). `test_projects/tiled_world`
> gains a tree placed as a tile object, and the drive script walks behind it.

That plan also held an open question for it: the renderer has `tilemap` for a
whole layer, and no call for one tile of a tileset.

### What a tile object would fix

**Tall scenery is two tile layers today, and it covers an actor wherever they
stand.** The trunk sits on a ground layer and the crown on a layer marked
`above`. `TileMapLayer.mount` puts the `:actors` slot between them, so an actor
draws over every trunk and under every crown. Walking behind a palm looks right.
Standing just below one, the crown still covers the actor's head.

A tile layer draws in one go, so it has no position to sort by. A tree placed as
a tile object is one picture at one position. The y-sort from the plan's step 1
could order it against the actors by its base. The canopy layer stays the answer
for scenery that always covers actors.

**Platforms want tile objects too.** The rafts in `examples/moving_platforms` and
`test_projects/topdownplatformer` draw their planks tile by tile in code. Placed
as a tile object, a platform would carry both a class,
`platform`, and a tile for the registry's block to draw. `possible-todos.md`
lists it under "Loose ends from top-down platforming".

## How the engine treats object layers today

### The loader keeps every object, and the layer it sat in

`TileMap.from_tiled` reads every object of every object layer into a `MapObject`
([from_tiled.rb:120](../../../lib/rgame/engine/tile_map/from_tiled.rb#L120)).
Each carries `layer`, the index of its layer. A tile object also carries `tile`,
the map's own id for the tile, and `orientation`. Tiled measures a tile object
from its bottom-left corner. The loader moves that to the top-left, so `x` and
`y` are the top-left corner for every shape
([from_tiled.rb:148-162](../../../lib/rgame/engine/tile_map/from_tiled.rb#L148-L162)).

### Nothing reads `layer`

*(Measured.)* No code under `lib/`, `examples/` or `test_projects/` reads
`MapObject#layer`.

### `mount` skips object layers, so nothing draws a tile object

`TileMapLayer.mount` builds a node for each tile layer and image layer. It skips
object layers, and its comment says why: "An object layer gets no node, since it
has nothing to draw"
([tile_map_layer.rb:74-84](../../../lib/rgame/engine/tile_map_layer.rb#L74-L84)).

*(Measured.)* No map uses a tile object. That covers the seven `.tmx` files the
repository tracks and the untracked `media/map/beach_large.tmx`.

### The scene names the parent of every node built from an object

`MapObjects#spawn_into(parent, objects)` builds a node from each object whose
class has a block, and adds it under `parent`. The documentation states the rule
in [tile_maps.md](../../api/tile_maps.md#building-nodes-from-objects): "Nothing
spawns a map's objects unless the scene asks. The scene calls `spawn_into` and
chooses the parent." The header of
[map_objects.rb](../../../lib/rgame/engine/map_objects.rb) says the same.

*(Measured.)* Every caller passes all of `map.objects`:

| Scene | Classes it builds | Parent |
|---|---|---|
| `examples/doors/main.rb` | `door`, `warp` | `slots[:doors]` |
| `examples/moving_platforms/main.rb` | `platform` | `slots[:platforms]` |
| `test_projects/adventure/garden.rb` | `door`, `warp` | `slots[:doors]` |
| `test_projects/adventure/town.rb` | `door` | `slots[:doors]` |
| `test_projects/topdownplatformer/course.rb` | `platform` | `slots[:platforms]` |
| `test_projects/topdownplatformer/course.rb` | `checkpoint`, `crate`, `walker` | `slots[:actors]` |

The class picks the registry, and the scene picks the slot. The object's layer
changes nothing. `course.tmx` and `platforms.tmx` each have two object layers,
`spawns` and `platforms`. Moving `platforms` under `obstacles` in Tiled would
change nothing in the game. `test_projects/tiled_world` places its NPCs from
offsets in code, not from the map.

### For tile layers, Tiled's order is the draw order

`TileMapLayer`'s header gives the reason: "A designer already orders layers in
Tiled and can see the result there." A designer who reorders tile layers sees
the change in the game. A designer who reorders object layers sees none.

## Why tile objects expose it

**The step had `mount` build the nodes on its own.** That breaks the documented
rule that only the scene spawns a map's objects. It also leaves `mount` to choose
a parent with no scene involved, from the one fact the rest of the engine ignores:
the object's layer.

**"The slot above that layer" has no definition.** A slot sits under the layer
that covers it, and no slot belongs to an object layer. The step does not say
what happens when:

- the object layer is not next to a slot. In `beach_large.tmx`, `Objects` comes
  after `Over`, the layer marked `above`, so the default `:actors` slot sits
  below both.
- the scene mounts two slots, as `course.rb` mounts `:platforms` and `:actors`.

NPCs and chests face the same question. It does not show for them only because
every scene answers it by naming a slot.

## A constraint any answer must meet

**Nodes that sort together must share one parent.** Y-sort orders one node's
children. A sorted node inside another sorts as one unit, at its own footing. So a
tree sorts against the hero only when both are children of the same node.

The hero is not on the map. A scene adds them from code when a player joins. So
the scene must be able to name the node the trees went into, whichever answer is
taken.

## Two answers

### A — the scene decides, as it does for every object today

Tile objects go through `spawn_into`, like chests. For example, the registry
builds a picture node for a tile object, and the scene's existing
`spawn_into(slots[:actors], map.objects)` line places the trees too.

- It keeps the documented rule, and one path from object to node.
- `mount` does not change.
- An object layer's position in Tiled still means nothing.
- The registry's rule changes. Today "an object of a class nobody defined builds
  nothing", and a tree placed with no class would build a picture. A tile object
  whose class has a block raises a second question: does the block draw the
  tile, or does the registry?

### B — Tiled decides

Each object layer becomes a slot at its place in the layer stack, named after
the layer. Tile objects join their own layer's slot, and `spawn_into` could
default to the same.

- Order means the same for objects as for tiles.
- Every map with object layers needs a look. In `platforms.tmx` both object
  layers come after `obstacles`, and the rafts must draw under the actors
  spawned from `spawns`. In `beach_large.tmx`, `Objects` would draw over the
  canopy.
- **It sets a trap.** Two object layers become two parents, and their children
  never sort against each other. A hero spawned into `spawns` would never sort
  against a tree in `scenery`. Designers would have to learn that nodes which
  sort together share an object layer. CLAUDE.md's "Design out misuse" rejects
  exactly such a rule.
- A slot could then be named two ways: by `mount`'s `slots:` keyword, or by an
  object layer.

### Direction

**The loader builds, not the scene.** An object layer becomes a node in the map,
and its objects become nodes inside it. Each object's class and properties
decide what it becomes, including properties that belong to one of its
components. That is B, with a registry to build from. It leaves open where an
actor goes on a map with no object layer. [object-layers-prior-art.md](object-layers-prior-art.md)
collects how other engines and Tiled itself answer these questions.

## What a tile object needs, whichever answer is taken

- **A renderer call for one tile.** `Core::Renderer` draws a whole layer with
  `tilemap(id, layer, …)`. The arithmetic for one tile already exists, private,
  in `TileMapRenderer#draw_tile`
  ([tile_map_renderer.rb:222](../../../lib/rgame/core/tile_map_renderer.rb#L222)).
  It applies the tile's offset, aligns it to the bottom of its cell and turns it
  by its orientation. The engine calls the new method by name, so `FakeRenderer`
  and the shared renderer contract get it too.
- **A base to sort by.** With its origin at the bottom centre of the tile,
  `(x + width / 2, y + height)`, a node with no `BoxCollider` sorts by its base.
  That is `Engine::Anchor`'s `:bottom`, the sprites' default. A rotated tile
  object has no obvious base.
- **The animation clock.** `TileMap#frame_tile(tile, elapsed)` picks an animated
  tile's frame. `Components::TileWorld` holds the elapsed time, and the node needs
  it at draw time.
- **No allocation per frame.** Every tile object draws every frame.
  `rake drive:allocations` decides.
- **Collision is separate.** Nothing makes a tile object solid. A tree's trunk
  still needs a solid tile or a collider.
- **A tracked map for the acceptance test.** `test_projects/tiled_world` loads
  `media/map/beach_large.tmx`, and `.gitignore` excludes `/media/`. A tree placed
  there would reach neither the repository nor CI. The test needs a map the
  repository tracks, such as `examples/assets/` or a test project's own folder
  like `topdownplatformer/course.tmx`.

## Open for the plan

1. Answer A, answer B, or another.
2. What a tile object whose class has a block builds. A platform is the first
   case.
3. Which tracked map carries the acceptance test.
