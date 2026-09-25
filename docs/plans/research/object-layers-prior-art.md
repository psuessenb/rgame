# Object layers in other engines

**Most Tiled loaders that do more than hand over data build the nodes
themselves.** They pick what to build from the object's Tiled class and put the
result in the object's own layer, so Tiled's layer order stays the draw order.
They differ most in how a property reaches the component that uses it. None of
them has a good answer for an actor the map does not contain.

This is research, not a plan. It follows [object-layers.md](object-layers.md) and
its direction: the map parses an object layer, the layer gets a node, and that
node's children are built from the objects. Each object's class and properties
decide what it becomes, including properties that belong to one of its
components. Sources were read on 2026-09-25. Claims about rgame are read off
`dcb07f8`.

## At a glance

| Engine or loader | Who builds from an object | Keyed by | Where the result goes | How a property arrives | An object nothing claims |
|---|---|---|---|---|---|
| libGDX | the game | — | wherever the game puts it | a `MapProperties` bag | stays data; `renderObject` is an empty hook |
| DRTiled with tiledriver (DragonRuby) | the game | — | the game hands its sprites and a depth to `render_map` | a bag | stays data |
| HaxeFlixel's Tiled demo | the game | a `switch` on the type | groups the game orders by hand | read inside the `switch` | ignored |
| Phaser 3 | the loader, when the game calls `createFromObjects` for one layer | id, gid, name or type, and a `classType` | the scene, or a container passed in | onto a field of that name, else into the object's data | not built |
| Excalibur's Tiled plugin | the loader | the class, through `entityClassNameFactories` | the scene, at a `zindex` | the factory gets the bag; seven names are reserved | a plain `Actor`, with a sprite for a tile object |
| ponytiled (Solar2D) | the loader draws every object; `map:extend` adds code | the type, naming a Lua module | its object layer's display group | eleven physics names go to the body, the rest onto the object | drawn as an image |
| STI (LÖVE) | the loader draws tile objects; the game does the rest | — | tile objects in their own layer; game sprites in a custom layer | a bag | a tile object is drawn |
| bevy_ecs_tiled | the loader | the class, as a registered Rust type | a child of its layer's entity, at the layer's z | a class becomes a component, its members the fields | an entity holding the raw object |
| SuperTiled2Unity | the importer | the class, through Prefab Replacements | under its layer, in the imported prefab | onto every component with a field, property or method of that name | a GameObject; a sprite for a tile object |
| YATI (Godot 4) | the importer | the class or `godot_node_type`; `instance` with `res_path` for a scene | a `Node2D` per object layer, objects as its children | known names onto the node, the rest into metadata | a node picked by shape |
| Godot's own editor | the designer | the scene they drop in | where they drop it | per instance, in the inspector | — |

## What Tiled says an object layer is for

