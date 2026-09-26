# Roadmap

**Steps 0–4 are implemented.** Step 5 is detailed, inserted after step 4
landed, and so are steps 6 and 7, re-planned after step 3 landed. Steps 8 and 9
are rough and get re-planned once the steps before them land. Every step from 5
on moved up by one, landed notes included, so a number in this document is
today's.

## Dependency shape

```
0 tour.tmx requirements ──────────────────────────────────────────────────────────────────────────┐  authoring runs in parallel
                                                                                                  │
1 parse + transform ─→ 3 map settings + builder ─→ 5 id + Fact ─┐                                 │
                       4 one tile drawn ────────────────────────┴─→ 6 mount builds ─┐             │
2 random source ────────────────────────────────────────────────────────────────────┴─→ 7 migrate ─→ 8 export ─→ 9 checked + played ─→ 10 fold back
```

Steps 1, 2 and 4 depend on nothing in this plan and can land in any order. Step 3
needs step 1, because the class it resolves may come from the object's tile.
Step 5 needs step 3, whose builder and `Node2D` keywords it changes, and step 6
builds every node on what step 5 leaves. Step 7 needs step 2, because a `Walker`
built from a map finds its random source in the tree. Step 9 needs step 8: the
level's designer picks classes from the exported types, rather than typing them.

## The invariant every step preserves

> **Every driven project enters the same scenes, plays the same sounds, and
> draws the same things at the same screen positions**, except where a step names
> what moves and why.

A report cannot match byte for byte across a step that moves a node's origin,
because it records each draw in local coordinates (see
[verify](../../../.claude/skills/verify/SKILL.md)). Steps 6 and 7 move origins,
so they compare where each draw lands on screen.

And the standing one from the Tiled format plan:
`spec/example_assets_spec.rb` still parses `town.tmx` to the same grid.

## What lands early, if the plan is abandoned

| Step | Defect it closes |
|---|---|
| 1 | A capsule reads as a rectangle; a tile object loses its tile's class; `objectalignment` places objects where Tiled does not |
| 2 | `Particles` and `WanderController` draw from an unseeded `Random`; 9 projects each read `RGAME_SEED` themselves |
| 4 | Nothing can draw one tile of a map outside a tile layer; a tileset that preserves its tiles' aspect, or draws them at the grid's size, draws differently from Tiled without a word |
| 5 | Every node carries a key for `Facts` and its object's whole record, though a node reads neither once built; adventure's chest, lever and crate each find `Facts` through their room and build their keys by hand |

Step 3 has no caller until step 6, so it lands for step 6 rather than alone.

---

## Step 0 — the requirements for `tour.tmx`

Authoring is half done, and step 1 changes what the parser reads. So the
requirements settle first, and you keep authoring against them while steps 1–8
are built. The level map gets its own requirements in step 9, once the exported
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
  `.gitignore` has no entry. Step 8 decides the generated project's Tiled
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
  and properties, `class_name` and the object layers. **For steps 7 and 10:**
  `MapObjects` is unreleased too. Unless a release ships it first, step 7
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
- **For step 7:** topdownplatformer's `Walker` already finds its random source
  in the tree, through `WanderController`'s default, and takes no `rng:`.

Documented in `docs/api/components.md` (`RandomSource`, and `rng:` on
`Particles` and `WanderController`), `docs/api/game.md` (`seed:`,
`random_source`) and `docs/api/systems.md` (six systems, not five).
`CHANGELOG.md` has an Added entry, a Changed entry for `WanderController`, and
the unreleased `Particles` entry names its default. The write-example skill
and CLAUDE.md's `--seed` row say where the seed goes.

---

## Step 3 — the settings a map may set, and building a node from an object *(Engine, pure)*

The mechanism, with no caller yet: step 6 wires it into `mount`. Building it
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

# 3c — @api private; step 6's mount is its caller
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
  so `CHANGELOG.md` waits for step 6.
- [write-ruby-code](../../../.claude/skills/write-ruby-code/SKILL.md) says that
  a constructor a map builds documents its settable keywords with `@param`, that
  the tags are what the map may set, and that a node passes a designer's value on
  to its components itself.

**Landed.** Three commits on `map-builder`, 3a to 3c as sketched. `rake spec`
4369 examples, 0 failures (4318 before, 51 new). `rake spec:core` 522,
0 failures. `rake docs:coverage`: 0 of 218 modules and classes with an
undocumented name. `rake drive:allocations`: all 43 projects within budget, run
because `Node2D#initialize` sets two more ivars. `make test` was not run, as the
step changes no C.

Open question 6 was settled before the step, as option A. A map's `Chest`
builds a `SpecMapGame::Chest` under the scope `SpecMapGame::Room`, and the same
map builds a `SpecMapOtherGame::Chest` under `SpecMapOtherGame::Room`. The
caller that uses both builds a `Crate` whose tagged `size:` sizes its collider.
On an unturned 24×24 object at (100, 200), the collider's box is
(100, 200, 24, 24). On the same object turned 30°, the collider's four corners,
carried through the node's frame, land on the four corners Tiled draws.

Where the sketch was wrong, or said too little:

- **A turned object's collider does not turn.** The sketch said the crate's box
  matches a turned rectangle's box. Only the node's frame turns: a
  `BoxCollider` stays axis-aligned in the world, by design. So the spec checks
  the collider's box on an unturned object, and its corners through the node's
  frame on a turned one. No object in the repository's maps is turned, and
  `tour.tmx`'s one turned object is R21's tile object. **For steps 6 and 7:** a
  map-built node on a turned object collides as if unturned.
- **A required keyword no property sets raises**, naming the map, the object and
  the keyword. Ruby's own "missing keyword" names neither the map nor the
  object. The first version counted only the properties, so it refused a class
  that requires `width:`, which the object's box sets. A spec with a `Raft` of
  that shape pins the fix. **For step 7:** `Raft` may require `width:` and
  `height:`, and may not tag them.
