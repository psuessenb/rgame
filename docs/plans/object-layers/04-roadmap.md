# Roadmap

**Steps 0–2 are implemented.** Step 3 is detailed. Steps 4–8 are rough and get
re-planned once the steps before them land.

## Dependency shape

```
0 tour.tmx requirements ───────────────────────────────────────────────────────────┐  authoring runs in parallel
                                                                                   │
1 parse + transform ─→ 3 map settings + builder ─┐                                 │
                       4 one tile drawn ─────────┴─→ 5 mount builds ─┐             │
2 random source ─────────────────────────────────────────────────────┴─→ 6 migrate ─→ 7 export ─→ 8 checked + played ─→ 9 fold back
```

Steps 1, 2 and 4 depend on nothing in this plan and can land in any order. Step 3
needs step 1, because the class it resolves may come from the object's tile. Step 6 needs step 2, because a `Walker` built from a map finds its
random source in the tree. Step 8 needs step 7: the level's designer picks
classes from the exported types, rather than typing them.

## The invariant every step preserves

> **Every driven project enters the same scenes, plays the same sounds, and
> draws the same things at the same screen positions**, except where a step names
> what moves and why.

A report cannot match byte for byte across a step that moves a node's origin,
because it records each draw in local coordinates (see
[verify](../../../.claude/skills/verify/SKILL.md)). Steps 5 and 6 move origins,
so they compare where each draw lands on screen.

And the standing one from the Tiled format plan:
`spec/example_assets_spec.rb` still parses `town.tmx` to the same grid.

## What lands early, if the plan is abandoned

| Step | Defect it closes |
|---|---|
| 1 | A capsule reads as a rectangle; a tile object loses its tile's class; `objectalignment` places objects where Tiled does not |
| 2 | `Particles` and `WanderController` draw from an unseeded `Random`; 9 projects each read `RGAME_SEED` themselves |
| 4 | Nothing can draw one tile of a map outside a tile layer |

Step 3 has no caller until step 5, so it lands for step 5 rather than alone.

---

## Step 0 — the requirements for `tour.tmx`

Authoring is half done, and step 1 changes what the parser reads. So the
requirements settle first, and you keep authoring against them while steps 1–7
are built. The level map gets its own requirements in step 8, once the exported
types exist to author it with.

### Shape

Changes to [map-requirements.md](map-requirements.md):

- **Carry over the done marks.** R1, R2, R4, R5, R6, R8, R9, R11, R12 and R15,
  as the authoring branch marks them.
- **R15 names the capsule** among the shapes.
- **R13's check reads the class names** of the class property and of its class
  member, now that `Properties#class_name` keeps them.
- **R17 stays at 64×48.** The map is 40×40, and 640 pixels is no wider than the
  window, so the example would have nowhere to scroll sideways. **Map › Resize
  Map…** in Tiled.
- **R19's check compares tile and image layers only.** Object layers stay hidden
  in the export, because Tiled's export draws shapes that rgame does not. Tile
  objects are checked where they are played, in the level.
- **`.tiled-session` goes into `.gitignore`.** The ground rules said to leave it
  out, and the branch commits one. An ignore entry replaces the rule.

New requirements, each with what to do in Tiled, why, and what the check reports:

| | Requirement | For step |
|---|---|---|
| R20 | A tile object with no class of its own, placed from a tile whose class is set in its tileset | 1b: a tile object takes its tile's class |
| R21 | A tileset whose object alignment is not *Unspecified*, with a tile object placed from it | 1b: `objectalignment` |
| R22 | Two object layers, one drawn *Top Down* and one *Manual* | 1c: `y_sort?` |
| R23 | One object layer with a bool property `actors` set to `true` | 1c: `actors?` |

Use lower-case classes in `tour.tmx`, such as `tree`. The format checklist then
builds nothing when a scene mounts it.

### Verify

`map-requirements.md` lists R1–R23, marks the ten done, and each new
requirement says what the check reports when it is missing.
`git check-ignore examples/assets/tiled_tour/tour.tiled-session` succeeds.

