# Design

## From an object in Tiled to a node in the tree

Five stages, each owned by one piece:

1. **`Tiled::Map` reads the file as written.** It learns the capsule, keeps a
   class property's class, and reads a tileset's `objectalignment`.
2. **`TileMap.from_tiled` turns it into what a game reads.** A tile object takes
   its tile's class when it has none, alignment is applied once, and an object
   layer becomes a `TileMap::ObjectLayer` that answers `y_sort?` and `actors?`.
3. **`TileMapLayer.mount` builds the tree.** An object layer becomes a node in
   its place among the layers, and each object in it goes to `MapBuilder`.
4. **`MapBuilder` builds one node.** It resolves the class, checks every property
   against the `@param` tags above the class's `initialize`, constructs the
   node, and gives a tile object its picture. It hands the node values and keeps
   the record: the node keeps only its object's id (decision 19).
5. **The node finds the rest in the tree.** Its room, its facts and its random
   source are systems, reached with `system!` in `_enter_tree`. Its
   `Components::Facts` keeps its own record in the facts database (decision
   20).

Stages 1 and 2 are pure and game-agnostic: a `TileMap` knows no game class.
Classes resolve in stage 4, when the scene mounts the map and the game's code is
loaded.

## The parse and the transform

```ruby
object = map.objects.find { it.id == 7 }
object.class_name                    # => 'Chest' — its own, or else its tile's
object.shape                         # => :capsule, for Tiled's capsule

bag = object.properties
bag.class_name                       # => nil — an object's own bag names no class
bag['collider'].class_name           # => 'BoxCollider' — a class property keeps its class
bag['collider']['width']             # => 20.0

layer = map.layer(3)                 # => a TileMap::ObjectLayer
layer.y_sort?                        # => true for Tiled's "Top Down" draw order, false for "Manual"
layer.actors?                        # => true when the layer has a bool property `actors`
map.actors_layer                     # => 3, or nil when no layer is marked
```

- **`Properties#class_name`** carries Tiled's `propertytype`. It is the one piece
  of a class value the parse used to drop.
- **`TileMap::ObjectLayer`** subclasses `Layer`, as `ImageLayer` does.
  `draworder` arrives as `y_sort?`, because the runtime view speaks none of
  Tiled's words (hard constraint 6).
- **`actors?` is read once, as `above?` is.** A mark on a layer that is not an
  object layer raises `Tiled::FormatError`, and so do marks on two layers or a
  non-bool value. There is one place spawned actors go.
- **`objectalignment` moves the corner once.** The transform turns each of its
  nine values into the object's top-left corner, as it does for Tiled's
  bottom-left default today. Nothing downstream learns the alignment.
- **Any child shape the parser does not know raises**, rather than reading as a
  rectangle. The capsule was found that way, and the next shape Tiled adds
  should be found the same way.

## Which classes build

