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
   against the `@param` tags above the class's `initialize`, constructs the node
   with its component values applied, and gives a tile object its picture.
5. **The node finds the rest in the tree.** Its room, its facts and its random
   source are systems, reached with `system!` in `_enter_tree`.

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
| `Chest` | a `Chest`, which must be a `Node2D` subclass |
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
the `def` documents it with a type Tiled can hold:

```ruby
class Chest < RGame::Engine::Node2D
  # A chest the hero opens once. It keeps its state in Facts under its fact_key.
  #
  # @param contents [String] the item inside
  # @param locked [Boolean] whether it takes a key to open
  def initialize(contents:, locked: false, **)
    super(**)
    @contents = contents
    @locked = locked
    add_component(RGame::Engine::Components::BoxCollider.new(
                    width: 14, height: 10, offset_x: -7, offset_y: -10, layer: :interactable
                  ))
  end
end

module RGame::Engine::Components
  class BoxCollider < Collider
    # @param width [Float] the box's width, in pixels
    # @param height [Float] its height
    # @param offset_x [Float] how far the box's left edge sits from the origin
    # @param offset_y [Float] how far its top edge sits from the origin
    # @param layer [Symbol] the collision layer it is found on
    def initialize(width:, height:, offset_x: 0, offset_y: 0, layer: :default)
      # ...as today
    end
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
  `width`, `height`, `input_owner`, `band` and `y_sort`), `map_object`,
  `fact_key`, and the property `fact`. The map sets the first six, and the
  builder the next three.
- **The tags come with the constructor.** A subclass without an `initialize` of
  its own uses its parent's, comment and all. `FeetCollider` has its own
  `initialize`, so only its own three tags count, not `BoxCollider`'s five.
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

For object 7, a `Chest` tile object in `map/town.tmx` with the properties
`contents: 'key'` and `collider` of class `BoxCollider` holding `width: 20.0`,
`MapBuilder` does the equivalent of:

```ruby
Chest.new(x: 184.0, y: 312.0, width: 16.0, height: 16.0, angle: 0.0,
          map_object: object, fact_key: :"map/town.tmx#7",
          contents: 'key')
# ...and while that runs, the BoxCollider Chest builds gets width: 20.0
node.add_component(Components::MapTile.new(tile: object.tile, orientation: object.orientation))
```

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

**A component's values apply while the node builds it.** Each class property
names a component class, and its members must be keywords that component's own
tags make settable. While the node's `initialize` runs, a component of that class
built by that `initialize` takes the map's values as keywords, the map's winning
over the ones the code passed:

- **A component has no writers to add.** It is built once, with its final
  values, so a `FeetCollider` derives its box and a `Particles` checks its
  limits exactly as when code builds it.
- **Only the node's own `initialize` counts.** A child node built inside it opens
  a scope of its own, so a child's `BoxCollider` never takes its parent's value.
  A component built later, in `_enter_tree`, takes nothing.
- **Every value is taken exactly once.** A class the node never builds raises,
  "Chest built no FeetCollider; object 7 in map/town.tmx sets one". A class it
  builds twice raises too, because the map cannot say which.
- **Nothing changes when no map node is building.** `Node2D.new` and
  `Component.new` forward with `(...)` and allocate nothing extra.

**The key in `Facts`** is the object's `fact` property as a Symbol when it has
one, and `:"<tilemap id>#<object id>"` otherwise. The tilemap id is the asset key
`TileWorld` was given, `'map/town.tmx'`, not the file path, which is absolute in
a game and differs between machines. `fact_key` and `map_object` are `nil` on a
node built in code.

```ruby
class Chest < RGame::Engine::Node2D
  def _enter_tree
    @facts = system!(RGame::Engine::Components::Facts)
    @state = @facts.fetch(fact_key, 'closed').to_sym
  end
end
```

## Tile objects

**Every tile object draws its tile** (decision 6). `MapBuilder` adds a
`Components::MapTile` to the node it built, or to a plain `Node2D` for a tile
object whose class is data. A node class's own drawing comes after the tile,
as any component's drawing precedes `_draw`.

```ruby
# Engine — draws the map's tile with its bottom centre on the origin
Components::MapTile.new(tile: 399, orientation: object.orientation)