- **The name resolves along the scope's name, not where the class was
  written.** Ruby, inside `class Adventure::Town`, does not look in
  `Adventure`. The builder does, because the name says the class belongs there.
  Between the game's module and the top level it also looks in what the scope
  inherits, as Ruby does.
- **A class written with `ruby -e` or in IRB has no source file either**, not
  only one from `eval` or C. `spec/api_docs/examples_spec.rb` runs a complete
  example with `ruby -e`, so the internals page shows a tagged class as a
  fragment.
- **A `@param` tag with no type, or written `@param [String] contents`, reads as
  no tag.** It is not refused. A property it was meant for raises at build
  instead, listing the settable keywords and naming the `@param` rule.
- **The reserved names are read from `Node2D#initialize`**, plus `fact`, so 3b's
  two keywords joined them without a list. A tag naming one raises whatever its
  type.
- **`[RGame::Util::Color]` reads as `[Util::Color]`.** Engine code may write the
  long form, and a tag of it would otherwise leave the keyword unsettable
  without a word.
- **The documentation went to `internals.md`, not `tile_maps.md`.** Nothing calls
  `MapBuilder` until step 6, and `tile_maps.md` documents what a game does today,
  with `MapObjects`. It gained `map_object:` and `fact_key:`, which a
  `MapObjects` block may pass. **For step 6:** "Building nodes from objects"
  moves onto the new path, and so does what `internals.md` says a game author
  writes.

`spec/rgame/engine/map_settings_spec.rb` also reads every engine `Node2D` class,
as the design asks. None has a tag yet, so it guards the first.

Documented in `docs/api/internals.md` (`MapBuilder`, the tag table and its
rules), `docs/api/tile_maps.md` (`map_object:` and `fact_key:`) and the
write-ruby-code skill (a node class a map builds). `CHANGELOG.md` waits for
step 6, as planned.

---

## What was measured before re-planning steps 4, 6 and 7

Taken at `f116a92`, after step 3 landed, and on
`origin/build-step-8-tiled-map` at `e9726f1` for `tour.tmx`.

| | |
|---|---|
| Scenes mounting `town.tmx` | 7; 2 of them define a `Door` (`examples/doors`, adventure) |
| Those 5 others reading `town.tmx`'s objects | 0 |
| Scenes passing `slots:` to `mount` | 6: `doors`, adventure's `Town` and `Garden`, `moving_platforms`, `Course`, `cutscene` |
| Scenes passing a slot other than `:actors`, once step 7 lands | 0 |
| Projects passing `mount(y_sort: false)` | 0 |
| Object layers in tracked maps | 7 in 5 maps: `town`, `garden` and `pits` 1 each, `platforms` and `course` 2 each |
| Tracked maps with an `above` layer, among those with an object layer | 0, so every slot sits over every layer |
| Tracked maps with a hidden layer | 0 |
| Tile objects in tracked maps | 0. `tour.tmx` has 2: one turned 90°, one flipped horizontally |
| Tilesets setting `fillmode` or `tilerendersize` | 0, tracked or on the authoring branch |
| Raft objects | 3: 2 polylines and 1 polygon, sized by `width` and `height` properties that step 3 refuses |
| Map-built node classes whose origin moves at step 7 | 1, `Door` ×2. The flags, the crate and the walker stand on points; a raft's origin is its route's first point, as today |
| `MapObjects` in a release | none: its `CHANGELOG.md` entry is under Unreleased |
| `slots:` in a release | none: v0.4.0 had `under:` |

**What Tiled does with a tile object** *(measured, in Tiled's `maprenderer.cpp`
and `orthogonalrenderer.cpp`, and its TMX reference)*:

- **The tile fills the object's box.** `CellRenderer::render` scales it by the
  box's size over the image's, unless the tileset's `fillmode` is
  `preserve-aspect-fit`, which scales both axes by the smaller factor.
- **The tileset's drawing offset applies**, multiplied by the same scale.
- **A horizontal or vertical flip negates that axis's scale**, inside the box.
  An anti-diagonal flip turns the tile a quarter and swaps the flips.
- **`tilerendersize="grid"`** draws a tileset's layer tiles at the map's grid
  size. rgame reads neither attribute.

---

## Step 4 — one tile, drawn anywhere *(`Core::TileMapRenderer`, `Components::MapTile`)*

A tile object is one picture of a map's tile at one position, and nothing can
draw that today. `TileMapRenderer` draws a whole layer, and its one-tile draw is
private and bound to a cell. Step 6 gives every tile object a `MapTile`, so the
drawing comes first. The step depends on nothing earlier in the plan.

It also closes two silent gaps the research found. A tileset that preserves its
tiles' aspect, or draws them at the grid's size, draws differently from Tiled
without a word.

### Sub-steps

- **4a** — `Tiled::Tileset` refuses a `fillmode` other than `stretch` and a
  `tilerendersize` other than `tile`.
- **4b** — `TileMapRenderer#draw_tile` draws one tile into a box, and a layer's
  cells draw through it. `Renderer#map_tile` forwards to it, as `#tilemap`
  forwards to `draw_layer`, and so does `FakeRenderer#map_tile`.
- **4c** — `Components::MapTile`.

### Shape

```ruby
# 4b — Core, @api private: the registered map's own draw, as draw_layer is
tiles.draw_tile(renderer, tile, left, top, width, height, orientation, elapsed: 0.0, z: 0)

# 4b — Core::Renderer, and FakeRenderer alike
renderer.map_tile(tilemap_id, tile, left, top, width, height, orientation, elapsed: 0.0, z: DEFAULT_Z)

# 4c — Engine
module RGame
  module Engine
    module Components
      # Draws one tile of the scene's map with its bottom centre on its node's
      # origin, stretched to the node's width and height.
      class MapTile < Engine::Component
        include Engine::Culling

        sealed_reader :tile, :orientation

        def initialize(tile:, orientation: TileMap::Orientation::IDENTITY)
          super()
          @rgame_tile = tile
          @rgame_orientation = orientation
        end

        def _attach = @rgame_world = node.system!(TileWorld)

        def _draw(renderer, view)
          width = node.width
          height = node.height
          left = Engine::Anchor.left(:bottom, width)
          top = Engine::Anchor.top(:bottom, height)
          return if culled?(view, node.world_x + left, node.world_y + top, width, height)

          renderer.map_tile(@rgame_world.tilemap_id, @rgame_tile, left, top, width, height, @rgame_orientation,
                            elapsed: @rgame_world.elapsed, z: Util::Z::Z_MIN)
        end
      end
    end
  end
end
```