| Tiled class | Builds |
|---|---|
| `Chest` | a `Chest`, which must be a `Node2D` subclass, resolved outward from the class of the scene that mounts the map ([open question 6](README.md#open-questions)) |
| `Town::Chest` | a `Town::Chest` |
| `entrance`, `start`, `gap`, or none | nothing: the object is data, read through `map.objects` and `object_named`. A tile object still draws its tile |
| `Chset` | raises `NameError`: no such constant |
| `Array` | raises `TypeError`: not a `Node2D` subclass |

**A class starting with a capital letter builds, and nothing else does.** Ruby
constants start with a capital, so the rule needs no list. The terrain class
`gap` stays terrain, and a tile object placed from a gap tile draws its tile and
builds nothing. Each raise names the map's tilemap id, the object's id and name,
and the class, and says the rule.

## What a map may set: the constructor's `@param` tags

A map may set a keyword of a class's `initialize` when the comment directly above
the `def` documents it with a type Tiled can hold. The sketches of game code in
this document sit inside the game's own module, where `Engine` stands for
`RGame::Engine` and `Components` for `RGame::Engine::Components`; see
[A game's own module](../../api/README.md#a-games-own-module).

```ruby
class Chest < Engine::Node2D
  # A chest the hero opens once.
  #
  # @param contents [String] the item inside
  # @param locked [Boolean] whether it takes a key to open
  def initialize(contents:, locked: false, **)
    super(**)
    @contents = contents
    @locked = locked
    add_component(Components::BoxCollider.new(
                    width: 14, height: 10, offset_x: -7, offset_y: -10, layer: :interactable
                  ))
  end
end
```

| Tag type | Tiled type | Ruby value |
|---|---|---|
| `[String]` | `string` | String |
| `[Integer]` | `int` | Integer |
| `[Float]` | `float`; an `int` is accepted | Float |
| `[Boolean]` | `bool` | `true` or `false` |
| `[Symbol]` | `string` | Symbol |
| a list of Symbols, such as `[:center, :bottom, :top_left]` | a string enum of those values | one of the Symbols |
| `[Util::Color]` | `color` | `Util::Color` |

- **The comment is read from the source.**
  `Chest.instance_method(:initialize).source_location` names the file and the
  line of the `def`. The tags are the unbroken run of comment lines directly
  above it. That is the block `spec/support/api_docs.rb` reads for
  `@api private`, and the block `tools/strip_comments.rb` keeps above a public
  method. It is read once per class, at the first build or export, and cached.
  Only YARD's `@param name [Type]` syntax is read. The YARD gem is not needed.
- **The tags are the allow-list.** A keyword with no tag cannot be set from a
  map. Neither can one tagged with a type outside the table, such as
  `@param rng [Random]`. That keeps a camera, a script or an RNG out of any map's
  reach.
- **A tag must name a keyword the `initialize` takes.** Reading one that does not
  raises, naming the class, the tag and the keywords. A spec reads the tags of
  every engine class that has any, so an engine comment cannot drift from its
  constructor unnoticed.
- **Reserved names raise too**: `Node2D`'s own keywords (`x`, `y`, `z`, `angle`,
  `width`, `height`, `input_owner`, `band`, `y_sort` and `map_object_id`), and
  `route` and `name`. The object's box sets `x`, `y`, `angle`, `width` and
  `height`, and the builder sets `map_object_id`, `route` and `name`.
- **The tags come with the constructor.** A subclass without an `initialize` of
  its own, such as `class LockedChest < Chest; end`, uses its parent's, comment
  and all. A subclass with its own `initialize` uses only its own tags.
- **A class needs its source.** A class defined by `eval`, or in C, has no source
  location, and building one from a map raises, naming it.
- **The pre-commit hook keeps the block.** `tools/strip_comments.rb` treats a
  `def initialize` in a public section as public, which was checked on a probe
  file. Step 3 adds that case to `spec/tools/comment_stripper_spec.rb`, so a
  change to the stripper cannot delete a class's settings without a failing
  spec.
- **Tiled's `file` type is not mapped.** Tiled resolves a file property against
  the map's directory, while a game names an asset by its key under the media
  root. So an asset key is a `[String]`.

## Building one node

For object 7, a `Chest` tile object in `map/town.tmx` with the property
`contents: 'key'`, `MapBuilder` does the equivalent of:

```ruby
Chest.new(x: 184.0, y: 312.0, width: 16.0, height: 16.0, angle: 0.0,
          map_object_id: 7, contents: 'key')
node.add_component(Components::MapTile.new(tile: object.tile, orientation: object.orientation))
```

**The builder hands the node values and keeps the record** (decision 19). Once a
node is built, how it was built does not matter, except for its object's id:

| Field of the `MapObject` | What the builder does with it |
|---|---|
| `class_name` | picks the class |
| `layer` | picks the parent |
| `x`, `y`, `width`, `height`, `rotation` | `Node2D`'s keywords `x:`, `y:`, `angle:`, `width:` and `height:` |
| `properties` | the class's tagged keywords |
| `tile`, `orientation` | a `MapTile` |
| `visible` | opacity 0 when hidden |
| `shape`, `points` | `route:`, an `Engine::Path` from `Path.from_object`, for a polyline or a polygon |
| `name` | `name:`, a String |
| `id` | `map_object_id:`, on every node it builds |

`route:` and `name:` go only to a class whose `initialize` names them. Every
class forwards `**` to `Node2D`, which takes neither. A class that requires
`route:` raises when built from another shape, naming the object.

**The node's own settings are keywords of its constructor.** Each flat property
must be a keyword the class's tags make settable, of the tagged type, and
arrives as the Ruby value the table gives. Anything else raises, listing the
keywords the class's tags make settable.

**The origin is the bottom centre of the object's box** (decision 10), turned
with the object:

```
origin_x = x + (width / 2) * cos(angle) - height * sin(angle)
origin_y = y + (width / 2) * sin(angle) + height * cos(angle)
```

with `angle` in radians and `(x, y)` the `MapObject`'s top-left corner. A point
object's origin is its point. A polygon or polyline has no box in Tiled, so its
origin is its own `(x, y)` and its points stay relative to it.

**A component's values come through the node.** A node that lets a designer
tune one of its components takes the value as a tagged keyword of its own, and
passes it on together with what it derives from it:

```ruby
class Crate < Engine::Node2D
  # @param size [Float] the crate's side, in pixels
  def initialize(size: 16.0, **)
    super(**)
    add_component(Components::BoxCollider.new(
                    width: size, height: size, offset_x: -size / 2, offset_y: -size, layer: :crate
                  ))
  end
end
```

The map never sets a component's keywords itself (decision 3). An override of
`width` would leave behind the offsets the code derived from it, and no node
class built from a map today wants one. `docs/plans/possible-todos.md` keeps the
design this plan drafted for it.

**A node keeps its facts in the `FactsDatabase` through `Components::Facts`**
(decision 20), one record of named fields under one key. Its key is `key:` when
the node passes one, and otherwise
`:"<tilemap id>#<object id>"`, derived at the component's first `_attach`. The
tilemap id is the asset key `TileWorld` was given, `'map/town.tmx'`, not the
file path, which is absolute in a game and differs between machines.
`map_object_id` is `nil` on a node built in code, which passes `key:` instead.

```ruby
class Chest < Engine::Node2D
  def initialize(**)
    super
    @facts = add_component(Components::Facts.new(state: 'closed'))
  end

  def _enter_tree = @state = @facts[:state].to_sym

  def open = @facts[:state] = 'open'
end
```

A class that lets a designer name the key tags a keyword of its own, such as
`@param fact [Symbol]`, and passes it on as `key:`. The property `fact` is no
longer special.

## Tile objects

**Every tile object draws its tile** (decision 6). `MapBuilder` adds a
`Components::MapTile` to the node it built, or to a plain `Node2D` for a tile
object whose class is data. The tile draws under everything else its node
draws, at the lowest `z:` in the node's slot. Components draw in the order they
were added, and the `MapTile` comes after the class's own.

```ruby
# Engine — draws the map's tile with its bottom centre on the origin
Components::MapTile.new(tile: 399, orientation: object.orientation)

# Core — the renderer grows one call, and the fake answers it too
renderer.map_tile(tilemap_id, tile, left, top, width, height, orientation, elapsed: world.elapsed, z: Z_MIN)
```

- **`map_tile` forwards to the registered map**, as `tilemap` does. It draws
  through `TileMapRenderer`'s existing single-tile path, opened to a position
  and a size, so a turned tile and an animated one draw as they do in a layer.
- **The tile fills the object's box.** Tiled scales a tile object to its width
  and height, and so does `map_tile`. A tileset whose `fillmode` preserves the
  tile's aspect, or whose `tilerendersize` is the grid, raises at load instead.
- **The clock is `TileWorld#elapsed`**, handed over at draw time (hard
  constraint 3).
- **A tile object outside the view draws nothing**, through `Engine::Culling` as
  a sprite does.

## Object layers in `mount`

```ruby
places = TileMapLayer.mount(view)   # object layers become nodes and build their objects
places[:actors]                     # the layer marked `actors`; on a map with no mark, a node under the first `above` layer
places['doors']                     # the object layer named 'doors', for what a scene spawns itself
```

- **Each object layer is a node in its place among the layers.** It is a plain
  `Node2D`, y-sorted when `y_sort?` says so, at the layer's opacity. A hidden
  layer still builds its objects and draws none of them, as a hidden tile layer
  still blocks, and so does a hidden object (decision 16).
- **Objects are added in the layer's order**, which is the y-sort's tie-break.
- **An object layer replaces a named slot** (decision 17). A scene adds what it
  spawns to `places[name]`, and it takes on the layer's draw order, opacity and
  visibility. An empty object layer in Tiled marks a place in the layer order.
- **`mount(y_sort:)` covers only the actors' place on a map with no mark.** An
  object layer follows the draw order the designer set in Tiled, where they can
  see it.
- **The marked layer is `places[:actors]`**, so a hero a scene spawns sorts
  against the trees placed there. A map with no mark keeps today's place.
- **`mount` builds once.** A second `mount` over the same `TileWorld` raises.

## The random source

```ruby
module RGame::Engine::Components
  class RandomSource < Engine::Component
    sealed_reader :seed               # RandomSource.new(seed: 42) keeps a Random seeded with it

    def rand(...) = @rgame_random.rand(...)
  end
end

RGame::Game.new(seed: 0xC0)   # RGAME_SEED wins when it is set; with neither, a fresh seed
game.random_source            # => the root's RandomSource, as game.facts is the root's Facts
node.system!(RGame::Engine::Components::RandomSource).rand(3)
```

- **It is not called `Random`.** Inside `Components`, that name would shadow
  Ruby's `Random` for every component that writes `Random.new`.
- **`WanderController` and `Particles` default to it.** Their `rng:` defaults to
  `nil` and resolves to the root's source at `_attach`. With no source on the
  root, they raise naming it, rather than drawing from an unseeded `Random` as
  they do today.
- **`RGAME_SEED` is read in one place**, `RGame::Game`, instead of in 9 projects.

## Writing Tiled's custom types

```ruby
module MyGame
  class Chest < Engine::Node2D
    # A chest the hero opens once.
    #
    # @placeable
    # @param contents [String] the item inside
    # @param locked [Boolean] whether it takes a key to open
    # @param lid [:flat, :round] the shape of its lid
    def initialize(contents:, locked: false, lid: :flat, **)
```

```ruby
report = RGame::Engine::MapTypes.new(MyGame).write('assets/my_game.tiled-project')
puts report
# assets/my_game.tiled-project
#   added      Chest   contents, lid, locked
#   unchanged  Door    entrance, party, to
#   removed    Barrel
# Tiled shows the change once the project is reopened.
# A class is written when the comment above its initialize carries @placeable.
```

**A class the designer may place carries `@placeable`** (decision 21). The
export walks the game's module, and every module and class defined under it,
and writes each placeable `Node2D` class. The tag is read as the `@param` tags
are: from the comment above the `initialize` the class uses. Nothing else reads
it. A map still builds a class without it (hard constraint 7).

**Each placeable class becomes a Tiled class**, named by its path under the
module, such as `Door` or `Town::Chest`. That is a name `MapBuilder` resolves
from any scene in the module. It is used as an object's class and a tile's,
since a tile object takes its tile's class. Its members are the keywords its
tags make settable:

| Tag | Member |
|---|---|
| `[String]`, `[Symbol]` | `string` |
| `[Integer]` | `int` |
| `[Float]` | `float` |
| `[Boolean]` | `bool` |
| `[Util::Color]` | `color`, written `#aarrggbb` as Tiled writes it |
| `[:flat, :round]` | `string`, of a string enum `Chest.lid` holding `flat` and `round` |

`name:` and `route:` are no members, since the builder fills them from the
object.

**A member shows its keyword's default** (decision 23). Tiled saves no member
the designer leaves at its default, so a map then gives the game Ruby's default.
The export shows the same value:

- A literal default shows itself: `locked: false` shows `false`.
- A constant shows its value, looked up outward from the class as `MapBuilder`
  resolves a class name.
- A required keyword shows Tiled's empty value for its type. A map that leaves
  it unset raises at load, as it does today.
- `nil` shows as empty for a String, a Symbol and a colour.
- Anything else raises at export, naming the class, the keyword and what to
  write instead. That covers a default the export cannot read, a default of
  another type than the tag's, and `nil` for any other type.

Prism reads the defaults, and loads only when the export runs. It takes about
35 ms to load, against about 120 ms for `require 'rgame'`, so loading it with
the engine would slow every game's start.

**The export owns every type whose name starts with a capital letter**
(decision 22). It replaces those the game defines, and keeps the id, colour and
fill Tiled holds for each. It removes the other capitalised types, and adds new
ones after the rest. The designer's lower-case types, such as `entrance`, stay
as they are, and so does every other key of the project.

**It writes the file as Tiled writes it.** Keys and members are sorted, the
indent is four spaces, an empty array spans two lines, and a float with no
fraction is written bare. A project in that format comes back byte for byte when
Tiled saves it again. A project that already holds the types is left untouched.

**Nothing at load reads the project** (hard constraint 7). The project only
helps the designer pick classes and fill in members. A map typed by hand, a map
beside a stale project, and a map with no project at all build the same.

**A generated project writes its types with `bundle exec rake tiled`**
(decision 24). `spec/tiled_project_spec.rb` fails when the project no longer
holds what the task writes, and names the command. `rgame new --no-tiled` leaves
out the project and the spec.

## What it replaces

- **`MapObjects` and `spawn_into`.** 5 scenes and 10 builder blocks move onto
  the map. `MapObjects` never shipped, so its Unreleased `CHANGELOG.md` entry
  goes rather than gaining a Removed one.
- **`mount`'s named slots**, which object layers replace (decision 17). After
  step 7 no project passes a slot other than `:actors`.
- **`Random.new(ENV.fetch('RGAME_SEED', DEFAULT_SEED).to_i)`**, in 9 projects.
- **`Node2D`'s `map_object:` and `fact_key:`**, which step 3 added. The id stays
  as `map_object_id`, and `Components::Facts` makes the key.
- **The `facts:` that adventure's `Chest`, `Lever` and `Crate` take from their
  room**, and the keys `Crate` derives by hand.

## Considered and rejected

- **A `map_settings` declaration** on each class, listing its settable keywords
  and their types. An earlier draft of this plan used one. It says what the
  constructor's documentation says, in a second place that must agree with the
  `initialize` below it. Every constructor change then has two lines to change,
  and the second is the one that gets forgotten.
- **The YARD gem.** It would be a second runtime dependency, which CLAUDE.md
  treats as a deliberate decision, to read one tag.
- **Types inferred from default values.** Prism can read `locked: false` from the
  signature. But required keywords such as `width:` and `contents:` have no
  default, a default like `-Math::PI / 2` has no literal type, and changing a
  default's literal would quietly change an exported type.
- **Setting a component's values from the map** (Q2 A). A class-typed property
  named after a component would set its keywords while the node builds it. No
  node class built from a map today sets a component value per object. In 4 of
  the 7, the code derives several of a component's values from one, which an
  override would bypass without a word. The drafted design, and why its
  alternatives failed, moved to `docs/plans/possible-todos.md`.
- **A registry per scene, or a list of classes per game** (Q3 A and B). Both are
  bookkeeping someone forgets, and a registry per scene keeps the scene deciding
  what a map may contain.
- **A map that adds components** (Q1 B and C). It moves what a chest is out of
  its class and into data nothing checks until the map loads.
- **The engine picking the only object layer for actors** (Q6 C). It would move
  tiled_world's actors above the canopy, because `beach_large.tmx` keeps its
  `Objects` layer on top.
- **An `Identity` for every map-built node** (step 5's Q1 C). `Identity`'s own
  comment says ids are the game's business, and `save_load_ids` gives its sheep
  Integer ids, which cannot key a fact. A derived key serves `Facts`, which is
  where a node's state goes, and a class may still take a designer's key.
- **The object's record on every node** (`map_object:`, step 5's Q1). Nothing
  read it once a node was built. The three classes that would read it wanted a
  route or a name, while building, and the builder now passes those.
- **The id only for a class that asks** (step 5's Q1 B). `Node2D` would hold
  nothing of the map, but a class adding a `Facts` would have to remember to
  take the id and pass it on.
- **A component holding only the key** (step 5's Q2 B). Every node would repeat
  the lookup in the database, and `Crate` would still build its three keys by
  hand.
- **One component per value, with a `part:` each** (what step 5 shipped). A
  crate needed three, each in a slot of its own, for values that are always
  there together. One record of named fields replaced them.
- **Keys that nest in their names**, such as `:"crate.x"`, rather than a record.
  RPG Maker keys its self switches `"3,7,A"`, and Ink its visit counts by path.
  A record keeps a node's fields together in the save, and lets the database
  hand out the whole record.
- **The origin at the top-left corner** (Q11 B). A tree with no collider would
  sort by its top edge.
- **A `Random` per node** (Q12 B). Seeded, every walker draws the same sequence.
  Unseeded, a driven run stops being reproducible.
- **A list of data classes** (Q10 B). It raises on a lower-case typo, at the
  price of a list the capital-letter rule does not need.
- **Resolving classes in the transform.** A `TileMap` is plain data built
  before a scene exists, and may be built in a process with none of the game's
  classes loaded. `mount` is the first point where they must be.
- **Exporting every class with a `@param` tag** (step 8's Q1 B). A tag must
  name a keyword a map sets. So a class with nothing to set, such as `Flag`,
  `Crate` or `Walker`, could never be exported.
- **Exporting every class a map can build** (step 8's Q1 A). The projects hold
  58 such classes, and the maps build 9. The designer would pick from scenes,
  rooms and heroes.
- **A marker module for placeable classes.** A tag keeps everything a map reads
  in the one comment `MapSettings` already reads.
- **The builder refusing a class without `@placeable`.** Hard constraint 7: a
  map typed by hand builds whatever fits, whether or not any export has run.
- **`rgame tiled-export`** (step 8's Q4). A command in the gem would reach games
  made before step 8. But it would fix the project's layout inside the gem. It
  would also require `rgame` from a CLI that requires only the standard library,
  and need `bundle exec` to load the game against its own engine.
- **`RGame::Game` writing the types when the game starts.** `RGame::Game.new`
  opens the window, and a shipped game would write into its own assets. Tiled
  would not see the file until the project is reopened.
- **One Tiled project for `examples/assets/`** (step 8's Q5 B). The export would
  merge several games' modules and refuse a class two of them define
  differently. No spec can load an example's classes to check the file.
