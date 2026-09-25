# Current state

What rgame does with a Tiled object layer today, what the maps and projects
hold, and what already resembles the work. Read off `abb91ad`, and off
`origin/build-step-8-tiled-map` for the half-authored `tour.tmx`.

## Where this started

Step 3 of the y-sort plan wanted a tree placed as a tile object to sort like an
actor. Tall scenery is two tile layers today: the trunk on a ground layer, the
crown on a layer marked `above`, and the `:actors` slot between them. So an actor
draws over every trunk and under every crown wherever they stand, and a crown
covers the head of an actor standing just below it. A tile layer draws in one go,
so it has no position to sort by. A tile object is one picture at one position.

The step could not say where such a node goes without an answer for every
object, so it moved to research, and the research to this plan. The Tiled format
plan had stopped short of it on purpose. Its decision 11 read: "The parser reads
object layers into records, and stops there. No node is ever built from a map."

## How the engine treats object layers today

**The loader keeps every object, and the layer it sat in.** `TileMap.from_tiled`
reads every object of every object layer into a `MapObject`
([from_tiled.rb:120](../../../lib/rgame/engine/tile_map/from_tiled.rb#L120)).
Each carries `layer`, the index of its layer, and a tile object carries `tile`
and `orientation`. The loader moves a tile object's corner from Tiled's
bottom-left to the top-left, so `x` and `y` are the top-left corner for every
shape ([from_tiled.rb:148-162](../../../lib/rgame/engine/tile_map/from_tiled.rb#L148-L162)).

**Nothing reads `layer`.** *(Measured.)* No code under `lib/`, `examples/` or
`test_projects/` reads `MapObject#layer`.

**`mount` skips object layers, so nothing draws a tile object.**
`TileMapLayer.mount` builds a node for each tile and image layer. It skips object
layers: "An object layer gets no node, since it has nothing to draw"
([tile_map_layer.rb:74-84](../../../lib/rgame/engine/tile_map_layer.rb#L74-L84)).

**The scene names the parent of every node built from an object.**
`MapObjects#spawn_into(parent, objects)` builds a node from each object whose
class has a block. The documentation states the rule: "Nothing spawns a map's
objects unless the scene asks." Every caller passes all of `map.objects`, so the
class picks the block and the scene picks the slot. Moving an object layer in
Tiled changes nothing in the game.

**For tile layers, Tiled's order is the draw order.** `TileMapLayer`'s header
gives the reason: "A designer already orders layers in Tiled and can see the
result there." For object layers it means nothing.

## What the parse and the transform leave out

*(Measured.)* Six gaps, each silent today:

| Gap | Where | What happens |
|---|---|---|
| **A capsule reads as a rectangle** | [object.rb:8](../../../lib/rgame/engine/tiled/object.rb#L8) knows five child shapes | `tour.tmx`'s object 4, a `<capsule/>`, comes out `:rectangle`. Any shape Tiled adds later would too |
| **A class property loses its class** | [properties.rb:53](../../../lib/rgame/engine/tiled/properties.rb#L53) | the members arrive as a nested bag, and `propertytype` is dropped |
| **An object layer's draw order is dropped** | [map.rb:230](../../../lib/rgame/engine/tiled/map.rb#L230) reads `draworder` | `TileMap::Layer` carries no draw order |
| **A tile object keeps only its own class** | [from_tiled.rb:154](../../../lib/rgame/engine/tile_map/from_tiled.rb#L154) | Tiled says a tile's class "is inherited by tile objects", and the map already keeps a class per tile ([from_tiled.rb:78](../../../lib/rgame/engine/tile_map/from_tiled.rb#L78)) |
| **`objectalignment` is not read** | `Tiled::Tileset` | a tile object is always placed by its bottom-left corner, which is right only while the tileset leaves it `unspecified` |
| **A map's source path is absolute in a game** | [game.rb:298](../../../lib/rgame/game.rb#L298) loads the path `AssetManager#resolve` expands | `TileMap#source.path` differs between machines. `TileWorld#tilemap_id` holds the asset key, such as `'map/town.tmx'` |

## What today's maps hold

*(Measured.)* Seven maps are tracked, and `beach_large.tmx` is not:

| Map | Object layers | Object classes | Tile classes |
|---|---|---|---|
| `examples/assets/garden.tmx` | `doors` | `entrance` ×4, `door` ×2, `warp` ×2 | — |
| `examples/assets/town.tmx` | `doors` | `entrance` ×3, `door` ×1 | — |
| `examples/assets/platforms.tmx` | `spawns`, `platforms` | none ×1, `platform` ×1 | `gap` |
| `examples/assets/pits.tmx` | `spawns` | none ×1 | `gap` |
| `examples/assets/puzzle.tmx` | none | — | — |
| `test_projects/topdownplatformer/course.tmx` | `spawns`, `platforms` | none ×1, `checkpoint` ×3, `crate` ×1, `walker` ×1, `platform` ×2 | `gap` |
| `media/map/beach_large.tmx` *(untracked)* | `Objects`, above the `above` layer `Over` | `start` ×1 | — |

- **13 objects in 4 maps take a node class's name**: `door`, `warp`,
  `platform`, `checkpoint`, `crate` and `walker` become `Door`, `Warp`, `Raft`,
  `Flag`, `Crate` and `Walker`.
- **8 objects carry a data class**, `entrance` or `start`, and stay data.
- **`gap` is a terrain class** in 3 maps, read by `TileMap`
  ([tile_map.rb:149](../../../lib/rgame/engine/tile_map.rb#L149)).
- **`tour.tmx` on the authoring branch** is 40×40 with 11 layers, 401 tiles and
  9 objects, all in `Object Layer 1`. Everything but the capsule loads as Tiled
  shows it.

## What builds nodes from objects today

*(Measured.)* 5 scenes, 10 builder blocks:

| Scene | Class | Builds | Needs besides the object |
|---|---|---|---|
| `examples/doors/main.rb` | `door`, `warp` | `Door` | `world: parent`; a warp also the room's `name` |
| `test_projects/adventure/garden.rb` | `door`, `warp` | `Door` | the same |
| `test_projects/adventure/town.rb` | `door` | `Door` | `world: parent` |
| `examples/moving_platforms/main.rb` | `platform` | `Raft` | nothing |
| `test_projects/topdownplatformer/course.rb` | `platform`, `checkpoint`, `crate`, `walker` | `Raft`, `Flag`, `Crate`, `Walker` | the walker takes the scene's `rng` |

6 of the 10 close over scene state. `Door` also picks its colour from
`object.class_name`, so a warp and a door share one class today.
`Scene::Rooms` is a component, so a door built without its scene can reach it
with `system(Scene::Rooms)`.

## Components a map could configure

*(Measured, from the constructor signatures.)* Of 39 components, 29 take only
keywords whose values Tiled can express: numbers, strings, booleans, a Symbol as
a string or an enum. The other 10:

| Component | Why a map cannot build its arguments |
|---|---|
| `ActionTrigger` | a positional Hash |
| `CameraFollow` | a camera |
| `Collider` | abstract |
| `Cutscene` | a script |
| `Pool` | a block |
| `TileWorld` | a map |
| `Timer`, `Tween` | positional arguments |
| `WanderController` | an RNG and a Range |
| `Mover` | abstract |

Lists of Symbols, such as `blocked_by: [:tiles, :actors]`, count among the 29
through their other keywords only. Tiled has no list type.

## Randomness

*(Measured.)* 9 projects seed their own `Random` from `RGAME_SEED`, in the scene:
`examples/pooling`, `game_menu`, `save_load`, `save_load_ids` and `effects`, and
`test_projects/topdownplatformer`, `tiled_world`, `adventure` and `asteroids`.
All but `asteroids` fall back to a `DEFAULT_SEED`, and `asteroids` runs unseeded
without the variable. Two engine components default to an unseeded `Random.new`:
`Particles` and `WanderController`. Three call sites rely on that default: two in
`examples/effects` and one in `test_projects/adventure/sparkles.rb`.

## What already resembles this

**Reuse it.**

- **`MapObject`, `TileMap#objects` and `object_named`.** Data objects stay read
  this way, and a map-built node keeps its record.
- **`Node2D#y_sort`.** An object layer's node is a y-sorted parent.
- **`Engine::Anchor`'s `:bottom`.** A tile object's picture stands on its node's
  origin, as the sprites' do.
- **`TileWorld#tilemap_id` and `#elapsed`.** The id names the map to the renderer
  and in a fact key. The elapsed seconds animate a tile object's tile.
- **`Facts`.** A map-built node that keeps state keeps it there, as
  `test_projects/adventure/chest.rb` does.
- **`system!`.** How a map-built node finds its room, its facts and its random
  source.
- **`TiledFixture`.** Spec maps come from `.tmx` strings, so the builder is
  tested against the producer it meets.

**Extend or generalise it.**

- **`TileMapLayer.mount` already builds a node per layer.** Object layers join
  the same loop as a third kind. They stop being skipped.
- **The `above` mark gets a sibling.** `actors` is read the same way: a bool
  property on a layer, read once by the transform, answered as `actors?`.
- **`TileMapRenderer#draw_tile` already places one tile.** It is private, and it
  draws at a cell. The single-tile draw opens it to a position.
- **`Renderer#tilemap` forwards to the registered map.** `map_tile` forwards the
  same way, in the live renderer and in the fake.
- **`Signal::DSL` and `Engine::Hooks` declare at class level, and the engine
  checks.** `map_settings` is a third declaration of that shape.
- **`Facts` is a system on the root that `RGame::Game` mounts.** The random
  source is a second one.

**Genuinely new.**

- **Building a node on the game's behalf, from a class name.** `Pool` builds
  nodes, but from a block the game gives it.
- **Applying map values to the components a node builds.** No component has
  writers for its settings, and 29 would need them.
- **Writing Tiled custom types from Ruby.**