**Landed.** One commit on `tour-map-requirements`, as the step has no
sub-steps. `map-requirements.md` has 23 requirement headings, a table marking
the ten done, and a line saying what the check reports under each of R20–R23.
`git check-ignore` matches the session against `.gitignore:59`, and
`tour.tiled-project` stays tracked. `rake spec` 4245 examples, 0 failures, as
before: the step changes no code.

Where the sketch was wrong, or said too little:

- **R17's reason was stale.** The sketch kept 64×48 so the example could
  scroll sideways, but decision 12 has the example play the level, not
  `tour.tmx`. The size stays, for two other reasons. R16 needs both sides a
  multiple of 16, and 40 is not one. And R19's check then draws the map in more
  than one view, where the renderer culls animated tiles and repeated image
  layers.
- **The capsule needs Tiled 1.12.** The ground rule said 1.10 or later. Tiled's
  manual marks **Insert Capsule** "New in Tiled 1.12", so the rule now says
  1.12. The branch's map was saved by 1.12.2.
- **The done marks moved into a table.** The branch marks a heading
  `### R1 (done)`, which changes its anchor, and R1, R12 and R15 are linked from
  other requirements.
- **R20 asks for a second tile object**, with a class of its own. The sketch
  asked only for one that inherits. Step 1's rule 5 says the object's own class
  wins, and only an override shows which side won, as R18 does for templates.
- **R21 rules out *Bottom Left* as well**, which reads the same as
  *Unspecified*, and asks for a rotated object, since Tiled turns an object
  about the point its alignment names. R23 puts the mark on R22's *Top Down*
  layer.
- **The lower-case rule covers every class**, custom types included, rather
  than objects alone. One rule with no exceptions is easier to follow while
  authoring.
- **The ignore entry does not untrack the branch's session.**
  `build-step-8-tiled-map` committed one, and needs
  `git rm --cached examples/assets/tiled_tour/tour.tiled-session` once.
- **A game made by `rgame new` would still commit its session.** The generated
  `.gitignore` has no entry. Step 7 decides the generated project's Tiled
  workflow, so the question moved there.

Found on the authoring branch while checking the marks, and left for the
author:

- **R10 and R14 look met, and are not marked.** The map has an image layer
  with an offset and one with Repeat X. Object 1's `long string` spans three
  lines.
- **The embedded `dungeon` tileset slices a spaced sheet as if it were
  packed.** `dungeon.png` is 203×186 pixels, which is 12×11 tiles with 1 pixel
  between them, and the tileset sets no spacing. So tiles 36–38 on the map are
  cut up to 3 pixels off, in Tiled as well. Setting the spacing to 1 fixes it.
  With a margin added, it would also answer R3.

---

## Step 1 — the parse and the transform *(`Engine::Tiled` and `TileMap`, pure)*

Six silent gaps, closed where the data enters, so nothing later in the plan
builds on a wrong reading. Each sub-step is useful alone.

### Sub-steps

- **1a** — `Tiled::Object` reads a capsule, and refuses a shape it does not know.
- **1b** — a class property keeps its class; a tile object takes its tile's class;
  `objectalignment` is read and applied.
- **1c** — `TileMap::ObjectLayer`, answering `y_sort?` and `actors?`, and
  `TileMap#actors_layer`, forwarded by `TileWorld`.

### Shape

```ruby
# 1a — Engine::Tiled::Object
object.shape                              # => :capsule

# 1b — Engine::Properties
RGame::Engine::Properties.new(values, class_name: nil)
bag['collider'].class_name                # => 'BoxCollider'
map.objects.find { it.id == 9 }.class_name   # => 'tree', from its tile
tileset.object_alignment                  # => :bottom_left, :center, ... — Tiled's nine, and :unspecified

# 1c — Engine::TileMap
class ObjectLayer < Layer
  def initialize(y_sort:, actors:, **)
  def y_sort? = @y_sort
  def actors? = @actors
end
map.actors_layer                          # => an index, or nil
world.actors_layer                        # TileWorld forwards it, as it does first_above_layer
```

### The rules the tests pin

**1a**

1. **A `<capsule/>` reads as `:capsule`**, with its width and height, as an
   ellipse does.
2. **A child element other than `properties` and the six shapes raises
   `Tiled::FormatError`**, naming the element, the object and the file.