# Core — the renderer grows one call, and the fake answers it too
renderer.map_tile(tilemap_id, tile, left, top, width, height, orientation, elapsed: world.elapsed)
```

- **`map_tile` forwards to the registered map**, as `tilemap` does. It draws
  through `TileMapRenderer`'s existing single-tile path, opened to a position
  and a size, so a turned tile and an animated one draw as they do in a layer.
- **The tile fills the object's box.** Tiled scales a tile object to its width
  and height, and so does `map_tile`.
- **The clock is `TileWorld#elapsed`**, handed over at draw time (hard
  constraint 3).
- **A tile object outside the view draws nothing**, through `Engine::Culling` as
  a sprite does.

## Object layers in `mount`

```ruby
slots = TileMapLayer.mount(world)   # as today; object layers now become nodes and build their objects
slots[:actors]                      # the layer marked `actors`; on a map with no mark, the slot under the first `above` layer
```

- **Each object layer is a node in its place among the layers.** It is a plain
  `Node2D`, y-sorted when `y_sort?` says so, at the layer's opacity. A hidden
  layer still builds its objects and draws none of them, as a hidden tile layer
  still blocks. See [open question 4](README.md#open-questions).
- **Objects are added in the layer's order**, which is the y-sort's tie-break.
- **`mount(y_sort:)` covers slots only.** An object layer follows the draw order
  the designer set in Tiled, where they can see it.
- **The marked layer is the `:actors` slot.** A scene that leaves `:actors` at
  its default gets that layer's node, so a hero it spawns sorts against the trees
  placed there. A map with no mark keeps today's rule.

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

## Writing Tiled's custom types *(rough)*

```ruby
RGame::Engine::MapTypes.write('examples/assets/tiled_tour/tour.tiled-project')
```

It walks the `Node2D` and `Component` subclasses whose tags make any keyword
settable, and writes a Tiled class for each: `useAs` object for a node class, `useAs`
property for a component. It replaces the classes it owns and keeps the ones the
designer wrote, such as `entrance`. Where it runs from, and what default each
member shows, are open questions [2](README.md#open-questions) and
[5](README.md#open-questions).

## What it replaces

- **`MapObjects` and `spawn_into`.** 5 scenes and 10 builder blocks move onto
  the map. `CHANGELOG.md` gets a Removed entry.
- **The slots scenes declared for objects**, `:doors` and `:platforms`, where
  the objects now build into their own layers. See
  [open question 3](README.md#open-questions).
- **`Random.new(ENV.fetch('RGAME_SEED', DEFAULT_SEED).to_i)`**, in 9 projects.

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

- **Writers on each component**, so the builder sets values after construction.
  It needs up to 29 writers, and each must re-derive what the constructor
  derived: a `FeetCollider`'s box, a `Particles`' checked limits. A writer that
  forgets one leaves a component that looks configured and is not.
- **Running `initialize` again with the map's values.** It rebuilds whatever the
  first run set up, signals included, and a component would have to remember its
  arguments.
- **The node passes component values on itself** (Q2 D). Every node class would
  repeat the same code, and the one that forgets drops the designer's value.
- **A registry per scene, or a list of classes per game** (Q3 A and B). Both are
  bookkeeping someone forgets, and a registry per scene keeps the scene deciding
  what a map may contain.
- **Matching property names on every component** (Q2 C). Rejected once already
  by the Tiled format plan: nothing checks the name, and two components with the
  same attribute both receive the value.
- **A map that adds components** (Q1 B and C). It moves what a chest is out of
  its class and into data nothing checks until the map loads.
- **The engine picking the only object layer for actors** (Q6 C). It would move
  tiled_world's actors above the canopy, because `beach_large.tmx` keeps its
  `Objects` layer on top.
- **An `Identity` for every map-built node.** `Identity`'s own comment says ids
  are the game's business. A derived key serves `Facts`, which is where a node's
  state goes, and a game may still set `fact` itself.
- **The origin at the top-left corner** (Q11 B). A tree with no collider would
  sort by its top edge.
- **A `Random` per node** (Q12 B). Seeded, every walker draws the same sequence.
  Unseeded, a driven run stops being reproducible.
- **A list of data classes** (Q10 B). It raises on a lower-case typo, at the
  price of a list the capital-letter rule does not need.
- **Resolving classes in the transform.** A `TileMap` is plain data built
  before a scene exists, and may be built in a process with none of the game's
  classes loaded. `mount` is the first point where they must be.
