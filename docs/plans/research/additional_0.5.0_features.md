# Additional features for 0.5.0

Research for five features that join 0.5.0 once the object-layers and smooth-art
plans finish. It is not a plan: it has no roadmap. It records what the code does
today, what each feature resembles, the traps found while reading, and the
questions a plan has to settle first. When a plan takes these features up, it
moves what it uses and deletes this file.

Everything here was read or measured at commit `99442bf`, on Ruby 4.0.5.

## Verdict

**All five fit 0.5.0, and none needs a GL loader or a new dependency.** Four are
small: the multiply blend, the sprite colour, the pushed platform and the respawn
point per room. One needs a design decision before any code: where a node's
facing lives.

**Compatibility constrains two of the five.** `Interactor`, `Respawn`, `Rooms`,
`Pushable` and `Platform` do not exist at the `v0.4.0` tag, so 0.5.0 is their
first release and they may take whatever shape works best. `Targeting` and
`Renderer#sprite` shipped in 0.4.0. Every change proposed to them below is an
addition.

**One finding corrects the todo list:** the multiply blend function in
`possible-todos.md` is wrong since premultiplied alpha landed. It would draw every
transparent pixel black.

## The request

As it arrived:

> * A raft you push carries nobody, because Pushable replaces the mover's update.
>   That rules out raft-pushing puzzles until you work around it.
> * Facing-aware interaction. Targeting::POLICIES is still only :nearest, measured
>   from the node's origin, so two signs side by side can pick the wrong one.
> * Multiply blend for night tints and shadows. possible-todos.md says it's small:
>   one GL 1.0 blend function, no loader.
> * Respawn resetting when a room move lands
> * Tinting a character. renderer.sprite still has no color

## What was measured

| | |
|---|---|
| Projects putting `Pushable` and `Platform` on one node | 0. `Pushable` is in `block_puzzle`, `push_pull`, `adventure` and `topdownplatformer`; `Platform` in `moving_platforms` and `topdownplatformer`'s raft |
| Projects mounting `Respawn` beside `Rooms` | 0. `Respawn` is in `moving_platforms`, `pits` and `topdownplatformer`; `Rooms` in `doors` and `adventure` |
| Subclasses of `Targeting` | 2: `Interactor` and `Grab` |
| Blend modes | 2, `:alpha` and `:add` |
| Places that use `:multiply` as the example of an unknown mode | 2: `spec/support/shared_examples/a_renderer.rb:756`, `docs/api/values.md:298` |
| Specs tying `Util::Blend::MODES` to the C enum | 0 |
| Check tests naming `RGAME_BLEND` | `test_draw_queue.c` 18 mentions, `test_canvas.c` 16, `test_backend.c` 4 |
| `_arrive` implementations | 6, three in code and three in docs. All six set the position and then add the node |
| `renderer.sprite` calls, comments excluded | 6: `AnimatedSprite`, 3 in examples, 2 in test projects |
| Renderer draw calls that take a colour | `rect`, `image`, `image_at`, `background` take `color:`; `nine_slice` takes `tint:`; `sprite` and `map_tile` take none |

## 1. A pushed platform carries its riders

**Today.** A mover's `_update` measures the node's world position around
`take_step` and hands the difference to its `Platform`
(`Mover#step_and_carry`, `mover.rb:321`). It finds the `Platform` lazily, on its
first update (`find_platform`, `mover.rb:334`). `Pushable` replaces `_update`
(`pushable.rb:56`) because its pushes arrive during other movers' updates. So it
never looks for a `Platform` and never carries. `docs/api/components.md:1192`
states the limit: "a pushed platform carries nobody".

**What it resembles.** It is `step_and_carry` again, around `Pushable#push`
instead of `take_step`. `push` already measures what it needs: it records
`pushed_x` and `pushed_y` (`pushable.rb:71`). The fix is in the extend pile:
after `apply_move`, `push` finds the `Platform` the way `Mover` does, and calls
`carry(pushed_x, pushed_y)`.

**Traps.**