**1b**

3. **A class property's value answers `class_name`** with its `propertytype`, at
   every depth. A bag that is not a class value answers `nil`.
4. **Two bags with the same values and different classes are not equal.**
5. **A tile object with no class takes its tile's class.** Its own class wins.
   A shape object is unaffected.
6. **Each of the nine alignments puts the object's top-left corner where Tiled
   draws it**, with and without rotation. `:unspecified` means bottom-left, as
   today.

**1c**

7. **An object layer answers `y_sort?`**: `true` for `topdown` or no
   `draworder`, `false` for `index`.
8. **`actors?` is `true` for a bool property `actors` set to `true`.** A value
   that is not a bool, a mark on a layer that is not an object layer, and marks
   on two layers each raise `Tiled::FormatError`, naming the layers.
9. **`actors_layer` is the marked layer's index, or `nil`**, answered by
   `TileMap`, by `TileWorld`, and by `StubTileMap` through the `a tile map`
   contract.
10. **`town.tmx` parses to the same grid** (the standing invariant).

### Tests

- `spec/rgame/engine/tiled/object_spec.rb`: rules 1 and 2.
- `spec/rgame/engine/tiled/properties_spec.rb`: rules 3 and 4, a class inside a
  class included.
- `spec/rgame/engine/tiled/tileset_spec.rb`: reading `objectalignment`.
- `spec/rgame/engine/tile_map_spec.rb`: rules 5–9, from `.tmx` strings through
  `TiledFixture`.
- `spec/support/shared_examples/a_tile_map.rb` and `stub_tile_map.rb`:
  `actors_layer`.

### Verify

- `rake spec`.
- `tour.tmx` from the authoring branch loads, with object 4 as `:capsule`:

  ```
  git archive origin/build-step-8-tiled-map examples/assets | tar -x -C /tmp/tour
  ruby -Ilib -e 'require "rgame"; p RGame::Engine::TileMap.from_tiled(RGame::Engine::Tiled::Map.load("/tmp/tour/examples/assets/tiled_tour/tour.tmx")).objects.map(&:shape)'
  ```

- `docs/api/tile_maps.md` documents the capsule, `class_name` on a class value,
  inherited tile classes and the alignment. `CHANGELOG.md` has a Fixed entry for
  the capsule, and an Added entry for the rest.

**Landed.** Three commits on `object-layer-parse`, 1a to 1c as sketched.
`rake spec` 4292 examples, 0 failures (4245 before, 47 new). `rake spec:core`
517, 0 failures. `rake docs:coverage`: 0 of 214 modules and classes with an
undocumented name. `make test` and `rake drive:allocations` were not run: the
step changes no C and no per-frame path.

`tour.tmx` from the authoring branch loads, with object 4 as `:capsule`. Its
`Object Layer 1` is an `ObjectLayer` with `y_sort?` true, and `actors_layer` is
`nil`, as nothing is marked yet. The two tile objects keep the corners they had.
Every map in the repository, and the two untracked ones under `media/`, loads
the same on `main` and on the branch. A dump of every layer, every object and a
checksum of every cell matched line for line, 73 lines across 8 maps. That
includes `town.tmx`, the standing invariant.

Where the sketch was wrong, or said too little:

- **A tile object inherits its tile's properties, not only its class.** Tiled's
  manual calls it "Tile Property Inheritance", and `Object::inheritedProperties`
  in Tiled's source merges by name, lowest first: the class's members, the
  tile's properties, the template's, the object's own. The parser already merges
  template and own, so the transform puts the tile's properties under that bag,
  which is Tiled's order. **For step 3:** a map-built node from a tile object
  sees its tile's properties as its own, so its class must tag every property
  the tile carries, or rule 11 raises.
- **`CHANGELOG.md` has no Fixed entry.** The Tiled parser has not been released:
  v0.4.0 has no `lib/rgame/engine/tiled/`. The
  [update-changelog](../../../.claude/skills/update-changelog/SKILL.md) skill
  says a fix to an unreleased feature is not a fix, so the two Unreleased
  entries on Tiled maps describe the capsule, the alignment, the tile's class
  and properties, `class_name` and the object layers. **For steps 6 and 9:**
  `MapObjects` is unreleased too. Unless a release ships it first, step 6
  deletes its Added entry rather than adding a Removed one.