- **One drawing path for a turned tile.** The private cell draw becomes a call
  to `draw_tile`, with the tile's own footprint as the box: its image's size,
  standing on the cell's bottom-left corner, moved by the drawing offset. A box
  the size of the image scales by 1, so a layer draws the calls it draws today.
- **`MapTile` resembles `Sprite`, and stays a component of its own.** Both put
  a picture's bottom centre on the origin and cull against the node's box, and
  `MapTile` reuses `Engine::Anchor` and `Engine::Culling` for exactly that. What
  differs is the part `Sprite` does not have: a map id, a clock from the
  `TileWorld`, an orientation and a stretch to the box.
- **The tile draws under everything else its node draws**, at `Z_MIN` in the
  node's slot. Components draw in the order they were added, and step 6 adds a
  `MapTile` after the class's `initialize`, so it would otherwise cover the
  class's own `Sprite`.

### The rules the tests pin

**4a**

1. **A tileset with `fillmode="preserve-aspect-fit"` raises
   `Tiled::FormatError`**, naming the attribute, the tileset and the file, and
   saying rgame stretches a tile object's tile. `stretch`, and no attribute, read
   as today.
2. **A tileset with `tilerendersize="grid"` raises the same way.** `tile`, and no
   attribute, read as today.

**4b**

3. **`draw_tile` stretches the tile to the box.** Its `image_at` has the box's
   top-left corner, and scales by the box's width and height over the image's.
4. **An orientation turns and mirrors the tile inside its box**, as Tiled's
   `CellRenderer` does. A mirrored tile mirrors in place. A tile turned twice
   turns about the box's centre. A tile turned a quarter turns about the box's
   centre, its image scaled to the box's height by its width.
5. **The tileset's drawing offset moves the tile**, scaled as the tile is.
6. **An animated tile draws the frame `elapsed` selects**, as `frame_tile`
   answers it.
7. **`z:` reaches every `image_at`.**
8. **Every example in `tile_map_renderer_spec.rb` passes unchanged**, though a
   layer's cells now draw through `draw_tile`.
9. **`renderer.map_tile` forwards to the registered map's `draw_tile`**, in the
   live renderer and in the fake, and `a renderer` checks both. An id no one
   registered resolves through the asset manager, as `tilemap` does.
10. **`draw_tile` allocates nothing** for a still tile, a mirrored one, a turned
    one, and each frame of an animated one.

**4c**

11. **`MapTile` draws its tile with its bottom centre on the node's origin**, the
    node's width and height, and passes no angle: `Node2D#draw` has already
    pushed the node's rotation.
12. **The map id and the clock come from the scene's `TileWorld`.** With none,
    `_attach` raises `system!`'s `KeyError`.
13. **It is culled against its box, as `Sprite` is against its own**, and a node
    with no size is never culled. The drawing offset is left out of the cull
    rect: it is a few pixels, and the most a missing edge can be.
14. **It draws at `Z_MIN`.**
15. **`_draw` allocates nothing.**

### Tests

- `spec/rgame/engine/tiled/tileset_spec.rb`: rules 1 and 2.
- `spec_core/rgame/core/tile_map_renderer_spec.rb`: rules 3–8 and 10. For rule 10
  it requires `spec/support/allocate_nothing_matcher.rb`, which names no layer,
  and hands `draw_tile` a plain object answering `image_at` and `rotated`, never
  a double.
- `spec/support/shared_examples/a_renderer.rb` and `spec/support/fake_renderer.rb`:
  rule 9, through the recorder the `tilemap` example uses. The orientation it
  passes is any object, since the contract runs in `spec_core/` too, where
  `Engine` is not loaded.
- `spec/rgame/engine/components/map_tile_spec.rb`: rules 11–15.

### Verify

- `rake spec`, `rake spec:core`, and `rake drive:allocations`, because a layer's
  animated tiles now draw through `draw_tile` every frame.
- **Every driven project reports the same under `--seed 1`, before and after.**
  No project draws a tile object yet, and a layer draws the calls it drew.
- No driven project reaches `map_tile` until step 9, so rules 10 and 15 are what
  decide its allocations.
- `docs/api/drawing.md` documents `map_tile` beside `tilemap`, and
  `docs/api/components.md` documents `MapTile`. `CHANGELOG.md` has an Added entry
  for both. The Unreleased entry on Tiled maps names the two refusals.

**Landed.** Three commits on `map-tile`, 4a to 4c as sketched. `rake spec`
4385 examples, 0 failures (4369 before, 16 new). `rake spec:core` 533, 0
failures (522 before, 11 new). `rake docs:coverage`: 0 of 219 modules and
classes with an undocumented name. `rake drive:allocations`: all 43 projects
within budget, at the figures step 3 measured give or take a tenth. `make test`
was not run, as the step changes no C.

The 12 projects that draw a map were driven with `--seed 1 --texts` for 240
ticks, on `main` and on the branch, 18 runs with every tiled_world script and
both cutscene scripts. 17 reports match byte for byte. topdownplatformer's
differs only in its map id, which is the map's absolute path in each checkout.
The recorder counts `tilemap` calls but not the tiles drawn inside one, so the
layer side rests on `tile_map_renderer_spec.rb`: its 58 examples pass
unchanged, the eight orientations read back pixel for pixel through a real
window among them. `draw_tile` allocates nothing for a still, a mirrored, a
turned and an animated tile, and `MapTile#_draw` nothing either. The spec
fails when an Array is added to `draw_tile`. `tour.tmx` from the authoring
branch still loads, with its two tile objects.

