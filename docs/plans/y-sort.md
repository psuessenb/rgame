# Y-sort

**Status: step 1 is implemented.** Four steps. Each is one branch and one pull
request, and its sub-steps are one commit each. **Steps 1 and 2 are
detailed.** Step 3 is rough and gets re-planned once step 2 lands. Step 4 folds
the plan back and deletes it.

## Verdict

**Y-sort is a `y_sort` flag on a `Node2D` container.** A sorted container draws
its children by `z`, then by where each one stands, then by the order they were
added. A child stands at the bottom edge of its `BoxCollider` box, or at its
origin if it has none. `TileMapLayer.mount` sorts every gap it leaves, so a
top-down map sorts its actors without being asked.

**The sort orders drawing and nothing else.** A sorted container keeps a second
array of its children for `draw`. `control` and `update` keep visiting them in
today's order, so a run does not depend on how often it was drawn.

**Then the two sprite components agree on an anchor.** `Sprite` and
`AnimatedSprite` both take `anchor:`, and both default to the feet. The
top-down projects lose their hand-written offsets, and every feet box stays
where it was.

**Tiles do not sort with actors.** The `above` canopy layer stays the answer. A
rough third step turns Tiled tile objects into nodes, and those sort like
actors.

## Goal

A character in a top-down scene draws behind whatever stands in front of them
and in front of whatever stands behind them. The game adds no code for it.

## Hard constraints

1. **The engine layer may not name `RGame::Core`.** Step 3's single-tile draw is
   a renderer method, called by name.
2. **A per-frame path allocates nothing.** The sort runs every frame, and
   `rake drive:allocations` decides whether it allocates.
3. **`draw` renders state.** Sorting for a draw may not change the order
   `control` and `update` visit children. `needs_redraw?` can skip a draw, and
   the catch-up loop can run several updates between two draws. If the draw
   reordered the update, two machines would play the same inputs differently.
4. **Every feature works with two players.** Each viewport draws the same
   order. `test_projects/adventure` puts two heroes in one sorted gap.
5. **UI never y-sorts.** Only a game's own `y_sort = true` and the gaps `mount`
   leaves are sorted.

## Decisions already taken

These were settled in conversation and in one round of questions. They are not
reopened inside this plan.

1. **Y-sort is opt-in, per container.** Its children are sorted by y, and
   nothing outside it changes. A shadow under its character, a sword in a hand
   and a particle burst are ordered by structure, not by position. A side-view
   game never wants y-sort.
2. **UI never y-sorts.** UI order is structural: a dropdown opens over the
   buttons below it. UI lives under `PlayerLayer` in the `:hud` band, so an
   opt-in on a world container never reaches it.
