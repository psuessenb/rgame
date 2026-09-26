# Object layers

**Status: steps 0–5 are implemented.** Steps 6 and 7 of
[the roadmap](04-roadmap.md) are detailed. Step 5 was inserted after step 4
landed, and the steps after it moved up by one. Steps 8 and 9 are rough and get
re-planned as the steps before them land. Step 10 folds the plan back and
deletes it.

## The request

In the user's words:

> I think handling the object layer entirely in the scene is the wrong approach.
> It seems to me ideally the object layer gets parsed with the map, gets a layer
> in the map and in that layer those objects get created as nodes. The object
> properties decide what class those nodes have, and which properties. This would
> require some kind of builder mechanism, and a way to set properties on a node
> _when those properties are actually properties of a component_.
>
> Additional hurdle I see: Where are actors placed on maps that come without an
> object layer?

## Goal

A designer places a chest, a door or a tree in Tiled, and the game gets a node
for it, in the layer it was placed in, set up by the properties the designer
gave it. A scene that shows the map writes no line for it.

## Verdict

**`TileMapLayer.mount` builds each object layer as a node, and each object in it
as an instance of the Ruby class its Tiled class names.** The class `Chest`
builds a `Chest`. A class starting with a lower-case letter, or none, is data and
builds nothing, except that a tile object always draws its tile. A node's own
properties arrive as keywords of its constructor, and a node that lets a
designer tune one of its components takes the value as its own keyword and
passes it on. What a map may set is what the `@param` tags above a class's
`initialize` document, with a type Tiled can hold. It is checked at
load, and written out as Tiled custom types, so the designer picks from the
game's real names.

**An object layer is a y-sorted node in the place Tiled draws it**, so a tree
placed as a tile object sorts against the actors in its layer. The layer a
designer marks `actors` is where `mount(view)[:actors]` puts the heroes that
code spawns. A map without the mark keeps today's place for them. An object
layer also marks a place for anything else a scene spawns, which replaces
`mount`'s named slots.

**Around that:**

- The parser fills four gaps: the capsule, a class property's class, a tile
  object's inherited class, and `objectalignment`.
- The renderer draws one tile.
- A node keeps its object's id and nothing else of it, and
  `Components::Fact` keeps a node's state in `Facts`.
- The root gains a seeded random source that map-built nodes find without being
  handed it.
- Every map, node and scene that builds from objects today moves onto the new
  path, and `MapObjects` goes.

## Hard constraints

1. **The engine layer may not name `RGame::Core`.** The single-tile draw is a
   renderer method, called by name. The fake answers it too, and `a renderer`
   checks both.
2. **A per-frame path allocates nothing.** Every tile object draws every frame.
   `rake drive:allocations` decides.
3. **`draw` renders state.** A tile object's animation reads `TileWorld#elapsed`,
   not a clock.
4. **`require "rgame"` loads no graphics.** Building nodes from a map is Engine
   work, specced headless.
5. **Every driven project enters the same scenes, plays the same sounds, and
   draws the same things at the same screen positions**, except where a step
   names what moves and why.
6. **The runtime view speaks none of Tiled's words.** `draworder` arrives as
   `y_sort?`, `propertytype` as `class_name`, and a gid as a tile id, as the
   Tiled format plan's decision 12 set out.

## Decisions already taken

Settled in conversation, in two question rounds, in a third before steps 4, 6
and 7 were re-planned, and in a fourth before step 5 was inserted. Not reopened
inside this plan.

1. **The loader builds, not the scene.** An object layer becomes a node in the
   map, and its objects become nodes inside it. Scenes stop calling `spawn_into`.
2. **An object's class names a node class, and the map only configures it**
   (Q1). The node class decides which components it has.
3. **The map sets a node's own keywords, never a component's.** Q2 chose one
   class-typed property per component, and review took it out of the plan. None
   of the 7 node classes built from maps sets a component value per object. In
   4 of them, the code derives several component values from one, which an
   override would bypass without a word. A node that lets a designer tune a
   component takes the value itself and passes it on. Setting a component's
   values from the map waits in `docs/plans/possible-todos.md`.