Where the sketch was wrong, or said too little:

- **A quarter-turned tile is stretched before it turns, not after.** Rule 4
  said its image is scaled to the box's height by its width. Tiled's
  `CellRenderer::render` scales by the box's width over the image's and its
  height over the image's, then moves the centre by half the difference of the
  box's sides and turns. The turned tile keeps the box's bottom-left corner,
  which is what a layer already drew. So a layer's cell passes a box the size of
  its image, not its turned footprint as the sketch said.
- **Two drives at once are no comparison.** The first comparison ran `main` and
  the branch side by side. Seven of the 36 runs crashed or wrote no report, and
  six more drew up to 8 frames fewer than 240. Run one after the other, they
  match.
- **`StubTileMap#frame_tile` allocated**, returning from inside a block, so an
  allocation spec through it measured the stub. It walks the frames in a
  `while` loop now.
- **`MapTile` is lifted by its node's elevation**, as a `Sprite` is. The sketch
  left it out, and a hopping node placed as a tile object would have left its
  picture on the ground.
- **The drawing offset stays out of the cull rect**, as rule 13 said. A tile
  object's offset is stretched with it, so a large stretch moves it further
  than the few pixels a layer tile moves.

Documented in `docs/api/components.md` (`MapTile`), `docs/api/drawing.md`
(`map_tile`) and `docs/api/tile_maps.md` (the two refusals, and the
`MapObject` table pointing at `MapTile`). `CHANGELOG.md` has an Added entry
for both, and the Unreleased entry on Tiled maps names the refusals.

---

## What was measured before planning step 5

Taken at `c881136`, after step 4 landed.

| | |
|---|---|
| Readers of `Node2D#fact_key` | 0 in `examples/` and `test_projects/`. `MapBuilder` sets it, and 2 specs and 2 pages of `docs/api/` read it back |
| Readers of `Node2D#map_object` once a node is built | 0. `MapBuilder` reads the object itself while it builds |
| What step 7's sketches read from `map_object` | a route and a name, each while building: `Raft`'s route through `Path.from_object`, in two games, and the name for `Flag` and adventure's `Door` |
| Classes taking a route or a name from their object today | `Raft` takes `route:` in both games, and `Flag` takes `name:`, each from a `MapObjects` block |
| Keywords of `Node2D#initialize` | 11, `map_object:` and `fact_key:` among them |
| `object_id` | Ruby's `Kernel#object_id`. Defining it makes Ruby warn "redefining 'object_id' may cause serious problems" *(measured)* |
| Nodes keeping their own state in `Facts` | 3, in adventure, all built in code. `Chest` and `Lever` keep one value under the `key:` their room passes. `Crate` keeps three, under keys it derives from one: `:crate_x`, `:crate_y` and `:crate_way`. Each also takes `facts:` from its room |
| Saves in adventure | none. Nothing in it writes a `SaveFile`, so a renamed key loses no one's state |
| Adventure, `--seed 4242 --texts`, 1640 ticks | in each half of the split screen, `chest`, `lever` and `crate` draw 119, 501 and 80 times. That is from tick 143 until the crate moves at 223, the chest opens at 262 and the lever is pulled at 644. None of the three draws after the town is built a second time *(measured)* |

---

## Step 5 — a node keeps its object's id, and `Components::Fact` keeps its state *(Engine, pure)*

Step 3 gave every node two keywords that a map fills: `map_object:`, the
object's whole record, and `fact_key:`, a key for `Facts`. After step 4 landed,
the conversation turned both down. In the user's words: "Giving _every_ node a
facts key because _some_ nodes might need it is bad design. That's what
components are for." And once a node is built, "it shouldn't matter _how_ it was
constructed", apart from its object's id. Decisions 19 and 20 hold what replaces
them. Nothing outside `lib/`, `spec/` and `docs/` reads either keyword yet.
Step 6 builds every map-built node through `MapBuilder`, and step 7 writes the
classes that read them, so the change comes before both.

What it resembles:

- **Reused.** `Components::Facts` holds the values, and `Facts.check_value`
  checks a default. `system!` finds `Facts` and the `TileWorld`.
  `Path.from_object` builds a route.
- **Extended.** The builder already reads `initialize`'s parameters for the
  keywords it requires. It reads them for `route:` and `name:` as well.
  `MapSettings` reserves what the builder sets, so its list changes with the
  keywords.
- **Genuinely new.** `Components::Fact`, one of a node's values in `Facts`.
  Adventure's three nodes each do it by hand today, with a `facts:` and a `key:`
  from their room. `Components::Identity` is the nearest existing thing. The
  design rejected it for this job: its ids are the game's to hand out, and an
  Integer id cannot key a fact.

### Sub-steps

- **5a** — `MapBuilder` hands a node values, never its record. `Node2D` loses
  `map_object:` and `fact_key:` and takes `map_object_id:`. A class whose
  `initialize` names `route:` or `name:` receives it. The property `fact` is no
  longer special.
- **5b** — `Components::Fact`.
- **5c** — adventure's `Chest`, `Lever` and `Crate` keep their state through
  `Components::Fact`, and stop taking `facts:`.

### Shape