1. **A grabber standing on the raft would move twice.** `Mover#drag_along_x`
   (`mover.rb:362`) pushes the grabbed crate first, then steps the grabber by
   the distance the crate went. If the push carried the raft's riders and the
   grabber was one of them, the carry moves it once and its own step moves it
   again. `push` receives the pusher as `by:`, so the carry has to skip the
   rider whose node is `by`. A walking pusher cannot meet this: it overlaps the
   raft it stands on, and an existing overlap stops nobody, so it never pushes
   its own platform. `Grab` can still hold it.
2. **`drag_along_x` pushes twice in one step** when the grabber is stopped short.
   The second push corrects the first. Each push carries by its own delta, so the
   riders end up moved by the sum, which is the crate's real step. A spec should
   pin that.
3. **Nothing keeps a pushed raft on the water.** The reserved blockers are
   `:tiles`, `:bounds` and `:gaps` (`Mover::RESERVED`). `:gaps` keeps the centre
   of a box on the floor, and a platform's own box *is* floor. A raft wants the
   opposite: its box kept off the ground. `TileWorld#ground_at?`
   (`tile_world.rb:163`) already answers the cell question, and ignores
   platforms. A blocker source beside `GapBlockers` could use it. Without one, a
   raft is pushed onto dry land unless the game walls the water with colliders.
   The carrying fix does not wait on this.
4. **The docs say it three times.** The `Mover` header (`mover.rb:16-17` and the
   section at `mover.rb:106`), and the `Mover` phase line in
   `docs/api/components.md:1191-1192`.

**What exercises it.** No project puts both components on one node. The
acceptance test is a raft to push with a hero on it. `topdownplatformer` already
has a raft (`raft.rb`, `Platform` and `PathFollow`) and a crate (`crate.rb`,
`Pushable` and `Respawn`), so a pushed raft there is one class away. The specs
belong in `pushable_spec.rb` and `platform_spec.rb`, and `platform_allocation_spec.rb`
covers the carry's allocations.

## 2. Facing-aware targeting

**Today.** `Targeting#pick` (`targeting.rb:44-46`) calls
`CollisionWorld#nearest(node.world_x, node.world_y, range, layer:)`. That
measures from the node's origin to each collider's centre (`cx`, `cy`), and keeps
the first on a tie, because it compares with a strict `<`. A hero whose origin
sits between two signs picks the nearer one, or on a tie whichever the broadphase
yields first, whichever way the hero faces.

**Nothing keeps a facing.** `Mover#heading_x` and `heading_y` (`mover.rb:225`)
call themselves "a facing rather than a velocity", but they read 0, 0 whenever
the mover is not trying to move. `CharacterBody` answers its intent this tick,
`PathFollow` zeroes at the end of its route, and `Velocity` scales its velocity.
So the heading is 0, 0 at exactly the moment a player stands in front of a sign.
`AnimatedSprite` has one `:stand` animation for the same reason
(`animated_sprite.rb:67-70`).

**What it resembles.** `AnimatedSprite#walk_animation` already turns a heading
into one of four directions, a tie going horizontal. A facing that `Mover`
remembers answers two questions: which target is in front, and which way to
stand. That puts it in the extend pile. `Mover` grows `facing_x` and `facing_y`,
the last heading that was not 0, 0, kept while the node stands still. The base
class is the place, because every mover updates it after `take_step` and no
subclass can forget it.

**The policy.** `POLICIES` is a public constant, and appending `:facing` is an
addition. `Grab` picks through `Targeting#pick`, so it gets it: a `Grab`
reaching for the crate in front of it is the same fix. The `Interactor` does
not *(read at `6526120`)*. It keeps the nearest node answering each of its
actions from its own `query_circle` pass, and takes `policy:` without reading
it. So `:facing` has to reach that pass as well, or
`Interactor.new(policy: :facing)` would pick by distance without a word.
`:facing` needs exactly
one `Mover` sibling to read, so it should `require_sibling(Mover)` at attach, as
`AnimatedSprite` does. `:nearest` stays measured from the origin: that is its
0.4.0 behaviour.

**Open:** what `:facing` picks. It could take the nearest candidate in front
(a positive dot product with the facing) and nil when none is. It could fall
back to the nearest behind. Or it could weigh angle against distance. Only a
game standing between two signs decides this, so the acceptance scene is that
one. The pick must allocate nothing: it runs every tick, and `nearest` allocates
nothing today *(measured, 0 objects a tick)*.