- **A class value with every member at its default is no longer `EMPTY`.** It
  keeps its class's name, so it is an empty bag answering `class_name`. The
  spec that pinned `EMPTY` changed with it.
- **The tile map contract gained a fourth layer.** `actors_layer` answering
  `nil` would pass for a stub that always answers `nil`. The contract's map now
  ends with an object layer marked for the actors, and both hosts build it.
- **Two guards the sketch did not name.** A `draworder` other than `topdown` or
  `index` raises at parse, where it would have read as *Manual*. An `actors`
  mark on a group raises, as one on a tile or image layer does.
- **A template instance's shape now goes through the same lookup.**
  `Template#apply` found an instance's shape with the old list of five, so an
  instance's capsule would have kept the template's shape. It now asks
  `Object.shape_element`, and an unknown child on an instance raises too.

---

## Step 2 — `Components::RandomSource`, and every project on it

The walker cannot move onto the map until it can find a random source without
its scene. The source is worth having alone: 9 projects repeat the same line, and
two engine components draw from an unseeded `Random` without saying so.

### Sub-steps

- **2a** — `Components::RandomSource`; `RGame::Game` mounts one and answers
  `random_source`; `Particles` and `WanderController` default to it.
- **2b** — the 9 projects and the 3 call sites that relied on the unseeded
  default move onto it.

### Shape

```ruby
# 2a — Engine
module RGame::Engine::Components
  # A system on the root, as Facts is: one seeded source of random numbers
  # that every node finds without being handed it.
  class RandomSource < Engine::Component
    sealed_reader :seed

    def initialize(seed:)
      super()
      @rgame_seed = seed
      @rgame_random = Random.new(seed)
    end

    def rand(...) = @rgame_random.rand(...)
  end
end

# 2a — glue
RGame::Game.new(seed: DEFAULT_SEED)   # RGAME_SEED wins when set; with neither, Random.new_seed
game.random_source

# 2a — the two engine defaults
WanderController.new(rng: nil, ...)   # nil: the root's RandomSource, found at _attach
Particles.new(rng: nil, ...)

# 2b — a project, before and after
@rng = Random.new(ENV.fetch('RGAME_SEED', DEFAULT_SEED).to_i)
@rng = system!(RGame::Engine::Components::RandomSource)
```

### The rules the tests pin

1. **Two sources with one seed give one sequence.** `rand` takes what
   `Random#rand` takes.
2. **`RGAME_SEED` wins over `seed:`**, and with neither the game picks a fresh
   seed. `seed` reads back what was used, so a run can be repeated.
3. **`WanderController` and `Particles` with no `rng:` use the root's source.**
   With no source on the root, `_attach` raises, naming `RandomSource`.
4. **An `rng:` passed explicitly still wins.**
5. **`rand` allocates nothing** beyond what `Random#rand` allocates.

### Tests

- `spec/rgame/engine/components/random_source_spec.rb`: rules 1 and 5.
- `spec_core/rgame/game_spec.rb`, or the spec that covers `game.facts`: rule 2.
- `wander_controller_spec.rb` and `particles_spec.rb`: rules 3 and 4.

### Verify

- `rake spec`, `rake spec:core`, `rake drive:allocations`.
- **Each of the 9 projects, driven with `--seed 1 --texts` before and after,
  reports the same.** One source per game can differ from one per scene in two
  ways, and each difference found gets named in the landed note:
  - something draws from the source before the scene that used to own one;
  - a scene entered twice used to start its sequence again, and now continues
    it.
- `docs/api/` documents `RandomSource` and `game.random_source`, and the pages
  for `WanderController` and `Particles` say where `rng:` comes from.
  `CHANGELOG.md` has an Added entry, and a Changed entry for the two defaults.

**Landed.** Two commits on `random-source`, 2a and 2b as sketched.
`rake spec` 4306 examples, 0 failures, 13 of them new. `rake spec:core` 522,
0 failures, 5 of them new. `rake docs:coverage`: 0 of 215 modules and classes
with an undocumented name. `rake drive:allocations`: all 43 projects within
budget. `make test` was not run, as the step changes no C.