```ruby
# 5a — Node2D. map_object: and fact_key: go.
Node2D.new(map_object_id: nil, **)   # alongside the keywords it takes today
node.map_object_id                   # sealed_reader: the object's id, or nil for a node built in code

# 5a — what MapBuilder passes, besides the box, the id and the tagged properties
class Raft < Engine::Node2D
  def initialize(route:, **)         # an Engine::Path, for a polyline or a polygon
class Flag < Engine::Node2D
  def initialize(name:, **)          # the object's name, '' when the designer gave none

# 5b — Engine
module RGame
  module Engine
    module Components
      # One value of its node's, kept in the root's Facts, so it outlives the
      # room the node stands in.
      class Fact < Engine::Component
        def initialize(default: nil, key: nil, part: nil)
          super()
          @rgame_default = Facts.check_value(default) { 'a Fact default' }
          @rgame_given = key
          @rgame_part = part
        end

        def _attach
          @rgame_facts = node.system!(Facts)
          @rgame_key ||= derived_key
        end

        # The Symbol the value is kept under.
        def key
          attached
          @rgame_key
        end

        def value = attached.fetch(@rgame_key, @rgame_default)

        def value=(value)
          attached[@rgame_key] = value
        end

        private

        def derived_key
          base = @rgame_given || map_key or raise ArgumentError, '...'   # rule 10
          @rgame_part ? :"#{base}.#{@rgame_part}" : base
        end

        def map_key
          id = node.map_object_id or return
          :"#{node.system!(TileWorld).tilemap_id}##{id}"
        end

        def attached = @rgame_facts || raise(...)   # rule 13
      end
    end
  end
end
```

Adventure, in its own module:

```ruby
# 5c — Chest, before and after. Lever changes the same way.
def initialize(facts:, key:, **)
  # ...
  @facts = facts
  @key = key
  @state = facts.fetch(key, 'closed').to_sym
end

def initialize(key:, **)
  super(**)
  add_component(Components::BoxCollider.new(width: SIZE, height: SIZE, layer: :interactable))
  @kept = add_component(Components::Fact.new(key:, default: 'closed'))
end

def _enter_tree = @state = @kept.value.to_sym

# 5c — Crate keeps three values, one Fact each, and moves to where it was left
@kept_x = add_component(Components::Fact.new(key:, part: :x, default: x))
@kept_y = add_component(Components::Fact.new(key:, part: :y, default: y))
@kept_way = add_component(Components::Fact.new(key:, part: :way, default: 'still'))

def _enter_tree
  self.x = @kept_x.value
  self.y = @kept_y.value
  @way = @kept_way.value.to_sym
end

# 5c — the town passes no facts
@actors.add_node(Chest.new(x: CHEST.first, y: CHEST.last, key: :chest))
```

- **The key is derived at the first `_attach`, not in `initialize`.** A node
  has no scene before it enters a tree, so there is no `TileWorld` to name the
  map. So `Chest` and `Lever` read their state in `_enter_tree`, and `Crate`
  moves to where it was left there. `CollisionWorld` indexes its colliders in
  its own `_update`, so a crate moved in `_enter_tree` collides where it stands.
- **A node keeping several values adds a `Fact` for each**, with a `part:`.
  `Crate`'s keys become `:"crate.x"`, `:"crate.y"` and `:"crate.way"`. Nothing
  saves the old ones.
- **`route:` and `name:` go only to a class whose `initialize` names them.**
  Every class forwards `**` to `Node2D`, which takes neither, so passing them to
  every class would raise. They need no `@param` tag, as `width` and `height`
  need none: the designer draws a route and types a name, and sets neither in a
  property field.
- **`Fact` has no `watch`.** A node that must follow a restore watches
  `fact.key` in `Facts` itself.

### The rules the tests pin

**5a**

1. **`Node2D#map_object_id` reads back what was passed, and is `nil` on a node
   built in code.**
2. **The builder sets `map_object_id` to the object's id** on every node it
   builds.
3. **A class whose `initialize` names `route:` receives the object's route**, as
   `Path.from_object` builds it: open for a polyline, closed for a polygon, and
   turned with the object. A class that requires `route:`, built from any other
   shape, raises `ArgumentError` naming the object, its shape and the class. A
   class whose `route:` is optional receives none from another shape.
4. **A class whose `initialize` names `name:` receives the object's name**, or
   `''` when the designer gave none.
5. **A class that names neither receives neither**, though it forwards `**` to
   `Node2D`.
6. **`MapSettings` refuses a tag naming `route` or `name`**, and one naming
   `map_object_id`, as one of `Node2D`'s own keywords. It no longer refuses
   `fact`.
7. **A `fact` property is a property like any other.** It sets a keyword `fact`
   that the class tags, and raises otherwise, listing the settable keywords.

**5b**

8. **With `key:`, the key is `key:`**, or `:"<key>.<part>"` with a `part:`.
9. **Without `key:`, the key is `:"<tilemap id>#<map_object_id>"`**, with
   `.<part>` for a part. That is decision 9's default, moved here. The tilemap id
   is the scene's `TileWorld`'s, read at the first `_attach`.
10. **With neither `key:` nor a `map_object_id`, `_attach` raises
    `ArgumentError`**, naming the node's class and saying to pass `key:`.
11. **The key is derived once.** A node that leaves the tree and enters it
    under a scene with another `TileWorld` keeps its key.
12. **`value` is the fact, or `default` for a key never set.** `value=` writes
    the fact, and `Facts` emits `on_changed` and calls its watchers, as for any
    write.
13. **`key`, `value` and `value=` raise before the node first enters a tree**,
    saying why, as `Particles#burst` does since step 2.
14. **A `default` that `Facts` would refuse raises `TypeError` as the component
    is built**, a Symbol included. So do a `key:` and a `part:` that are not
    Symbols.
15. **Two `Fact`s on one node, with different parts, keep two values.**
16. **`value` allocates nothing, and neither does `value=` writing the value
    already held.**

**5c**

17. **Adventure's town, built a second time, holds the chest, the lever and the
    crate as the first one left them**, the crate where it was pushed. No spec
    loads a test project's classes, so the drive under Verify decides it.

### Tests

- `spec/rgame/engine/node2d_spec.rb`: rule 1, in place of
  `#map_object and #fact_key`.
- `spec/rgame/engine/map_builder_spec.rb`: rules 2–5 and 7, from `.tmx` strings
  through `TiledFixture`. "The fact key and the record" becomes "the object
  id". A new describe covers `route:` and `name:`: a polyline, a polygon, a
  turned polyline, a rectangle for a class that requires a route, and one for a
  class whose route is optional.
- `spec/rgame/engine/map_settings_spec.rb`: rule 6. `SpecMapKeyedChest` tags
  `route` and raises. `SpecMapFactChest`'s `fact` tag now reads.