4. **The Tiled class is the Ruby constant's name, resolved at load** (Q3). It
   must name a `Node2D` subclass. There is no registry and no list. Which module
   the name resolves in is [open question 6](#open-questions). A map-built
   node finds what else it needs in the tree, such as `Scene::Rooms` or the
   random source.
5. **A class starting with a capital letter builds a node, and any other class
   is data** (Q10). `entrance`, `start` and the terrain class `gap` stay data. A
   capitalised class that names no `Node2D` subclass raises (Q4).
6. **Every tile object draws its tile** (Q5). A data tile object becomes a node
   that draws it. A node class's node draws it too, under whatever it draws
   itself.
7. **The designer marks where spawned actors go** (Q6). A bool property `actors`
   on one object layer, read once as `above` is. `slots[:actors]` is that
   layer's node, and a map with no mark behaves as today.
8. **rgame writes Tiled's custom types** (Q7), after the load-time check lands
   in the same plan. The research found no Tiled loader that raises on an
   unknown property.
9. ~~**A map-built node's key in `Facts`** is its object's `fact` property when
   set, and `:"<tilemap id>#<object id>"` otherwise (Q8).~~ **Amended by
   [decision 20](#decisions-already-taken).** The default key stays
   `:"<tilemap id>#<object id>"`, now as `Components::Fact`'s rule. A designer's
   `fact` reaches it only through a class that takes one. The tilemap id is the
   asset key, because the file path is absolute in a game.
10. **A map-built node's origin is the bottom centre of its object's box**, for
    every shape, and a point object's origin is the point (Q11). Rotation turns
    about it.
11. **A random source on the root, seeded from `RGAME_SEED` when it is set**
    (Q12). Every example and test project that seeds its own `Random` moves onto
    it in the step that adds it.
12. **`tour.tmx` stays the format checklist, and a second small map is the
    level the example plays** (Q9). Authoring continues on
    `build-step-8-tiled-map`.
13. **A capsule reads as `:capsule`**, and any shape the parser does not know
    raises.
14. **What a map may set is read from the `@param` tags above `initialize`**, not
    declared a second time. A keyword is settable when its tag gives a type
    Tiled can hold. The comment is found through `source_location`, and the
    pre-commit hook keeps it. An earlier draft declared the same thing with
    `map_settings`, and the conversation rejected the second list.
15. **The two games with rooms get a town map of their own** (re-plan Q1). Seven
    scenes mount `town.tmx`, and five of them define no `Door`, so a `Door` in
    it would raise in each. `town_with_gate.tmx` carries the gate, and a spec
    keeps its tile layers equal to `town.tmx`'s. A `mount(build: false)` was
    rejected: five teaching examples would each carry a keyword that exists
    because another example shares their map.
16. **A hidden object layer, and a hidden object, build and draw nothing**
    (re-plan Q2). Their nodes get opacity 0, and still update and collide, as a
    hidden tile layer still blocks. That is what Tiled shows. A hidden layer
    marked `actors` raises at load. Building nothing was rejected, since the
    same checkbox would then mean different things for two kinds of layer.
17. **Object layers replace `mount`'s named slots** (re-plan Q3). A scene adds
    what it spawns to an object layer's node, found by the layer's name or path,
    and an empty object layer marks a place the way a named slot did. A child
    takes on its layer's draw order, opacity and visibility, and sorts with the
    objects built there. `places[:actors]` stays: the marked layer, or today's
    place on a map with no mark. After step 7 no project passes a slot other
    than `:actors`, and `slots:` never shipped.
18. **A raft's size is `deck_width` and `deck_height`** (re-plan Q4). A raft is
    a polyline or a polygon, its route, whose box is 0×0, and step 3 reserves
    `width` and `height` for the box. Letting a property set the box for a shape
    without one was rejected: a size would have two sources.
19. **A node keeps its object's id, and nothing else of it** (step 5's Q1). In
    the user's words, once a node is built "it shouldn't matter _how_ it was
    constructed", apart from the id. So the builder turns every field of a
    `MapObject` into a keyword, a component or a place in the tree, and keeps the
    record. A polyline's or a polygon's route arrives as `route:`, and the name
    as `name:`, each only in a class whose `initialize` names it.
    `Node2D#map_object_id` is the one field every node keeps, `nil` on a node
    built in code. `map_object:` on every node was rejected: nothing read it
    once a node was built, and the three classes that would read it read it
    while building. Also rejected: passing the id only to a class that asks,
    which each class would have to remember, and an `Identity` the builder adds
    to every node. `object_id` is Ruby's own, and redefining it warns.
20. **A node keeps its state in `Facts` through `Components::Fact`** (step 5's
    Q2 and Q3). In the user's words: "Giving _every_ node a facts key because
    _some_ nodes might need it is bad design. That's what components are for."
    The key is `key:` when the node passes one, and otherwise
    `:"<tilemap id>#<object id>"`. A node keeping several values gives each
    `Fact` a `part:`. The property `fact` becomes a keyword like any other, which
    a class tags and passes on as `key:`, as decision 3 has it for any value a
    component takes. Adventure's `Chest`, `Lever` and `Crate` move onto it in
    step 5. A component holding only the key was rejected: every node would
    repeat the lookup in `Facts`, and `Crate` would still build its keys by hand.

## What was measured before planning

Taken at `abb91ad`, and on `origin/build-step-8-tiled-map` for `tour.tmx`.
[01-current-state.md](01-current-state.md) has the lists behind each number.

| | |
|---|---|
| `rake spec` | 4245 examples, 0 failures, 36 s |
| Scenes calling `TileMapLayer.mount` | 13 |
| Scenes building nodes from objects | 5, with 10 builder blocks; 6 close over scene state |
| Node classes built from maps | 7: `Door` ×2, `Raft` ×2, `Flag`, `Crate`, `Walker`; `Warp` ×2 to come |
| Objects whose class becomes a Ruby class | 13, in 4 maps |
| Objects of a data class | 8: `entrance` ×7, `start` ×1 |
| Maps with a terrain tile class | 3, all `gap` |
| Map-built node classes that set a component value per object | 0 of 7 |
| Map-built node classes that derive component values from one they take | 4 of 7 |
| Projects seeding their own `Random` from `RGAME_SEED` | 9 |
| Engine components defaulting to an unseeded `Random` | 2: `Particles`, `WanderController` |
| Silent gaps in the parse and the transform | 6 |
| `tour.tmx` requirements marked done | 10 of 19 |
| `@param` tags under `lib/` | 0; the tags are a new convention, needed only on constructors a map builds |

## What this plan does not deliver

- **A map adding components a node class lacks.** See decision 2.
- **A map setting a component's values directly.** See decision 3, and
  `docs/plans/possible-todos.md`.
- **Lists in map settings.** Tiled has no list type, so
  `blocked_by: [:tiles, :actors]` stays in code. A flags enum could carry it
  later.
- **Restoring state beyond `Facts`.** A node that keeps state writes it to
  `Facts` through a `Components::Fact`. The engine restores nothing else.
- **Tiles in a tile layer sorting with actors.** That stays in
  `docs/plans/possible-todos.md`.
- **Object references.** Tiled's `object` property type still arrives as an
  Integer, not a node.
- **Reading the designer's own `.tiled-project`.** Defaults come from Ruby.
- **A tileset that preserves its tiles' aspect, or draws them at the grid's
  size.** Step 4 refuses `fillmode="preserve-aspect-fit"` and
  `tilerendersize="grid"` rather than drawing them. No map uses either.
- **A turned object's collider turning with it.** A `BoxCollider` stays
  axis-aligned in the world, as step 3 found, so a map-built node on a turned
  object collides as if unturned.

## Open questions

1. ~~**Are map settings inherited?**~~ **Settled by decision 14 — with the
   constructor.** A subclass without an `initialize` of its own uses its
   parent's, comment and all, and one with its own uses only its own tags. See
   [the design](03-design.md#what-a-map-may-set-the-constructors-param-tags).
2. **Where does the export run?** `exe/rgame` may not require `rgame`, so it
   cannot load a game's classes. A rake task in the generated project, or a
   method on `RGame::Game`, are the candidates. *Waits on step 8's re-plan.*
3. ~~**Do `mount`'s other named slots survive?**~~ **Settled in the re-plan —
   no.** After step 7 no project passes a slot other than `:actors`. Object
   layers take their place. See decision 17.
4. ~~**Does a hidden object layer build its objects?**~~ **Settled in the
   re-plan — yes, and draws none of them.** So does a hidden object. See
   decision 16.
5. **What default does the export show for a member?** Ruby cannot report a
   keyword's default. Prism, a default gem, can read a literal one from the
   signature, such as `locked: false`. A computed default, such as
   `-Math::PI / 2`, would show as unset. *Waits on step 8's re-plan.*
6. ~~**Which module does a Tiled class resolve in?**~~ **Settled before step 3
   — A.** `MapBuilder.new(tilemap_id:, scope:)` resolves a name in each module
   of the scope's name, innermost first, then in what the scope inherits and at
   the top level. Step 6's `mount` passes the class of the node `TileWorld` is
   attached to. Every example and test project keeps its classes in a module of its own, as
   [A game's own module](../../api/README.md#a-games-own-module) recommends, so
   a map's `Door` names no top-level constant. `garden.tmx` and `town.tmx` serve
   both `examples/doors` and `test_projects/adventure`, and each game has a `Door`
   of its own: `DoorsExample::Door` and `Adventure::Door`.
   - **A — outward from the module of the scene that mounts the map**
     *(recommended)*. A map mounted by `Adventure::Town` resolves `Door` as Ruby
     resolves it inside that class: `Adventure::Town::Door`, then
     `Adventure::Door`, then `::Door`. A map names no module, one map serves
     both games, and nothing is configured. `MapBuilder.new` takes the class of
     the node `TileWorld` is attached to, beside `tilemap_id:`, and step 6's
     `mount` passes it.
   - **B — the map names the module**, `Adventure::Door`. Explicit, but a map
     two games share can serve only one of them, and renaming the module breaks
     every map.
   - **C — `RGame::Game.new(namespace: Adventure)`.** One place, but a game that
     leaves it out gets a `NameError` for a class it defined, and a game whose
     classes span several modules still needs B's spelling.

## Reading order

| | |
|---|---|
| [01-current-state.md](01-current-state.md) | what rgame does with an object layer today, what the maps hold, and what already resembles this |
| [02-prior-art.md](02-prior-art.md) | what Tiled intends an object layer for, and how eleven engines and loaders build from one |
| [03-design.md](03-design.md) | the design, and what was rejected |
| [04-roadmap.md](04-roadmap.md) | the implementation order |
| [map-requirements.md](map-requirements.md) | what `tour.tmx` must contain, and how the check reports a gap |