`rand` allocates nothing with no argument, an Integer or a Range. Each of the 9
projects was driven with `--seed 1 --texts` for 240 ticks, before and after, and
tiled_world with each of its 6 scripts. The same runs went again at the lengths
the scripts are written for: adventure for 1640 ticks under seeds 1 and 4242,
topdownplatformer for 1654 under seeds 1 and 3, asteroids for 3000, effects for
400, and pooling and save_load_ids for 600. Of the plan's two predicted
differences:

- **Nothing draws from the source before the scene that used to own one.** At
  240 ticks, 11 of the 14 reports match byte for byte.
- **A scene entered twice now continues its sequence.** Adventure frees the
  town and builds it again at 1640 ticks, and the second town's sparkles land
  elsewhere: the rects' x span ends at 488.0 rather than 488.7 under seed 4242.
  Scenes entered and sounds played match. Asteroids enters `PlayScene` once in
  3000 ticks, so its replay never comes up in a driven run.

Where the sketch was wrong, or said too little:

- **Adventure and topdownplatformer never report byte for byte**, not even on
  `main`. Two runs of adventure there drew 238 and 239 frames, and its first
  text appears at tick 3 in one run and tick 4 in another. The comparison drops
  the counts and the first-drawn tick, and compares every `first`, `last` and
  `spans` field. Those match, apart from the second town above and a `faded`
  whose first frame depends on which frames were drawn.
- **Pooling's report differs in one line, and it is not a draw position.** The
  example draws its own allocation count, and the first second reads 42,623
  where it read 42,633. The seconds after it match.
- **No call site relied on the unseeded default.** The three the current state
  counted all passed their scene's seeded `Random` to `Particles`. They now pass
  nothing.
- **A burst before the node is in the tree had to be refused.** The default
  resolves at `_attach`, so `Particles#burst` before then failed on `nil`. It
  now raises and says why. The two-viewport spec burst before its root entered
  the tree, and now enters it first.
- **The raise for a missing source names the node, not the component.** It is
  `system!`'s `KeyError`: "Node2D found no
  RGame::Engine::Components::RandomSource system on the root".
- **`RGAME_SEED` is read with `Integer()`, not `to_i`.** A value that is not an
  Integer raises `ArgumentError` rather than seeding 0.
- **The seed moved to `main.rb`.** Three projects kept `DEFAULT_SEED` on the
  scene class, and it is now the game's setting. Asteroids no longer threads
  a seed through `Root` into `PlayScene`: with no `RGAME_SEED` the game picks
  one, as `Random.new` did.
- **The API reference check needed `RGAME_SEED` on its allow-list.** It reads
  a backticked upper-case word as a constant.
- **For step 6:** topdownplatformer's `Walker` already finds its random source
  in the tree, through `WanderController`'s default, and takes no `rng:`.

Documented in `docs/api/components.md` (`RandomSource`, and `rng:` on
`Particles` and `WanderController`), `docs/api/game.md` (`seed:`,
`random_source`) and `docs/api/systems.md` (six systems, not five).
`CHANGELOG.md` has an Added entry, a Changed entry for `WanderController`, and
the unreleased `Particles` entry names its default. The write-example skill
and CLAUDE.md's `--seed` row say where the seed goes.

---

## Step 3 — the settings a map may set, and building a node from an object *(Engine, pure)*

The mechanism, with no caller yet: step 5 wires it into `mount`. Building it
first, against records parsed from `.tmx` strings, lets its rules be pinned
without a scene.

### Sub-steps

- **3a** — `Engine::MapSettings` reads the `@param` tags above a class's
  `initialize`: the types, the allow-list and the checks.
- **3b** — `Node2D` takes `map_object:` and `fact_key:`.
- **3c** — `Engine::MapBuilder`: class resolution, property checks and casts,
  the origin, and the key in `Facts`.

### Shape