## 3. Multiply blend

**Today.** `Util::Blend::MODES` is `[:alpha, :add]` (`blend.rb:23`), and a mode's
position in it is the number C takes (`blend.rb:14`). The chain runs:

| | |
|---|---|
| Ruby | `Blend.index(mode)` → `Renderer#push_blend(index)` (`renderer_ext.c:328`) |
| C | `rgame_app_push_blend` (`app.c:830`) → `rgame_canvas_push_blend` → the enum in `draw_queue.h:54` |
| GL | `gl_set_blend` (`gl_backend.c:21-23`) |

`Particles` validates `blend:` through `Blend.mode!` (`particles.rb:85`), so it
gets a new mode with no change.

**Three traps.**

1. **`app.c:839-840` turns every mode but `:add` into `:alpha`.** A mode added
   to the enum and to `MODES` but not there draws as plain alpha, with no error.
   No spec ties `MODES` to the enum. `spec/rgame/util/controls_spec.rb` parses a
   C header and compares every value, and the same guard would catch this.
2. **The GL function in `possible-todos.md` predates premultiplied alpha.** It
   says `glBlendFunc(GL_DST_COLOR, GL_ZERO)`. Colours are premultiplied now, and
   the source factor is `GL_ONE` (`gl_backend.c:23`). A transparent texel is
   (0, 0, 0, 0), so `GL_ZERO` draws it black, and a shadow sprite would blacken
   its whole rectangle. The function is `GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA`.
   The source arrives as (a·c, a), so the result is dst·(a·c) + dst·(1 − a),
   which is dst·lerp(1, c, a). An opaque pixel multiplies, and a transparent one
   leaves the destination alone. Both factors are core GL 1.0.
3. **Two places name `:multiply` as the unknown mode.** The shared renderer
   contract (`a_renderer.rb:756-757`) and a docs example the doc specs run
   (`docs/api/values.md:298`). Both fail once the mode exists, and each needs
   another name.

**What to add.** `:multiply` goes at the end of `MODES`, never in the middle,
because the position is the number. Then a case in `gl_set_blend`, the coercion
in `app.c`, and a pixel spec beside the two `:add` ones
(`spec_core/rgame/core/renderer_spec.rb:309-323` and `:428-452`). A recording
refuses a blend mode, and it refuses multiply for the same reason. A night tint
is then a rect drawn under `blended(:multiply)` over a `WorldView`, and a shadow
is a dark sprite drawn the same way.

## 4. The respawn point follows a room move

**Today.** `Respawn#_attach` (`respawn.rb:68`) records the point on the first
attach only. Every later attach keeps it and checks it for a gap. The header says
so (`respawn.rb:16-18`), `docs/api/components.md:1606-1608` repeats it, and
`respawn_spec.rb:28` pins it: "stays when the node attaches again somewhere
else".

**A game cannot work around it today.** `Rooms#land` (`rooms.rb:356-366`) takes
the node out of its old room and calls the new room's `_arrive`. `_arrive`
places the node and adds it, and the add runs `Respawn#_attach`, which raises
for an old point over a gap in the new room. `on_arrived` fires after that. So a
handler that calls `set_point` on arrival comes too late: the raise came first.

**What exercises it.** No project mounts both. That is CLAUDE.md's case of two
systems green in isolation and never composed, and the scene to write first is a
hero with a `Respawn` walking through a door into a room with gaps.

**Where the reset could live.**

- **A. In `Respawn#_attach`.** On an attach under a different `Scene::Room`, take
  where the node stands. It depends on `_arrive` placing the node before adding
  it. All six implementations do, but nothing enforces it, and one that adds
  first would record the old room's position.
- **B. In `Rooms#land`, after `_arrive`.** The position is final there. `Rooms`
  sets the point of the moving node's `Respawn`, and `Respawn#_attach` stops
  checking on a later attach, since `set_point` checks instead. A move to a room
  with a gap under the entrance still raises, and names the entrance. `Rooms` and
  `Respawn` are both engine classes, so the reference is allowed. A warp, a move
  to the node's own room, also passes through `land`.

B puts the reset where the landing is known, and does not depend on a habit.

