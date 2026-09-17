# How other engines read Tiled

Six implementations, chosen because each answers one of the questions this plan
has to answer. What matters is not that they are similar — they are — but the
two places they all land in the same spot, and the one place none of them helps.

## libGDX — the closest structural match

libGDX parses `.tmx` at runtime, in the game's own process, into plain objects.
That is what rgame does, and libGDX is the only one of the six that does it the
same way.

Its shape ([libgdx.com, Tile maps](https://libgdx.com/wiki/graphics/2d/tile-maps)):

| | |
|---|---|
| `TiledMap` | the root; holds `MapLayers` and `TiledMapTileSets` |
| `MapLayers` | a heterogeneous, ordered, name-indexed list |
| `TiledMapTileLayer` | a grid of `Cell`, each holding a tile reference **plus its flip and rotation** |
| `TiledMapTileSets` | **several** `TiledMapTileSet`, each with its `firstgid` |
| `MapProperties` | "essentially a hash map, with string keys and arbitrary values" |
| `TiledMapTile` | id, properties, and its collision `MapObjects` |
| `OrthogonalTiledMapRenderer`, `IsometricTiledMapRenderer`, … | **one renderer per orientation** |

Three things to take. Tilesets are a collection with `firstgid`, and a layer may
draw from any of them. Flip and rotation live **on the cell**, not on the tile —
the tile is shared, the orientation is per-placement. And orientation is handled
by swapping the renderer, which is the seam
[decision 1](README.md#decisions-already-taken) buys.

One thing to leave. libGDX allocates a `Cell` object per non-empty tile. rgame
holds a dense `Util::Tensor` of integers, which is why a 60×40×2 map costs
4800 slots rather than 4800 objects. Keep that, and the orientation has to live
somewhere other than an object — see
[the design](03-design.md#orientation-eight-of-them-decoded-once).

## SuperTiled2Unity — the object-to-node mapping, done at import

Unity's importer converts a `.tmx` into a prefab when the file lands in the
project, and objects become GameObjects. The interesting part is **Prefab
Replacements**: a table in project settings keyed by the Tiled object's **type
(class)**, mapping it to a prefab. At import, each matching object becomes an
instance of that prefab, and "any custom properties on your Tiled Object with a
name that matches a field in your prefab's components will be automatically
applied"
([SuperTiled2Unity docs](https://supertiled2unity.readthedocs.io/en/latest/manual/extending-the-importer.html)).

This is the registry in
[decision on nodes-on-a-map](03-design.md#nodes-on-a-map), and it confirms the
key: **the object's class, not its name and not its gid.** A name identifies one
object; a class identifies a kind, which is what a factory is for.

Its property-to-field auto-assignment is the part to reject. Setting fields by
string name is invisible to every tool and fails at import with a message about a
field, not about a map.

## Bevy — `bevy_ecs_tiled`

Every Tiled item becomes an entity, arranged in a hierarchy: "layers are children
of the map entity, tiles and objects are children of their respective layers". It
turns **custom properties into components**, which is the same idea as the
registry with the key moved from class to property name
([bevy_ecs_tiled](https://github.com/adrien-bon/bevy_ecs_tiled)).

It supports external and embedded tilesets, atlases and multiple images,
animated tiles and image layers — which is a useful confirmation that
[decision 6](README.md#decisions-already-taken)'s list is the list a real
consumer needs, not a superset.

The entity-per-tile model is the thing to reject, for the same reason as
libGDX's `Cell`.

## Godot

Godot has no built-in Tiled reader. Community importers convert a `.tmx` into
Godot's own `TileMap` and `TileSet` resources at import time.

Godot's native `TileSet` is worth one look anyway, because it solved the flip
question differently: an oriented tile is an **alternative tile**, a separate id
in the tileset, generated for each orientation actually used. That is a third
option alongside "flip on the cell" and "flip packed in the gid", and it is
rejected here for a plain reason — it makes the tile id depend on which
orientations a map happens to contain, so the same tileset yields different ids
in two maps.

## Phaser 3

`map.createFromObjects(layerName, config)` builds sprites from an object layer,
with the config matching on gid, name or type. Same mapping table, third
independent arrival at it.

## pytmx and tmxlite

Both are pure readers with no engine attached, and both are structured as one
class per element: `TiledMap`, `TiledTileLayer`, `TiledObjectGroup`,
`TiledObject`, `TiledImageLayer`, `TiledGroupLayer`, with properties as a plain
dict on each.

This is the parse/runtime split of
[decision 8](README.md#decisions-already-taken) with the runtime half missing,
and it is evidence that the parse half stands on its own — these libraries are
useful precisely because they assert nothing about how a game uses the result.

## What they agree on

1. **Tilesets are a collection ordered by `firstgid`,** and resolving a gid means
   finding the last tileset whose `firstgid` is not greater than it. Every one of
   the six does this identically.
2. **Orientation is chosen once and swapped out,** never branched on per tile.
3. **Properties are an untyped-at-the-boundary bag** attached to every element.
4. **Objects map to game entities by class,** through a table the game supplies.
5. **The parse is separate from the thing that draws.** Even libGDX, which does
   both at runtime, keeps `TiledMap` free of any drawing.

## What none of them gives us

- **A layer index that survives group layers.** libGDX nests `MapLayers`;
  Phaser flattens; pytmx exposes both. None of them has rgame's constraint, which
  is that a layer index is also a **z slot in a scene tree** — `TileMapLayer`
  mounts one node per layer and the actors go in a gap between two of them. So
  the flattening rule is ours to choose, and it has to be stable: inserting a
  group in Tiled must not silently move where the actors draw.
- **A headless layer that may not name the renderer.** Every one of the six
  parses straight into engine types that hold textures. rgame's parser may not
  hold an image at all ([constraint 1](README.md#hard-constraints)), which is why
  `TileMap.load` returns a path and why this plan has to return several paths
  rather than one.
- **A reason to keep the whole file.** They are libraries and must serve
  everybody. This is one engine with one orientation and a documented supported
  subset, and saying no is cheaper here than anywhere on that list.