**Tiled calls objects information for the game.** Its manual: "Using objects you
can add a great deal of information to your map for use in your game. They can
replace tedious alternatives like hardcoding coordinates (like spawn points) in
your source code or maintaining additional data files for storing gameplay
elements." Tile objects are "useful for placement of recognizable interactive
objects that need special information, like a chest with defined contents or an
NPC with defined script"
([Working with Objects](https://doc.mapeditor.org/en/stable/manual/objects/)).

**An object layer y-sorts by default.** The format reference says of
`draworder`: "Whether the objects are drawn according to the order of appearance
("index") or sorted by their y-coordinate ("topdown"). (defaults to "topdown")"
([TMX format](https://doc.mapeditor.org/en/stable/reference/tmx-map-format/)).
A tile object's `y` in the file is its bottom edge, so Tiled's editor already
sorts tile objects by their base, as rgame's y-sort does.

**A tile's class is inherited by tile objects.** The reference says of a tile's
class: "Is inherited by tile objects." The manual adds: "If you're using tile
objects, you can set the class on the tile to avoid having to set it on each
object instance"
([Custom Properties](https://doc.mapeditor.org/en/stable/manual/custom-properties/)).

**Templates hold what repeats.** An instance inherits the template's
properties, and "if a property of a template instance is changed, it will be
internally marked as an overridden property and won't be changed when the
template changes"
([Using Templates](https://doc.mapeditor.org/en/stable/manual/using-templates/)).

**A class can hold another class.** Tiled's own example project,
[`examples.tiled-project`](https://github.com/mapeditor/tiled/blob/master/examples/examples.tiled-project),
models a physics body this way. `Body` has a `fixture` member of class
`Fixture`, and `Fixture` has a `filter` member of class `Filter`. `NPC` and
`Trigger` each carry a `script` file, and `Exit` a `direction` enum. Each class
says which elements may use it: `Body` may sit on a map, a layer, an object or a
tile, and `NPC` only on an object or a tile. In a map file, "only the actually
set members are saved" (TMX format). The defaults live in the project file.

### Tiled's example maps use object layers two ways

- **As a data layer, drawn over everything.**
  [`rpg/island.tmx`](https://github.com/mapeditor/tiled/blob/master/examples/rpg/island.tmx)
  stacks `Ground`, `Fringe` and `Over` tile layers, then an `Objects` layer
  holding a start point, an exit and a resting spot.
  [`orthogonal-outside.tmx`](https://github.com/mapeditor/tiled/blob/master/examples/orthogonal-outside.tmx)
  does the same with `Location`, `Trigger`, `Fixture` and `NPC` objects. There
  the layer's position means nothing. This is the shape of rgame's
  `beach_large.tmx`.
- **As a draw layer that holds the actors.**
  [Sticker Knight](https://github.com/mapeditor/tiled/tree/master/examples/sticker-knight)
  has no tile layer at all. Its eleven layers are object layers, from `static`
  and two parallax layers through `ground`, `castle` and `shading` to `game`,
  `above` and a hidden `bounds`. The hero, the blocks and the coins sit in
  `game` as template instances. The hero is on the map. The block template
  carries `bodyType`, `density` and `friction`. ponytiled, by the same author,
  sends those names to the physics body.

## Who builds, and where the result goes

**Three shapes.**

1. **The loader hands over data and the game builds.** libGDX,
   [DRTiled](https://github.com/wildfiler/drtiled), the HaxeFlixel demo, and
   rgame today. The game then restates the layer order in code.
   [HaxeFlixel's `PlayState`](https://github.com/HaxeFlixel/flixel-demos/blob/dev/Editors/TiledEditor/source/PlayState.hx)
   adds the background, the coins, the images, the objects and the foreground
   in that order, by hand. Its
   [`TiledLevel#loadObject`](https://github.com/HaxeFlixel/flixel-demos/blob/dev/Editors/TiledEditor/source/TiledLevel.hx)
   switches on `player_start`, `floor`, `coin` and `exit`.
   [libGDX's renderer](https://github.com/libgdx/libgdx/blob/master/gdx/src/com/badlogic/gdx/maps/tiled/renderers/BatchTiledMapRenderer.java)
   walks the layers in order and calls `renderObject` for each object of an
   object layer. That method is empty, left for a game to override.
2. **The loader builds from a registry keyed by the class.**
   [Excalibur](https://excaliburjs.com/docs/tiled-plugin/) takes
   `entityClassNameFactories: { 'player-start': (props) => new Player(...) }`.
   A factory receives the position, the name, the class, the layer, the object
   and its properties.
   [ponytiled](https://github.com/ponywolf/ponytiled)'s `map:extend("hero",
   "coin")` requires a Lua module per type and hands each matching display
   object to its `new`.
   [SuperTiled2Unity](https://supertiled2unity.readthedocs.io/en/latest/manual/extending-the-importer.html)
   swaps an object for a prefab named in the project settings, and calls this
   "ideal for spawners".
   [YATI](https://github.com/Kiamo2/YATI) maps the class to a Godot node type,
   and `instance` with a `res_path` property to a whole scene.
   [bevy_ecs_tiled](https://adrien-bon.github.io/bevy_ecs_tiled/guides/properties.html)
   maps it to a registered component type.
   [Phaser](https://docs.phaser.io/api-documentation/class/tilemaps-tilemap#createfromobjects)
   sits between the first two shapes: the game calls `createFromObjects` for one
   layer and names the class to build.
3. **Where the built thing lands.** Most put it in its object layer. bevy_ecs_tiled
   organises "a clear hierarchy: layers are children of the map entity, tiles
   and objects are children of their respective layers". By default each layer
   sits 100 z below the one above it, and "objects on a given layer inherit the Z offset of their parent
   layer" ([Z-ordering](https://github.com/adrien-bon/bevy_ecs_tiled/blob/main/book/src/design/z_order.md)).
   YATI turns an object layer into a `Node2D` with the objects as children.
   ponytiled keeps each object in its layer's display group.
   [STI](https://github.com/karai17/Simple-Tiled-Implementation) batches tile
   objects in their own layer. It sorts them by `y + height` when the layer is
   `topdown`, once, at load. Excalibur is the exception. A factory's entity
   joins the scene, and z comes from a `zindex` property on the object or its
   layer.

**What an unclaimed object becomes varies.** Excalibur builds a plain `Actor`,
with a sprite for a tile object and a collider when `collisiontype` is set.
YATI builds by shape: a `Sprite2D` for a tile object, a `StaticBody2D` for a
rectangle, a `Marker2D` for a point. ponytiled and STI draw a tile object. Phaser
builds nothing it was not asked for.

## How a property reaches what uses it

**Five answers.**

| Answer | Who | Trade |
|---|---|---|
| **Hand over the bag** | Excalibur's factories, libGDX, HaxeFlixel, rgame's `MapObjects` | the builder reads what it wants; nothing checks the rest |
| **By name, onto the built object** | Phaser: "if it has the same property name and a value that isn't `undefined`; or on the Game Object's data otherwise." ponytiled copies every property, and the layer's first | one flat namespace; a typo lands in `data` |
| **By name, onto any component** | SuperTiled2Unity "will search through all `MonoBehaviour` components on an instanced prefab and look for a matching `method`, `property`, or `field`" ([SuperPrefabReplacement](https://github.com/Seanba/SuperPrefabReplacement)) | reaches components with no mapping written; two components with one name both receive it |
| **Reserved names, routed to one subsystem** | ponytiled sends `density`, `friction`, `bounce`, `bodyType`, `radius`, `shape`, `box`, `chain`, `connectFirstAndLastChainVertex`, `outline` and `isSensor` to `physics.addBody`. Excalibur reserves names such as `zindex`, `camera`, `solid` and `collisiontype`. YATI maps dozens of names onto Godot properties | a fixed list the loader owns; a game cannot add a component to it |
| **One Tiled class per component** | bevy_ecs_tiled: a type that derives `Reflect` and is registered becomes a component with the values set in Tiled. The app writes `tiled_types_export.json`, which the designer imports in Tiled's Custom Types Editor. "Properties created only in Tiled (ie. not exported from your app) will not be loaded in Bevy." | typed, and the designer picks from the game's own components; needs an export step |

**YATI shows where matching by name breaks.** A rectangle of class `staticbody`
becomes a `StaticBody2D` with a `CollisionShape2D` child. "Both elements do have a
`use_parent_material` property. Which one of them should the property affect? By
default the property affects the parent. If you want the property to affect the
child, prefix the name with two underscores"
([Reference](https://github.com/Kiamo2/YATI/blob/main/Reference.md)). Every name
it does not know goes into metadata.

**Godot's own editor has no such problem.** A level is a scene, and a designer
places a gameplay object by instancing its scene. Each instance shows its
exported properties in the inspector, and "Editable Children" opens the
properties of the nodes inside it. Its nearest match to a tile that becomes a
node is a scene collection tile source, which places "actual *scenes* as tiles",
such as "shops the player may be able to interact with". The manual warns that
"every scene is instanced individually for every placed tile"
([Using TileSets](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html)).

## Actors the map does not contain

**No loader has a good answer.** Four approaches, and rgame's `slots:` already
belongs to the second:

- **Put the actor on the map.** Sticker Knight places the hero in its `game`
  layer, from a template. That does not fit an actor spawned when a player
  joins, or a map shared by several games.
- **Insert a layer by index.** STI's `map:addCustomLayer("Sprite Layer", 3)`
  inserts a layer with its own `draw` and `update`. `map:convertToCustomLayer`
  turns an existing object layer into one.
  [tiledriver](https://github.com/vinnydiehl/tiledriver)'s
  `render_map(sprites: [player, *npcs], depth: 0)` draws the sprites that many
  layers from the top, one by default. rgame's `TileMapLayer.mount(slots:)`
  names a layer by index, name or path. With nothing named, it uses the first
  layer marked `above`.
- **Let the designer name the layer in Tiled.** SuperTiled2Unity reads a
  `unity:SortingLayer` property on a Tiled layer and puts that layer's tiles on
  a Unity sorting layer of that name. A player sprite on the same sorting layer
  draws among them
  ([Sorting](https://supertiled2unity.readthedocs.io/en/latest/manual/sorting.html)).
  Excalibur's `zindex` on a layer does the same with a number.
- **By hand.** Phaser orders by creation and `setDepth`, HaxeFlixel by the order
  it adds groups, libGDX by what the game draws when. bevy_ecs_tiled suggests
  listening to map events and "manually adjust[ing] the Z offset".

**Unity sorts by a name, not by a parent.** In SuperTiled2Unity's
`Custom Sort Axis` mode, tiles and sprites sort by y across a whole sorting layer,
wherever each sits in the hierarchy. The condition is that sprites and tiles
"that you want to sort dynamically are assigned the same `Sorting Layer` and
`Order in Layer` values", which its manual calls "the most common source of
errors". Godot, bevy_ecs_tiled,
YATI and rgame sort within one parent, so an actor spawned in code must join the
object layer's node to sort against the trees in it.

## What none of them gives us

- **A misspelt property goes unnoticed.** Every loader that applies properties
  by name drops or stores a name it does not know: Phaser into `data`, YATI into
  metadata, bevy_ecs_tiled not at all. None of the documentation read says an
  unknown name raises. Only bevy_ecs_tiled's exported types stop a designer
  typing one, and only in the editor.
- **A clear home for an actor spawned in code.** Each loader either leaves it to
  the game or makes the designer name a layer for it. None ties it to "the layer
  this map's actors live in".
- **One path for an object that is both a picture and a gameplay thing.** In
  Excalibur a factory replaces the default `Actor`, sprite included: "If we do a
  factor method we skip any default processing"
  ([object-layer.ts](https://github.com/excaliburjs/excalibur-tiled/blob/main/src/resource/object-layer.ts)).
  A chest drawn from its tile then draws itself.

## What this means for rgame's loader today

*(Measured.)* Three gaps against the Tiled behaviour above:

- **`draworder` is read and then dropped.** `Tiled::ObjectLayer#draw_order` is
  `:topdown` or `:index` ([map.rb:230](../../../lib/rgame/engine/tiled/map.rb#L230)).
  `TileMap::Layer` does not carry it, and nothing outside `lib/rgame/engine/tiled/`
  reads it. It maps onto `y_sort: true` and `false`.
- **A tile object does not inherit its tile's class.** `MapObject#class_name`
  comes from the object alone
  ([from_tiled.rb:154](../../../lib/rgame/engine/tile_map/from_tiled.rb#L154)),
  though the map keeps a class per tile
  ([from_tiled.rb:78](../../../lib/rgame/engine/tile_map/from_tiled.rb#L78)).
- **A class-typed property carries only the members set in the map.**
  `Tiled::Properties` reads it as a nested bag
  ([properties.rb:53](../../../lib/rgame/engine/tiled/properties.rb#L53)).
  Tiled saves only the members set on that element, and rgame reads no project
  file, so the defaults are missing. A component's own defaults could fill them
  if the Tiled types were exported from the components, as bevy_ecs_tiled does.

Templates are already resolved, the instance's properties winning
([template.rb](../../../lib/rgame/engine/tiled/template.rb)).

*(Measured.)* Of the seven maps the examples and test projects load, six have an
object layer. The one without is `examples/assets/puzzle.tmx`, which
`examples/block_puzzle` loads. In `beach_large.tmx`, `Objects` sits above `Over`, the layer marked `above`, as
in Tiled's `island.tmx`.

## Questions for the plan

1. How a property reaches a component: the bag, a name matched on every
   component, reserved names, or one Tiled class per component.
2. Whether rgame exports its components as Tiled custom types, and whether an
   unknown property raises.
3. Where an actor spawned in code goes: the object layer when the map has one,
   `slots:` when it does not, or a layer the designer names.
4. What an object with no builder becomes: nothing, or a picture for a tile
   object.
5. Whether a builder replaces the default picture, as in Excalibur, or adds to
   it.
