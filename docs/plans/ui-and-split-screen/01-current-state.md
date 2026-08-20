# Camera and input as they stand — and exactly what blocks split-screen

Working document for the overhaul requested in
[`camera-and-input-requirement.md`](camera-and-input-requirement.md). This file
is the inventory: what the code does today, and the specific properties that
make more than one camera or more than one player impossible. The proposal is in
[`03-design.md`](03-design.md); the survey of how other engines answer the same
question is in [`02-prior-art.md`](02-prior-art.md).

---

## 1. What a camera is today

Three objects, and the camera is *none* of them exclusively — it is a plain
object the scene creates and hands to two different consumers.

```
BeachScene (a Node2D, the scene boundary)
├── @camera = Engine::Camera.new(viewport_width:, viewport_height:,
│                                world_width:, world_height:)
├── component  Components::TileWorld.new(map:, tilemap_id:, camera: @camera)
│              └─ draw: renderer.tilemap(id, camera.x, camera.y,
│                                        camera.viewport_width, camera.viewport_height)
└── child node Engine::CameraView.new(camera: @camera)
               └─ draw_children: renderer.translated(-camera.x, -camera.y) { super }
                  └── player, NPCs — world-space children
```

- `Engine::Camera` (`lib/rgame/engine/camera.rb`) — `x`, `y`, `center_on`, and a
  clamp against world bounds. Its **viewport size is fixed at construction**
  (`camera.rb:10`) and comes from the window (`beach_scene.rb:28` passes
  `game.width` / `game.height`).
- `Engine::CameraView` (`camera_view.rb:23`) — a `Node2D` that overrides
  `draw_children` to wrap the subtree in `renderer.translated`. This is the one
  and only view transform.
- `Components::TileWorld#draw` (`tile_world.rb:58-63`) — **does not go through
  `CameraView`**. It is a component on the scene node, so it draws in the scene's
  own `draw_content`, and passes the camera offset to `renderer.tilemap` as
  arguments, because the C tile renderer does its own culling.

So there are already **two independent ways the camera reaches the renderer**,
and they are consistent only because both read the same `@camera` object.

### The scene owns the camera

Nothing in the engine says a scene must have a camera, or may have only one.
The convention is entirely in the example. `Game` knows nothing about cameras.

## 2. What the tick looks like today

`RGame::Game` (`game.rb:88-104`):

```ruby
def update(dt)
  @root.control(@action_mapper.poll(@input))   # one snapshot, whole tree
  @root.update(dt)
  @root.sweep_freed
  @dirty = true
end

def draw
  @root.draw(@renderer)                        # one pass, whole tree
  @overlay.draw(@renderer, width, height, fps)
end
```

Three traversals of one tree, each exactly once per tick. `Node2D#control`,
`#update` and `#draw` (`node2d.rb:126`, `:136`, `:145`) all have the same shape:
resolve the transform, run components, run the `on_*` hook, descend.

## 3. What input is today

Two binding tables in series, and the doc comments disagree with the code about
which is which.

```
game code                Engine::ActionMapper          Core::Input              App (C)
:turn ────── map ──────▶ {axis: %i[left right]} ─┐
                                                 └─▶ down?(:left) ─ table ─▶ KEY_LEFT ─▶ input_down?(0, 80)
```

- `Util::Controls::DEFAULT_KEYBOARD` maps `:left → KEY_LEFT`, `:fire → KEY_SPACE`
  — a **semantic name to a physical id**, per device class.
- `Core::Input#down?(action, device:)` (`input.rb:58`) resolves through that
  table and asks the app.
- `Engine::ActionMapper#poll` (`action_mapper.rb:29-41`) maps the *game's*
  actions onto `Core::Input`'s action names. Its comment calls those "physical
  ids decoupled from any backend's constants" — they are not; they are a second
  layer of names, and the physical ids are one table further down.

Four consequences, all of them blocking:

1. **`ActionMapper` never passes `device:`** (`action_mapper.rb:37,39`), so every
   call takes `Core::Input`'s default — the keyboard. **No gamepad input can
   reach the engine layer at all today**, despite the whole per-device stack in C
   being finished and specced.
2. **`Core::Input#axis` is never called** by anything above. Analog sticks are
   unreachable; `ActionMapper` synthesises axes from two buttons instead
   (`action_mapper.rb:36-38`). There is no dead zone anywhere in the project.
3. **A rebinding screen has no single table to edit.** Changing what `:fire`
   means requires editing `Core::Input`'s table (a `Core` object the engine layer
   may not name) *or* the action map (which only names other names).
4. **One mapper, one `Actions`, one `control` for the whole tree.** The snapshot
   is a single reused, deliberately allocation-free object
   (`action_mapper.rb:19-24`) — correct for one player, and the exact thing that
   has to become one-per-player.

## 4. The seven properties that block the requirement

Mapped against [the requirement](camera-and-input-requirement.md):

| # | Blocker | Where | Requirement it breaks |
|---|---|---|---|
| 1 | `draw` is a single pass over the tree | `game.rb:100`, `node2d.rb:145` | each player needs the *same* world drawn once per camera |
| 2 | A camera is applied by a node *inside* the world subtree | `camera_view.rb:23` | a node in the shared world cannot know how many times it is being drawn |
| 3 | Camera viewport size is fixed at construction | `camera.rb:10-13` | the rect changes when the layout does (1 player full-screen → 2 players half each) |
| 4 | `TileWorld#draw` reads one camera off the scene | `tile_world.rb:58` | a view-dependent drawer needs to know *which* view it is drawing for |
| 5 | One `Actions` snapshot broadcast to the whole tree | `game.rb:89` | per-player actions; the mapper is single-instance and single-device |
| 6 | Nothing owns "which device is player 2 on" | — | per-player bindings; hot-plug already works in C and is unused above |
| 7 | Nothing can address "the screen minus my half" | — | per-player HUD/menu must lay out against its viewport rect, not `game.width` |

Two more that are latent rather than blocking:

8. **There is no z band convention.** The draw queue sorts by `z` across the
   whole frame, and a component's `z:` is a render layer chosen by hand
   (`sprite.rb:12` is explicit that it is *not* `abs_z`). Today `DebugOverlay`
   picks `Z = 1_000_000` to stay on top. Once there are three draw bands
   (world / per-player screen space / global screen space) their ordering has to
   be stated rather than picked per class.
9. **`renderer.clipped` has never been called from above.** The C side is
   covered end to end (`test/test_canvas.c:414`, "two viewports each get their
   own clip and camera"), and `spec/support/shared_examples/a_renderer.rb:401`
   covers the contract — but no engine class and no example uses it. The first
   split-screen pass is also the first real exercise of that path.

## 5. What is *not* broken, and should survive

Worth saying plainly, because the overhaul touches the files around them:

- **The scene graph itself.** `control`/`update`/`draw`, components, anchors
  (`root`/`scene`), `system(klass)`, `queue_free`/`sweep_freed`, the
  construct-vs-enter split. None of it assumes one camera or one player.
- **`draw_children` as an override seam** (`node2d.rb:235`). It is exactly the
  right hook; it just needs a node type above `CameraView` that loops.
- **`SceneStack` as a *component*.** Because it is a component rather than a
  property of the root, a game can mount one per band — a world stack, a
  per-player menu stack, a global cutscene stack — with no change at all. This is
  the piece that makes "one player in their inventory, one player walking" cheap.
- **The whole C input stack.** Per-device queries, stable player slots across a
  replug, hot-plug hooks, virtual-controller tests. It is finished and correct;
  only the Ruby layer above it fails to use it.
- **The transform and clip stacks in C.** They are push/pop stacks and a clip
  always narrows, precisely so this feature is possible.
- **`draw` renders state; time enters through `update`.** Split-screen turns
  this from a style rule into a correctness rule — see
  [`03-design.md`](03-design.md), "What N draws per tick makes newly illegal".