**Open:** does a warp reset the point? And does a checkpoint survive leaving its
room and coming back? A reset on every landing forgets it.

## 5. Tinting a character

**Today.** `Renderer#sprite(id, row, col, x, y, flip_x:, z:)` (`renderer.rb:103`)
takes no colour. It calls `SpriteSheet#draw`, which calls `image_at`, and
`image_at` already takes `color:` down to C (`renderer.rb:193`). A per-call
colour on `sprite` is therefore two keywords: one on `Renderer#sprite` and one on
`SpriteSheet#draw`. Add a third on the fake (`fake_renderer.rb:93`) and a case in
the shared contract. `Components::Sprite` draws with `renderer.image`, which
takes `color:` already (`sprite.rb:48`). `AnimatedSprite` is the one that draws
through `sprite`.

**Pick `color:`.** `rect`, `image`, `image_at` and `background` call it
`color:`. `nine_slice` calls it `tint:` and forwards it as `color:`
(`renderer.rb:110-112`), and `UI::IconButton` takes `tints:`. `sprite` is
`image_at` underneath, so `color:` matches what it forwards to, and `nine_slice`
stays the odd one out.

**A character is several draws, so a keyword per call does not tint it.** The
adventure's hero draws a sprite, a hat and its name over it (`hero.rb:103-109`).
Tinting that hero means tinting its subtree, as `Node2D#opacity` fades one.

**What it resembles: the opacity stack.** `Node2D#draw` applies `opacity` through
`renderer.faded`. The canvas keeps a stack of opacities and multiplies each
vertex's alpha by the top one (`canvas.c:250-271`). A tint is the same multiply
on all four channels: `faded(o)` is a tint of white at alpha `o`. Generalising
that stack from one float to four gives a node-wide `tint`. It reaches every draw
under the node: sprites, rects, text, `map_tile` (which takes no colour,
`renderer.rb:143`) and children. The recording replay already multiplies by a
tint this way (`canvas.c:324-331`).

**Traps.**

1. **`rgame_as_shown` (`node2d.rb:650`) branches four ways** on scale and opacity.
   A tint as a third wrapper would make eight. Folded into the push opacity uses,
   it stays at four.
2. **Combining opacity and tint must not build a `Color` every frame.** Push four
   floats through a private renderer method, as `push_opacity` takes one, or have
   the node combine them when either is set.
3. **White at full opacity must stay bit for bit.** `faded_alpha` returns the
   alpha it was given at opacity 1, so an untinted draw is what it was before
   opacity existed. The smooth-art plan counted 4 Check tests asserting a
   translucent vertex colour, among them
   `the_colour_reaches_the_vertex_in_gl_byte_order` in `test_canvas.c`.
4. **Premultiplication already comes out right.** `vertex_colour` fades and then
   premultiplies. A texel is premultiplied at load, so texel × vertex colour is
   the premultiplied product.

**Open:** node-wide, per call, or both. Node-wide answers "tint a character".
`color:` on `sprite` is parity with `image` and costs almost nothing.

## How the five relate

None depends on another, so each is one branch and one pull request. One pair
touches the same code and is easier in sequence: **multiply and tint** both
change `graphics/canvas.c` and the renderer's shared contract.

The pushed platform and the respawn point are loose ends of the top-down
platforming plan, and share `topdownplatformer` as the place to drive them.

## Open questions

1. **Where facing lives, and what `:facing` picks.** Blocks feature 2.
2. **Whether a warp resets the respawn point**, and whether a checkpoint survives
   a room move and a return. Blocks feature 4.
3. **A blocker that keeps a pushed raft over the gaps**, or colliders the game
   places. Does not block the carrying fix.
4. **A node-wide tint, `color:` on `sprite`, or both.** Blocks feature 5.

## Where these came from

Three of the five are in `docs/plans/possible-todos.md`. Remove each entry as its
feature lands:

- "Blend modes beyond `:add`": the multiply blend.
- "Loose ends from top-down platforming", two bullets: the pushed platform and
  the respawn point in a room left behind.

Facing-aware targeting and tinting a character have no entry there.
"Per-layer parallax, offset and tint" under the Tiled loose ends is a different
feature: a tile layer's tint read from the map.