- `spec/rgame/engine/components/fact_spec.rb`: rules 8–16.
- **The caller that uses both**, in `fact_spec.rb`: a chest class that adds a
  `Fact`, built by `MapBuilder` from a `.tmx` string under a scene with a
  `TileWorld`. Beside it stands the same class built in code with `key: :chest`.
  Both are opened. The scene is freed and built again from the same map, and
  each new chest reads `open`: one under `:"map/town.tmx#7"`, the other under
  `:chest`.

### Verify

- `rake spec`, `rake spec:core` and `rake drive:allocations`.
  `Node2D#initialize` sets one ivar where it set two, and the crate writes its
  facts from `_update`.
- **Adventure, driven with `--seed 4242 --texts` and `--seed 1 --texts` for 1640
  ticks, before and after.** The scenes entered, the sounds played, and the
  texts with their first ticks match, give or take the frame step 2 found varies
  between runs. At seed 4242, `chest`, `lever` and `crate` still draw 119, 501
  and 80 times in each half of the split screen, and none of them draws after
  the town is built again. A count grown by the ticks after that rebuild would
  mean a lost state. The draw calls' spans and the translates pushed match, so
  the crate stands where it was left.
- `grep -rnw -e fact_key -e map_object lib spec examples test_projects docs/api .claude`
  finds only `tile_map.rb`'s `require_relative 'map_object'`, where it found 31
  lines at `c881136`.
- `docs/api/components.md` documents `Fact`, between `DespawnOffscreen` and
  `FeetCollider`. The Facts section of `docs/api/dialogue.md`, and
  `Components::Facts`' class comment, say where a node's own state goes.
  `docs/api/internals.md`'s `MapBuilder` section describes `map_object_id`,
  `route:` and `name:`, and drops `fact`. `docs/api/tile_maps.md`'s `MapObjects`
  bullet names `map_object_id:`. The write-ruby-code skill's "A node class a map
  builds" says a class names `route:` or `name:` to receive them, untagged.
- `CHANGELOG.md` has an Added entry for `Components::Fact` and
  `Node2D#map_object_id`. `map_object:` and `fact_key:` have no entry to remove,
  since step 3 left the changelog to step 6.

---

## Step 6 — `mount` builds the object layers, and they replace named slots *(Engine, pure)*

Step 3 built one node from one object, step 4 drew one tile, and step 5 settled
what a node keeps of its object. This step joins them to the tree: a map's object layers become nodes in their place, and a scene
writes no line for what they hold. An object layer also marks a place in the
layer order, so named slots go (decision 17).

Nothing in a tracked map builds yet. Every class there stays lower-case until
step 7, so the step can land, and be driven, against projects that do not change.

### Sub-steps

- **6a** — `MapBuilder` gives a tile object its tile, and a hidden object
  opacity 0.
- **6b** — `mount` builds each object layer as a node in its place, and the
  layer marked `actors` is where the actors go.
- **6c** — object layers replace named slots: `mount` returns
  `TileMapLayer::Places`, `slots:` goes, and the six scenes that pass it move
  off it.

### Shape

```ruby
# 6a — MapBuilder, as step 3 left it, and:
builder.build(tile_object)     # its class's node with a MapTile added, or a plain Node2D with one for a data class
builder.build(hidden_object)   # the node it would build, at opacity 0

# 6b — Engine
world.objects                  # TileWorld forwards TileMap#objects, as it forwards #layer

# 6c — Engine
places = RGame::Engine::TileMapLayer.mount(view)  # y_sort: true, as today
places[:actors]    # the layer marked `actors`; on a map with none, a node under the first `above` layer
places['doors']    # the object layer named 'doors', or a 'Group/layer' path, as TileMap#layer_index takes them
```

The six scenes, before and after:

```ruby
# examples/doors, adventure's Town and Garden
slots = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new), slots: { doors: nil, actors: nil })
doors.spawn_into(slots[:doors], @map.objects)

places = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new))
doors.spawn_into(places['doors'], @map.objects)   # until step 7 lets the map build them
```

`moving_platforms` and `Course` spawn their rafts into `places['platforms']`,
and `cutscene` drops a `slots:` equal to the default. Each object layer stands
where its scene's slot stood: after every tile layer, before the actors. So
nothing changes place on screen.

### The rules the tests pin

**6a**

1. **A tile object whose class builds a node gets a `MapTile`** of its tile and
   orientation, added after the class's `initialize`.
2. **A tile object whose class is data builds a plain `Node2D`**, placed as step
   3's rule 12 places any node, with its `map_object_id` and a `MapTile`.
3. **A shape object whose class is data still builds nothing.**
4. **An object hidden in Tiled builds, at opacity 0** (decision 16). It updates
   and collides, and draws nothing.

**6b**

5. **Each object layer becomes a `Node2D` in its place among the layers**,
   y-sorted when `y_sort?` says so. Its opacity is the layer's, and 0 when the
   layer is hidden.
6. **Its objects build in the layer's order, and are added under it.** Their
   classes resolve in the class of the node the scene's `TileWorld` is attached
   to, as open question 6 settled.
7. **The marked layer's node is where the actors go.** A map with no mark keeps
   today's place: a node under the first `above` layer, or over every layer,
   y-sorted unless `y_sort: false`.
8. **A hidden layer marked `actors` raises `Tiled::FormatError` at load**, naming
   the layer. Every actor spawned into it would draw nothing.
9. **A second `mount` over the same `TileWorld` raises**, naming its node. It
   would build every object twice.

**6c**

10. **`places[:actors]` answers rule 7's node, and `places[name]` the object
    layer a name or path names.** A tile or image layer's name raises
    `ArgumentError`, saying only an object layer holds nodes. A name no layer
    has raises `KeyError` listing the object layers. Any other key raises.
11. **`mount` takes no `slots:`.** A scene that passes one gets Ruby's
    `ArgumentError` for an unknown keyword.

### Tests