```ruby
# 3a — @api private; read from the comment above Chest#initialize, in a game's module
class Chest < Engine::Node2D
  # @param contents [String] the item inside
  # @param locked [Boolean] whether it takes a key to open
  def initialize(contents:, locked: false, **)
    # ...
  end
end
RGame::Engine::MapSettings.of(Chest)   # => { contents: :string, locked: :bool }, frozen and cached

# 3b — Node2D
Node2D.new(map_object: nil, fact_key: nil, **)   # alongside the keywords it takes today
node.map_object                        # sealed_reader; nil for a node built in code
node.fact_key                          # sealed_reader

# 3c — @api private; step 5's mount is its caller
builder = RGame::Engine::MapBuilder.new(tilemap_id: 'map/town.tmx')
builder.build(object)                  # => a Chest, or nil for an object whose class is data
```

### The rules the tests pin

**3a**

1. **The tags are the unbroken run of comment lines directly above the
   `def initialize` the class uses.** A blank line detaches a comment, as it
   does for `tools/strip_comments.rb` and `spec/support/api_docs.rb`.
2. **`@param name [Type]` with a type from the design's table makes `name`
   settable, with that type.** Any other type, such as `[Random]`, and a keyword
   with no tag, leave it unsettable.
3. **A tag naming something `initialize` does not take raises when it is read**,
   naming the class, the tag and the keywords `initialize` takes. So does a tag
   naming a reserved name: `Node2D`'s own keywords, `map_object`, `fact_key` or
   `fact`.
4. **A subclass without its own `initialize` reads its parent's tags.** One with
   its own reads only its own.
5. **A class with no source location raises when it is read**, naming the class.
6. **A class's tags are read once and cached.**
7. **The comment stripper keeps the tag block above a `def initialize`.**

**3b**

8. **`map_object` and `fact_key` are `nil` on a node built in code**, and read
   back what was passed.

**3c**