3. **A subtree sorts as one unit.** A hero, their shadow and their label sort
   together, by the hero's footing. The sibling `z` sort already works this way,
   and so do Godot and Unity (see [Prior art](#prior-art)).
4. **A child stands at the bottom of its `BoxCollider` box, or at its origin.**
   A feet box and a y-sort answer the same question: where does this node stand.
   `Navigator` already asks the same component: the node's `BoxCollider`, or its
   origin on a node with none. This rule is right
   today for every hero (`FeetCollider`) and for the adventure's chest, crate
   and lever (a box the size of the body), whatever the sprites do. The
   alternatives, the origin and a per-node offset, are under
   [Considered and rejected](#considered-and-rejected).
5. **The key is `z`, then footing, then the order added.** `z` keeps its meaning,
   above its siblings, so an overlay in a sorted gap stays on top with `z: 1`.
   Godot sorts the same way: "Nodes sort relative to each other only if they
   are on the same `z_index`."
6. **The opt-in is a `Node2D` attribute, and `mount` sorts its gaps.** All seven
   projects that mount a gap are top-down. A side-view game on a Tiled map
   passes `y_sort: false`.
7. **The sort is an in-place insertion sort.** See
   [What was measured](#what-was-measured-before-planning).
8. **The sprites agree on `anchor:`, and both default to `:bottom`.** This is
   step 2, after the sort, so the sort ships even if the sweep turns up
   something unexpected. With `:bottom` as the default, a top-down game is right
   without passing anything. The ship that forgets `anchor: :center` spins about
   its tail, which shows at once. A wrong sort point would not.
9. **Tiles keep the canopy layer.** Tiled tile objects become sorted nodes in a
   rough step 3. Sorting tile layers row by row goes to
   `docs/plans/possible-todos.md` with a trigger.
10. **This is a plan of its own**, independent of the 0.5.0 roadmap. Y-sort
    touches none of that roadmap's remaining steps.

## Open questions

None blocks step 1 or step 2.

1. **A node with a feet box and a second box.** `get_component(BoxCollider)`
   raises when two components match, so such a node raises at its first sorted
   draw. No node in the repository has two today. The likely answer is that a
   `FeetCollider` wins. *Waits on the first game that needs a hitbox beside a
   feet box.*
2. **A sorted container inside a sorted container.** Under decision 3 the inner
   one sorts as one unit at its own footing. Merging the two into one sort is
   the alternative. *Waits on a scene that needs it.*
3. **How step 3 draws one tile.** The renderer has `tilemap` for a whole layer,
   and no call for one tile of a tileset. *Waits on step 2; settled in step 3's
   re-plan.*

## What was measured before planning

At `ff9122f`, on Ruby 4.0.5.

| What | Result |
|---|---|
| The children `control`, `update` and `draw` walk | all three walk `rgame_children_in_order`, one array that the `z` sort reorders in place (`node2d.rb` lines 429, 440, 569) |
| Paths that remove a child | `remove_node` only; `sweep_freed` calls it |
| `sort!` with a block, every child moving up to 1.5px a frame | 2.4, 15.5 and 83.3 µs a frame for 10, 50 and 200 children; allocates on every call |
| An insertion sort, same input | 1.7, 8.9 and 41.1 µs; allocates nothing |
| The insertion sort with the real key: `Node2D`s, half of them boxed | 2.4, 14.3 and 62.9 µs; under 0.03 objects a frame, the timing harness included |
| Projects that mount an `:actors` gap | 7, all top-down |
| Nodes in a gap that do not stand on the ground | `examples/pathfinding`'s `Route` and `Cursor`, `examples/block_puzzle`'s `Square`, all without a `z`; `test_projects/adventure`'s `Sparkles`, at `z: 1` |
| Nodes that carry two `BoxCollider`s | 0 |
| `Sprite.new` outside the specs | 5, and all rotate: the asteroids ship, rocks and bullets, and `examples/sprite` |
| `AnimatedSprite.new` in `examples/` and `test_projects/` | 11, and all draw a character walking on the ground |
| Hand-written distances from a sprite's top-left to its feet | 4 `CAMERA_OFFSET_X/Y` pairs and 1 `FEET_CENTRE_X/Y` pair, in 5 files |
| Clamps that assume a top-left origin | 4 pairs, in `walk`, `split_screen`, `game_menu` and `input_glyphs` |
| `CollisionBox.bottom_anchored` | 3 in `lib/`, 3 in `spec/`, 4 in `docs/api/` |

200 walking actors cost 63 µs a frame, 0.4% of a 60fps frame. A second viewport
sorts again, but the order is already right, so it only compares.

## What already resembles this

**Reuse it.**

- `Node2D#rgame_sort_children` and `rgame_sibling_order`: the sibling order and
  its tie-break.
- `get_component(BoxCollider)`, which is how `Navigator` finds where a node
  stands.
- `FakeRenderer`'s recorded sort keys and `node2d_draw_order_spec.rb`, which
  assert draw order headless.
- `TileMapLayer.mount`'s gaps, which are the containers that get sorted.

**Extend or generalise it.**

- **The sibling `z` sort grows a key.** It answers the question y-sort asks, in
  what order do siblings draw, about a different property. One sort with three
  keys, not a second sorting system.
- **The two sprite anchors become one keyword.** Both components answer "where
  does the picture sit against the origin", differently and without saying so.
- **`FeetCollider` sits on the origin** instead of deriving its box from the
  sprite's size, once the origin is the feet.
- **`Culling`** gets the footprint from the anchor, in one place for both
  components.

**Genuinely new.**

- **A second order of a node's children.** Nothing keeps one today. Hard
  constraint 3 needs it: the draw may not reorder the update.
- **A draw of one tile**, in step 3.

## Prior art

**Godot 4** turns y-sort on per node with
[`CanvasItem.y_sort_enabled`](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-y-sort-enabled):
"this and child CanvasItem nodes with a higher Y position are rendered in front
of nodes with a lower Y position." A child without y-sort keeps its subtree
together: its children "render together on the same Y position" as it. Nodes
sort by y only within one `z_index`. A node sorts on its own position. A sprite
moves its picture against that position with
[`Sprite2D.centered`](https://docs.godotengine.org/en/stable/classes/class_sprite2d.html)
(default `true`) and `offset`. Tiles get a per-tile point instead,
[`TileData.y_sort_origin`](https://docs.godotengine.org/en/stable/classes/class_tiledata.html).
Godot 3 had a node class for it,
[`YSort`](https://docs.godotengine.org/en/3.5/classes/class_ysort.html).

**Unity** sorts 2D renderers by
[sorting layer and order in layer first](https://docs.unity3d.com/Manual/2d-renderer-sorting.html),
and only then by distance along a sort axis. A top-down game sets that axis to
y. A sprite sorts on
[`SpriteSortPoint`](https://docs.unity3d.com/ScriptReference/SpriteSortPoint.html)
`Center` or `Pivot`, and the pivot is set on the sprite asset. A
[Sorting Group](https://docs.unity3d.com/Manual/sprite/sorting-group/use-sorting-groups.html)
keeps a hierarchy together: "A nested sorting group is sorted first, then sorted
as a single item within the parent sorting group."

**What they agree on.** Y-sort is scoped: to a node in Godot, and to a sorting
layer and order in Unity. An explicit layer beats position. A group sorts as
one item.

**What none of them gives us.** Each sorts on a point the author sets: a node's
position, a sprite's pivot, a tile's `y_sort_origin`. None derives the point
from the collision shape. rgame can, because every top-down actor already
carries a feet box, and the feet box is exactly where the actor stands.

## Considered and rejected

- **Sorting `@children` in place, the way `z` works.** It is one array and no
  new state. But `control` and `update` walk the same array, so an actor walking
  north would change who updates first. The draw would then decide the update,
  which breaks hard constraint 3.
- **Sorting in `update` instead of `draw`.** That keeps a run deterministic,
  but collisions would resolve in order of y. A crate and the hero pushing it
  would swap turns as they cross. A paused world moved by a cutscene would also
  draw in a stale order, since a paused node never updates.
- **`sort!` with a block.** It allocates on every call and is twice as slow on
  the nearly sorted order that consecutive frames give it.
- **The node's origin as the sort point.** Godot and Unity do this. Here every
  hero's origin is at the top-left of their sprite, and nodes that draw by hand
  keep whatever origin their author chose. "Put the origin at the feet" would be
  a rule someone has to remember.
- **A per-node sort offset**, such as `sort_offset_y:`. It is explicit, but it is
  a number every author has to supply, and it is wrong until they do.
- **A `YSort` class.** An existing node could not become one, and it would be a
  class for one flag.
- **Y-sort for every node.** Most order is structural (decision 1).
- **Tile layers sorting row by row with the actors,** as Godot 4's
  `TileMapLayer` does. `Core::TileMapRenderer` would draw a row at a time,
  interleaved with nodes. It waits for a map that the canopy layer and tile
  objects cannot express.

## What this does not deliver

- Tiles in a tile layer sorting with actors.
- A sort along any axis but y, such as an isometric diagonal.
- Nested sorted containers merging into one sort.
- A UI order such as "the item being dragged draws on top".
- Characters that stand on a Tiled point. Step 2 keeps every character where it
  stood before.

---

## Roadmap

### Dependency shape

```
1 y-sort ─→ 2 sprite anchors ─→ 3 tile objects (rough) ─→ 4 fold back
```

Step 3 comes after step 2 because a tile object anchors at its feet, as step 2
makes the sprites do.

> **Only drawing follows the sort.** `control` and `update` visit a sorted
> node's children in the order they would without the sort, however those
> children move and however often the node is drawn.

Each detailed step is worth landing alone:

| Step | Defect it closes |
|---|---|
| 1 | Overlapping actors draw in the order they were added |
| 2 | Swapping a `Sprite` for an `AnimatedSprite` moves the picture by half its size; top-down games write their feet offsets by hand |

### Step 1 — y-sorted children *(`Node2D`, pure)*

The sort itself, and the gaps that use it. It comes first because nothing else
in this plan is visible without it.

#### 1a — where a child stands

A node answers its footing: the bottom of its `BoxCollider` box in its parent's
space, or its `y`. It finds the collider once, and looks again when a component
is added or removed. `elevation` plays no part, so a character mid-hop sorts by
the spot they left.

```ruby
# Node2D
def add_component(component, as: nil)
  # ...as today, then:
  @footing_known = false
end

protected

# hot-path
def rgame_footing_y
  rgame_find_footing unless @footing_known
  return @rel_y unless @footing

  box = @footing.box
  @rel_y + box.offset_y + box.height
end

private

def rgame_find_footing
  @footing_known = true
  @footing = get_component(Components::BoxCollider)
end
```

`remove_component` clears `@footing_known` the same way.

#### 1b — `y_sort`, and a draw order of its own

A sorted node keeps `@draw_order`, a second array of its children. `add_node`
and `remove_node` keep it in step, and `draw_children` sorts it and walks it.
`control` and `update` still walk `rgame_children_in_order`.

```ruby
# Node2D

# Whether this node draws its children by where they stand ...
attr_reader :y_sort

def y_sort=(value)
  @y_sort = value
  @draw_order = value ? @children.dup : nil
end

def initialize(x: 0, y: 0, z: 0, angle: 0, width: 0, height: 0, input_owner: nil,
               band: nil, y_sort: false)
  # ...as today, then:
  @footing = nil
  @footing_known = false
  self.y_sort = y_sort
end

# add_node:    @draw_order&.push(node)
# remove_node: @draw_order&.delete(node)

# hot-path
def draw_children(renderer, view)
  rgame_children_in_draw_order.each { it.draw(renderer, view) }
end

private

# hot-path
def rgame_children_in_draw_order
  return rgame_children_in_order unless @draw_order

  rgame_sort_by_footing(@draw_order)
  @draw_order
end

# hot-path
def rgame_sort_by_footing(order)
  i = 1
  while i < order.size
    node = order[i]
    j = i
    while j.positive? && rgame_draws_after?(order[j - 1], node)
      order[j] = order[j - 1]
      j -= 1
    end
    order[j] = node
    i += 1
  end
end

# hot-path
def rgame_draws_after?(one, other)
  return one.z > other.z unless one.z == other.z

  one_y = one.rgame_footing_y
  other_y = other.rgame_footing_y
  return one_y > other_y unless one_y == other_y

  one.rgame_sibling_order > other.rgame_sibling_order
end
```

Every new non-public method carries `rgame_`, so `Engine::SealedPrivates` seals
it. `draw_children` stays a seam.

#### 1c — `mount` sorts its gaps, and the projects that relied on add order

```ruby
def self.mount(parent, gaps: { actors: nil }, y_sort: true)
  # ...
  under.each { |name, layer| nodes[name] = parent.add_node(Node2D.new(z: z += 1, y_sort:)) if layer == index }
```

Three nodes relied on the order they were added in. Each gets a `z` that says
what that order meant:

| Node | Today | After |
|---|---|---|
| `examples/pathfinding` `Cursor` | added after the hero, so on top | `z: 1` |
| `examples/pathfinding` `Route` | added before the hero, so under | `z: -1` |
| `examples/block_puzzle` `Square` | added before the blocks, so under | `z: -1`: a floor marking must not draw over a block sliding onto it |

`test_projects/adventure`'s `Sparkles` already has `z: 1`.

#### Rules the tests pin

1. A sorted node draws a child standing further down after a child standing
   further up.
2. A higher `z` draws later, whatever the footing.
3. Equal `z` and equal footing draw in the order added, and the order holds
   frame after frame.
4. A child with a `BoxCollider` stands at `y + offset_y + height` of its box.
   `elevation` does not move it.
5. A child with no `BoxCollider` stands at its `y`.
6. Adding or removing a component changes where the child stands from the next
   draw on.
7. `control` and `update` visit the children in the same order with and without
   `y_sort`, whatever their positions. This is the invariant.
8. A child's subtree draws as one unit, at the child's footing.
9. Drawing twice in one frame, as two viewports do, draws the same order twice.
10. `y_sort = false` returns to `z` order. `y_sort = true` after children were
    added sorts all of them.
11. Sorting allocates nothing once warm.
12. `mount`'s gaps are sorted, and `mount(..., y_sort: false)` leaves them
    unsorted.

#### Tests

- `spec/rgame/engine/node2d_draw_order_spec.rb`, a new `describe 'a y-sorted
  parent'`: rules 1–5, 8–10. It also holds the one case that uses everything at
  once: in one sorted gap drawn through two viewports, a hero with a
  `FeetCollider` mid-`Hop`, a crate with a `BoxCollider` and a coin with none.
- `spec/rgame/engine/node2d_spec.rb`: rules 6 and 7.
- An allocation example beside `node2d_control_allocation_spec.rb`: rule 11,
  with 50 children moving every frame.
- `spec/rgame/engine/tile_map_layer_spec.rb`: rule 12.

#### Verify

A hero in a sorted gap draws behind a node they stand behind. The update order
does not change. Nothing allocates.

- `rake spec` and `rake drive:allocations`.
- `ruby tools/drive_test_project.rb` for `examples/pathfinding`,
  `examples/block_puzzle` and `test_projects/adventure`, each reporting what it
  reported before.
- By eye: walk round the spiky ball in `examples/collision_tiles`, and let two
  heroes cross in `test_projects/adventure`.
- `docs/api/scene_graph.md` (draw order), `docs/api/tile_maps.md` and every
  other page that mentions `mount` say what the code now does, per
  [write-docs](../../.claude/skills/write-docs/SKILL.md). `CHANGELOG.md` has an
  entry.

**Landed.** `Node2D` takes `y_sort:` and answers `y_sort` and `y_sort=`. A
sorted node keeps a second array of its children for drawing and
insertion-sorts it on each draw by `z`, footing, then the order added.
`TileMapLayer.mount` sorts its gaps unless passed `y_sort: false`. It landed on
the `y-sort` branch in two commits, after the plan's own commit.

- `rake spec`: 3839 examples, 0 failures, 20 of them new. `rake spec:core`:
  517, 0 failures. `make test`: 412 checks, 0 failures. `rake drive:allocations`:
  every project within budget.
- Rule 7, the invariant, is pinned by `node2d_spec.rb`. Pointing the draw order
  at `@children` itself instead of a copy fails all three new examples there.
- Seeded `--texts` drives of all 12 runs that mount a gap, before and after:
  every draw count, text count and sound is the same. `examples/pathfinding` and
  `examples/block_puzzle` are byte-identical, so the three `z`s keep the order
  they replaced. The other ten differ only in order: the first or last call
  falls on a different actor, and rows with equal counts swap places in the
  listing. In `test_projects/adventure` the lever's label now draws before the
  chest's.
- Allocations against `ff9122f`, same projects: equal, except
  `examples/block_puzzle` at 3.3 objects a second instead of 3.1. The two extra
  objects are `IMEMO/callcache` at the comparison in `rgame_draws_after?`: Ruby's
  inline cache taking a new receiver class the first time a block and the hero
  meet after warm-up. It happens once per pair of classes, not every frame.
- **1a and 1b are one commit.** Footing has no caller and no public way to test
  before the sort exists, so a 1a commit alone would have been untested code.
- **A `FeetCollider` in a sorted parent needs its node's size before the first
  draw.** Its `box` raises on a 0×0 node, and the sort reads `box`. In a game
  the sprite sets the size on attach, before any draw. A spec that draws a tree
  it never entered has to give the node a size. Step 2 removes the guard.
- **Not checked by eye.** Walking round the spiky ball in
  `examples/collision_tiles` and two heroes crossing in
  `test_projects/adventure` still need someone at a window.
- Documented in `docs/api/scene_graph.md` (a new "Y-sort" section),
  `drawing.md` (the slot step), `components.md` (`mount`'s gaps) and
  `tile_maps.md` (tiles do not sort with actors). `CHANGELOG.md` has one entry
  under Added.

### Step 2 — the sprites agree on an anchor

Separate from step 1 so the sort ships even if this sweep turns up something
unexpected. It flips a default that seven projects rely on.

#### 2a — `anchor:` on both, defaults unchanged

Both components take `anchor:` with the same three values. Nothing moves yet:
`Sprite` defaults to `:center` and `AnimatedSprite` to `:top_left`. `Culling`
takes the footprint from the anchor for both.

```ruby
module RGame
  module Engine
    # Where a picture sits against its node's origin ...
    module Anchor
      NAMES = %i[center bottom top_left].freeze

      def self.check!(anchor) = ...   # raises ArgumentError naming NAMES

      # The picture's left and top edges, measured from the origin.
      # hot-path
      def self.left(anchor, width) = ...
      # hot-path
      def self.top(anchor, height) = ...
    end
  end
end

Components::Sprite.new(id:, scale: 1.0, z: 0, anchor: :center)
Components::AnimatedSprite.new(sheet:, z: 0, anchor: :top_left)
```

Negative zero allocates on this Ruby. `left` and `top` return an Integer `0`
where a size of zero would give `-0.0`.

#### 2b — both default to `:bottom`, and `FeetCollider` sits on the origin

With the origin at the feet, a feet box no longer needs the sprite's size.
`FeetCollider` loses its guard against reading before the node has a size,
since there is nothing left to guard. `CollisionBox.bottom_anchored` has no
caller left and goes.

```ruby
class FeetCollider < BoxCollider
  def initialize(width:, height:, layer: :default)
    super(width:, height:, offset_x: -width / 2.0, offset_y: -height, layer:)
  end
end
```

The asteroids ship, rocks and bullets and `examples/sprite` pass
`anchor: :center`.

#### 2c — the examples, each feet box where it was

`collision_tiles`, `jump_topdown`, `pathfinding`, `walk`, `split_screen`,
`collectables`, `game_menu` and `input_glyphs`. Each start position, camera
offset, clamp and hand-drawn decoration moves by the sprite's offset. The
feet box, the picture and the camera all stay where they were in the world.
`FEET_CENTRE_X/Y` and most of the `CAMERA_OFFSET` pairs come out near zero.

#### 2d — the test projects, the same way

`test_projects/adventure`'s hero and `test_projects/tiled_world`'s walkers.

#### Rules the tests pin

1. `:center` puts the picture's centre on the origin, `:bottom` its bottom
   centre, and `:top_left` its top-left corner.
2. A `Sprite` and an `AnimatedSprite` with the same anchor and size cover the
   same pixels.
3. Rotation and scale still turn about the origin, so `:center` spins in place.
4. `elevation` lifts the picture for every anchor.
5. Culling measures the footprint where the anchor put it.
6. An unknown anchor raises at construction and names the three.
7. A `FeetCollider`'s box is centred across the origin with its bottom edge on
   it, and can be read before the node enters the tree.

#### Tests

`spec/rgame/engine/components/sprite_spec.rb`, `animated_sprite_spec.rb` and
`feet_collider_spec.rb`, `spec/rgame/engine/culling_spec.rb`, and
`collision_box_spec.rb` and `box_collider_spec.rb` without their
`bottom_anchored` examples.

#### Verify

Every project 2b, 2c and 2d touch reports exactly what it reported before the
step. Its feet boxes, pictures and cameras are where they were, so a seeded run
draws and collides the same. Record each report on `main` before the step
starts, then compare:

```
ruby tools/drive_test_project.rb examples/collision_tiles/main.rb --seed 1 --texts > before.txt
# ...after the step:
ruby tools/drive_test_project.rb examples/collision_tiles/main.rb --seed 1 --texts | diff before.txt -
```

Also `rake spec` and `rake drive:allocations`. `docs/api/components.md`
(`Sprite`, `AnimatedSprite`, `FeetCollider`, `CameraFollow`) and
`docs/api/toolbox.md` (`CollisionBox`) say what the code now does. The
`CHANGELOG.md` entry says the default moved.

### Step 3 — Tiled tile objects as sorted nodes *(rough)*

A designer places a tree as a tile object, and it sorts like an actor. `mount`
builds a node for each tile object in an object layer and adds it to the gap
above that layer. The node draws its tile anchored at the feet, as step 2 made
the sprites do. `MapObject` already carries the tile and its top-left corner,
and an object layer gets no node today.

This needs a renderer call that draws one tile of a tileset, which is Core work
the engine reaches by name (hard constraint 1). `test_projects/tiled_world`
gains a tree placed as a tile object, and the drive script walks behind it.

Re-plan after step 2 lands.

### Step 4 — fold the plan back and delete it

- Read `docs/api/` for anything this plan says that the pages do not: the
  footing rule, the invariant, the anchor values. Add what is missing.
- Move row-by-row tile sorting to `docs/plans/possible-todos.md`. Its trigger is
  a map whose tall scenery neither the canopy layer nor tile objects can
  express, such as a wall a character walks both in front of and behind. Move
  any open question still open.
- Delete `docs/plans/y-sort.md`.

#### Verify

`CHANGELOG.md` covers everything steps 1–3 shipped, per
[update-changelog](../../.claude/skills/update-changelog/SKILL.md). `rake spec`
passes, including the docs link checks. `docs/plans/y-sort.md` is gone.