- `spec/rgame/engine/map_builder_spec.rb`: rules 1–4, from `.tmx` strings with a
  tileset, through `TiledFixture`.
- `spec/rgame/engine/tile_map_spec.rb`: rule 8.
- `spec/rgame/engine/components/tile_world_spec.rb`: `objects`.
- `spec/rgame/engine/tile_map_layer_spec.rb`: rules 5–7 and 9–11. The examples
  that name slots (`boats:`, `shadows:`, `sky:`) are rewritten against object
  layers placed where those slots were.
- **The caller that uses all of it**, in `tile_map_layer_spec.rb`: a map whose
  *Top Down* object layer is marked `actors` holds a tree placed as a tile
  object of class `tree`, under a tile layer marked `above`. The scene adds a
  hero to `places[:actors]` and draws through two `WorldView`s side by side.
  In both views, the hero draws before the tree while standing north of the
  tree's origin, and after it once south of it. Both draw under the `above`
  layer.

### Verify

- `rake spec`, `rake spec:core`, `rake drive:allocations`.
- **Every driven project reports the same under `--seed 1 --texts`, before and
  after, except for its `world` band count.** Each object layer's node calls
  `layered` once per drawn viewport. Where it replaces a slot node, the count
  stays; where it does not, it grows by one. So the count grows by one per frame
  and viewport for `collision_tiles`, `scroll_map`, `cutscene`, `pathfinding`,
  `jump_topdown`, `pits`, `moving_platforms`, topdownplatformer and tiled_world,
  and stays for `doors` and adventure. The landed note names any other difference.
- **`tour.tmx` from the authoring branch mounts headless.** Its two tile objects
  build plain nodes with a `MapTile`, and nothing else builds.
- `docs/api/tile_maps.md` rewrites "Building nodes from objects" for the new
  path. That covers the class rule, data classes, the `@param` tags (linking
  `internals.md` for the table), tile objects, the `actors` mark, hidden layers
  and objects, `route:` and `name:`, `map_object_id` and `Components::Fact`, and
  `places[name]`. `MapObjects` keeps a short section
  until step 7 removes it. `docs/api/scene_graph.md` and `internals.md` follow.
- `CHANGELOG.md` has an Added entry for map-built nodes. The Unreleased entry
  on `slots:` becomes one on `places[name]`, since `slots:` never shipped.

---

## Step 7 — every map and project on the new path

Step 6 built the path, and nothing uses it yet. This step renames the classes in
four maps, tags the constructors they name, and deletes `MapObjects`. Its
sub-steps follow the projects, because two games share `garden.tmx` and must
move together.

### Sub-steps

- **7a** — the doors. `examples/doors` and adventure get a town map of their own
  with the gate (decision 15), `town_with_gate.tmx`. `town.tmx` loses its object
  layer. Both games define `Door` and `Warp`, and `garden.tmx` and the new map
  name them.
- **7b** — `examples/moving_platforms`: `Raft` is tagged, and `platforms.tmx`
  names it, sized by `deck_width` and `deck_height` (decision 18).
- **7c** — topdownplatformer. `course.tmx` names `Raft`, `Flag`, `Crate` and
  `Walker`, moves its `platforms` layer under `spawns`, and marks `spawns` as
  `actors`.
- **7d** — `MapObjects` goes: the class, its spec, its documentation, and its
  Unreleased `CHANGELOG.md` entry.

### Shape

Game code, in each game's own module:

```ruby
# 7a — DoorsExample and Adventure alike. Adventure's also takes name:, the object's name, and draws it above the door.
class Door < Engine::Node2D
  COLOR = Util::Color.new(150, 104, 56)

  # A door built from a map. A hero's feet touching its box ask the world's
  # rooms for a move, and the door stays where it is.
  #
  # @param to [Symbol] the room the door leads to
  # @param entrance [String] the entrance in that room where the hero arrives
  # @param party [Boolean] whether it moves every hero the world holds, rather than the one who touched it
  def initialize(to:, entrance:, party: false, **)
    super(**)
    @to = to
    @entrance = entrance
    @party = party
    add_component(Components::BoxCollider.new(width:, height:, offset_x: -width / 2.0, offset_y: -height,
                                              layer: :door))
    add_component(Components::Collectable.new(by: :hero, free: false)).on_collected { move(it.node) }
  end

  def _enter_tree = @rooms = system!(Engine::Scene::Rooms)

  def _draw(renderer, _view) = renderer.rect(-width / 2.0, -height, width, height, color: self.class::COLOR)

  private

  def destination = @to

  def move(hero) = @rooms.move(@party ? @rooms.node.heroes : hero, to: destination, entrance: @entrance)
end

# A warp pad: a door into the room it stands in. A room is its own scene.
class Warp < Door
  COLOR = Util::Color.new(150, 96, 210, 200)

  # @param entrance [String] the entrance in this room where the hero arrives
  def initialize(entrance:, **) = super(to: nil, entrance:, **)

  private

  def destination = scene.name
end

# 7b and 7c — Raft, in each game. `width:` and `height:` go; the builder passes route: (step 5).
# @param deck_width [Integer] the raft's width in pixels, a multiple of 16
# @param deck_height [Integer] its height in pixels, a multiple of 16
def initialize(route:, deck_width:, deck_height:, **)
  super(**)
  # ... the BoxCollider, Platform and PathFollow as today, sized by the deck

# 7c — Flag takes name: as today, and the builder passes the object's name (step 5)
def initialize(name:, **)
  super(**)
  @name = name
  # ... other.node.reach(@name)

# 7c — the course keeps no slots and builds nothing itself
@actors = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new))[:actors]   # the spawns layer
```

What the maps hold afterwards:

| Map | Classes that build | Change |
|---|---|---|
| `town.tmx` | none | its `doors` object layer goes; its tile layers stay |
| `town_with_gate.tmx` | `Door` ×1 | a copy of `town.tmx`, with `door` renamed |
| `garden.tmx` | `Door` ×2, `Warp` ×2 | renamed from `door` and `warp` |
| `platforms.tmx` | `Raft` ×1 | renamed from `platform`; `width` and `height` become `deck_width` and `deck_height` |
| `course.tmx` | `Raft` ×2, `Flag` ×3, `Crate`, `Walker` | renamed, as above; `platforms` under `spawns`; `spawns` marked `actors` |