9. **A class starting with a capital resolves to a constant**, `Town::Chest`
   included, in the scope [open question 6](README.md#open-questions) settles.
   No such constant raises `NameError`, and a constant that is not a `Node2D`
   subclass raises `TypeError`. Each message names the tilemap id, the object's
   id and name, and the class.
10. **Any other class, or none, builds nothing.** `build` returns `nil`.
11. **Every property must be a keyword the class's tags make settable, of the
    tagged type**, and arrives as the design's table says, a String becoming a
    Symbol for `[Symbol]`. Anything else raises, listing the settable keywords.
    A class-typed property is no exception.
12. **The origin is the bottom centre of the object's box, turned with it.** A
    point object's origin is its point, and a polygon's or polyline's is its own
    corner. `angle` is the object's rotation, and `width` and `height` its size.
13. **`fact_key` is the `fact` property as a Symbol**, and otherwise
    `:"<tilemap id>#<object id>"`. `map_object` is the record it was built from.

### Tests

- `spec/rgame/engine/map_settings_spec.rb`: rules 1–6, with its classes defined
  in the spec itself, and one built by `eval` for rule 5.
- `spec/tools/comment_stripper_spec.rb`: rule 7.
- `spec/rgame/engine/node2d_spec.rb`: rule 8.
- `spec/rgame/engine/map_builder_spec.rb`: rules 9–13, its records parsed from
  `.tmx` strings through `TiledFixture` rather than built with `MapObject.new`.
- **The caller that uses both**, in the same file: a node class whose tagged
  `size:` it passes to a `BoxCollider`, deriving the offsets, built from a
  rotated rectangle object. Its box matches the object's box on the map.

### Verify

- `rake spec`.
- `docs/api/` documents the `@param` convention, `map_object` and `fact_key`.
  `MapSettings` and `MapBuilder` are `@api private`, and nothing uses them yet,
  so `CHANGELOG.md` waits for step 5.
- [write-ruby-code](../../../.claude/skills/write-ruby-code/SKILL.md) says that
  a constructor a map builds documents its settable keywords with `@param`, that
  the tags are what the map may set, and that a node passes a designer's value on
  to its components itself.

---

## Step 4 — one tile, drawn anywhere *(rough)*

`renderer.map_tile(tilemap_id, tile, left, top, width, height, orientation,
elapsed:)` in `Core::Renderer`, forwarded to the registered map as `tilemap` is,
through `TileMapRenderer`'s single-tile path opened to a position and a size.
The fake answers it, and `a renderer` checks both. `Components::MapTile` draws a
tile with its bottom centre on the node's origin, culled as a sprite is, with the
clock from `TileWorld#elapsed`.

To settle in the re-plan: whether a tileset's drawing offset applies to a tile
object as it does in a layer, what Tiled does with a tile object scaled to a
size its tile does not have, and what `map_tile` allocates per call.

## Step 5 — `mount` builds the object layers *(rough)*

`TileMapLayer.mount` gives each object layer a node in its place, y-sorted as
`y_sort?` says and at the layer's opacity, and calls `MapBuilder` for each
object. A tile object gets a `MapTile`. `slots[:actors]` becomes the marked
layer's node. The composition test goes here: a hero spawned into the marked
layer, a tree placed as a tile object, two viewports, the hero walking round the
tree.

To settle in the re-plan: open question 4, hidden object layers. Whether
`TileWorld` owns the `MapBuilder`, since it holds the tilemap id. What
`tiled_world`, whose `Objects` layer sits above the canopy, draws after this
step.

## Step 6 — every map and project on the new path *(rough)*

13 objects in 4 maps take a Ruby class's name. `Door` ×2, `Raft` ×2, `Flag`,
`Crate` and `Walker` tag their settable keywords, put their origin at the bottom
centre, and find their room or random source in the tree. `Warp` joins `examples/doors` and
`test_projects/adventure`. The 5 scenes lose `MapObjects` and `spawn_into`, and
`MapObjects` goes, with a Removed entry in `CHANGELOG.md`.

To settle in the re-plan: open question 3, the leftover slots. Whether
`Warp` subclasses `Door`. The screen-position comparison for every driven
project these maps reach.

## Step 7 — Tiled's custom types, written from Ruby *(rough)*

`RGame::Engine::MapTypes.write(path)` writes a Tiled class into a
`.tiled-project` for each `Node2D` and `Component` subclass whose tags make any
keyword settable. It
replaces the classes it owns and keeps the designer's. An Array of Symbols
becomes a Tiled enum.

To settle in the re-plan: open questions 2 and 5, where it runs and what default
a member shows. The name it writes for a class inside a game's module, which
follows from open question 6. Whether the generated project gains the task, and
`spec/rgame/cli/generated_project_spec.rb` with it. Whether its `.gitignore`
leaves out `*.tiled-session`, as this repository's does since step 0.

## Step 8 — the maps checked, and the level played *(rough)*

Two halves, as [map-requirements.md](map-requirements.md#the-check-and-the-example-that-plays-the-map)
sketches:

- `spec/example_assets_spec.rb` checks `tour.tmx` against R1–R23, and its
  gzip and infinite twins.
- A second map, designed as a level, is played by a new example with a drive
  script. Its requirements are written at this step's re-plan, against the
  exported types: trees as tile objects in the marked layer, a chest whose state
  survives leaving the room, a value a node passes on to its component.

`puzzle.tmx`, which has no object layer, covers the fallback slot.

## Step 9 — fold the plan back and delete it

- **`docs/api/tile_maps.md`** says what a map builds and how: the class rule,
  data classes, the `@param` tags, tile objects, the `actors`
  mark, `fact_key`. "Building nodes from objects" is rewritten for the new path.
- **`docs/api/components.md`** covers `MapTile` and `RandomSource`.
- **`docs/api/scene_graph.md`** covers what `mount` builds for an object layer.
- **`docs/plans/possible-todos.md`**:
  - "Platforms as Tiled tile objects" is answered, or its trigger updated.
  - Open questions still open move here.
  - So do the plan's "does not deliver" items that have a trigger.
- Run [learn-from-mistakes](../../../.claude/skills/learn-from-mistakes/SKILL.md)
  over every step's "What proved wrong".
- Delete `docs/plans/object-layers/`.

### Verify

`CHANGELOG.md` covers everything steps 1–8 shipped, per
[update-changelog](../../../.claude/skills/update-changelog/SKILL.md): the
capsule fix, the random source, map-built nodes, the `@param` convention, `map_tile`, and
the removal of `MapObjects`. `rake` passes. `docs/plans/object-layers/` is gone,
and `grep -r object-layers docs/ .claude/` finds nothing.