`course.tmx` has to reorder. Without it, the flags, the crate and the walker
would build in `spawns`, under the rafts in `platforms`, and stop sorting with
the heroes. The walker rides the ring, so it would disappear under it.
`platforms.tmx` needs no reorder: its hero goes over every layer, as today.

### The rules the tests pin

1. **`town_with_gate.tmx` and `town.tmx` have the same tile layers**, cell for
   cell, so an edit to one cannot silently leave the other behind.
2. **`town.tmx` holds no capitalised class**, so the five examples that mount it
   and define no `Door` keep mounting it.
3. **Every door and warp names an entrance on the map its room is built from**,
   and every entrance stays off every door's box, as today, with the classes
   `Door` and `Warp` and the rooms' own town.
4. **Each raft stops short of its bank by less than a hop**, as today, reading
   `deck_width`.
5. **`course.tmx`'s layer marked `actors` is above its `platforms` layer**, so a
   later edit in Tiled cannot put the heroes under the rafts unnoticed.

### Tests

- `spec/example_assets_spec.rb`: rules 1–5, with the doors describe moved onto
  `town_with_gate.tmx` and the classes `Door` and `Warp`.
- `spec/rgame/engine/map_objects_spec.rb` goes in 7d.

No spec loads an example's or a test project's classes, since each file starts
its game when required. The drive runs below are what show that each class
resolves under its scene, and builds with the settings its map gives it.

### Verify

- `rake spec`, `rake spec:core`, `rake drive:allocations`.
- **Driven with `--seed 1 --texts` at the end of step 6 and after 7d**, at the
  lengths step 2 used: `doors`, adventure for 1640 ticks under seeds 1 and
  4242, `moving_platforms`, topdownplatformer for 1654 ticks under seeds 1 and
  3, and the five examples that mount `town.tmx`. The scenes entered, the sounds
  played and the texts drawn match.
- **Each draw lands where it landed**, compared by a recorder that adds up the
  translates and scales around each draw, as the y-sort plan's comparison did.
  Only the doors move their origin, to the bottom centre of their box.
- **The five `town.tmx` examples report their `world` band count one lower** per
  frame and viewport than at the end of step 6, since the map lost its object
  layer. That undoes step 6's growth for them.
- `grep -rn MapObjects lib examples test_projects spec docs/api` finds nothing.
  `docs/api/tile_maps.md`, `examples.md` and `internals.md` describe the new
  path, and so does the header of `examples/doors/main.rb`. `CHANGELOG.md` has
  no `MapObjects` entry, since none shipped.

---

## Step 8 — Tiled's custom types, written from Ruby *(rough)*

`RGame::Engine::MapTypes.write(path)` writes a Tiled class into a
`.tiled-project` for each `Node2D` subclass whose tags make any keyword
settable. It replaces the classes it owns and keeps the designer's. An Array of
Symbols becomes a Tiled enum.

To settle in the re-plan: open questions 2 and 5, where it runs and what default
a member shows. Which classes it writes, now that open question 6 resolves a
name from the scene's class: a project's maps may serve two games, as
`garden.tmx` serves `DoorsExample` and `Adventure`, and each game has its own
`Door` with its own tags. Whether the generated project gains the task, and
`spec/rgame/cli/generated_project_spec.rb` with it. Whether its `.gitignore`
leaves out `*.tiled-session`, as this repository's does since step 0.

## Step 9 — the maps checked, and the level played *(rough)*

Two halves, as [map-requirements.md](map-requirements.md#the-check-and-the-example-that-plays-the-map)
sketches:

- `spec/example_assets_spec.rb` checks `tour.tmx` against R1–R23, and its
  gzip and infinite twins.
- A second map, designed as a level, is played by a new example with a drive
  script. Its requirements are written at this step's re-plan, against the
  exported types: trees as tile objects in the marked layer, a chest whose state
  survives leaving the room, a value a node passes on to its component.

This is the first driven project with a tile object, so its
`rake drive:allocations` budget is where `map_tile` is measured in a whole game.
R19's comparison with Tiled's export, and R21's turned tile object, check
step 4's box draw by eye. `puzzle.tmx`, which has no object layer, covers the
place `mount` leaves for the actors on a map with no mark.

---

## Step 10 — fold the plan back and delete it

- **`docs/api/tile_maps.md`** says what a map builds and how: the class rule,
  data classes, the `@param` tags, tile objects, the `actors`
  mark, hidden layers and objects, `route:` and `name:`, `map_object_id` and
  `Components::Fact`, and `places[name]`. Step 6 rewrote
  "Building nodes from objects"; this step checks it against the code.
- **`docs/api/components.md`** covers `Fact`, `MapTile` and `RandomSource`.
- **`docs/api/scene_graph.md`** covers what `mount` builds for an object layer.
- **`docs/plans/possible-todos.md`**:
  - "Platforms as Tiled tile objects" is answered, or its trigger updated.
  - Open questions still open move here.
  - So do the plan's "does not deliver" items that have a trigger.
- Run [learn-from-mistakes](../../../.claude/skills/learn-from-mistakes/SKILL.md)
  over every step's "What proved wrong".
- Delete `docs/plans/object-layers/`.

### Verify

`CHANGELOG.md` covers everything steps 1–9 shipped, per
[update-changelog](../../../.claude/skills/update-changelog/SKILL.md): what the
Tiled parser gained, the random source, map-built nodes and `places[name]`, the
`@param` convention, `map_tile` and `MapTile`, and `Components::Fact` with
`map_object_id`. It has no entry for `MapObjects`, `slots:`, `map_object:` or
`fact_key:`, which never shipped. `rake` passes. `docs/plans/object-layers/` is gone,
and `grep -r object-layers docs/ .claude/` finds nothing.
