# UI and split-screen — what the engine layer is still missing

**Status: notes, not a plan.** Two features the engine layer needs and does not
have. Neither is a port and neither is blocked on anything; both are new design.
This folder exists so the reasoning behind their absence is not rediscovered.

Everything else the Gosu replacement and the `RGame::Engine` move turned up has
landed or been folded into the real documentation. These two are what remain.

**Split-screen now has a worked proposal**, driven by
[`camera-and-input-requirement.md`](camera-and-input-requirement.md):

- [`01-current-state.md`](01-current-state.md) — what camera and input do today,
  and the seven properties that block more than one of either.
- [`02-prior-art.md`](02-prior-art.md) — how Unreal, Unity, Bevy and Godot answer
  the same question, and what to take from each.
- [`03-design.md`](03-design.md) — the design: the player owns the camera and
  the bindings, the world is updated once and drawn once per view. It answers the
  ownership question §2 leaves open below, and it changes the input half too.
- [`04-roadmap.md`](04-roadmap.md) — the implementation plan. Detailed for steps
  0–3, deliberately rough for 4–6.

---

## 1. There is no UI toolkit

The engine used to have one: `ui/menu.rb`, `ui/button.rb`, `ui/selector.rb`,
`ui/control.rb`, `ui/panel.rb`, `ui/label.rb`, `ui/localized.rb`, plus a
`Clickable` component. All of it was deleted, because all of it hit-tested
against a mouse cursor:

```ruby
def hovering?(actions) = contains?(actions.pointer_x, actions.pointer_y)
```

**Mouse input is not part of this engine, deliberately.** `RGame::Core::Input`
has no pointer and no `:pointer` binding, and the id range a mouse would have
occupied is left unused in `rgame/core.h` rather than renumbered later. That
decision is recorded in `docs/c_engine_feature_specs.md` §1. Its known cost was
always exactly this: click-based UI has to become **keyboard and controller
navigation**, which is a different design rather than a port of the old one.

So the old package is not a reference. Do not preserve its API.

### What a replacement has to answer

- **Focus.** With no pointer there is no hover, so something owns "which control
  is focused" and how `up`/`down`/`left`/`right` move it. That is the whole
  design; everything else follows.
- **Activation.** `confirm` on the focused control. The physical ids already
  exist (`RGame::Util::Controls::DEFAULT_KEYBOARD` has `confirm`), and
  `ActionMapper` already turns them into named actions with edge queries.
- **Layout.** The deleted package positioned everything absolutely. Whether that
  is still the answer is open.

### It leaves a hole in the test coverage

Nothing exercises `renderer.nine_slice` or `RGame::Core::UiAtlas` end to end any
more — no example registers a UI atlas, and both classes are covered only by
their own specs. Whatever replaces the UI package is what will first prove that
path works in a running game, which is a reason to build a small real menu
rather than a widget library nobody uses.

`RGame::Engine::CachedLabel` survived the deletion and is the piece worth
keeping in mind: a display string rebuilt only when it changes, which is what
stops a per-frame label allocating. See `docs/api/toolbox.md`.

## 2. Split-screen exists in Core and nowhere above

**The plumbing has been ready since the renderer was written.** Per viewport,
clip to its screen rect and translate by its camera offset, then run the *same*
world-draw code:

```ruby
players.each do |p|
  renderer.clipped(p.vx, p.vy, p.vw, p.vh) do
    renderer.translated(-p.camera.x, -p.camera.y) { world.draw(renderer) }
  end
end
```

That is why the transform and clip stacks are proper push/pop stacks rather than
one global mutable region, and why a clip always *narrows* — a child cannot draw
outside the region its parent allowed. `test/test_canvas.c` checks the
composition end to end, with no display involved.

**Nothing above has ever called it.** `renderer.clipped` is the one Core drawing
method neither example nor any engine class uses. The plumbing is ready and
completely unexercised from above, which is worth knowing before trusting it.

### What changes above

`RGame::Engine::CameraView` and `RGame::Engine::Camera` are the pieces that grow
it, and the change is not cosmetic: **it changes what a camera is**, from a
single draw-time offset for the whole screen into one of several viewports, each
with its own rect. A scene currently assumes one camera and one screen; both
assumptions become "one per player".

Worth deciding early: does a viewport own a camera, or does a camera own a
viewport? The answer decides whether split-screen is a property of the scene or
of the node that draws the world.

### The interaction nobody has looked at

Input is already per-device — `Input#down?(action, device:)` takes a device, and
`device_slots.c` keeps a player on one slot across a disconnect. But
`ActionMapper#poll(backend)` polls **one** backend and produces **one** `Actions`
snapshot, and `RGame::Game` calls it once per tick. Two players need two
snapshots. That is a small change and an easy one to forget until the second
player's controller does nothing.

## Cross-references

- `docs/api/drawing.md` — `clipped`, `translated`, and the split-screen shape.
- `docs/api/scene_graph.md` — the camera as a draw-time view transform, as it is
  today.
- `docs/api/input.md` — devices, slots, and what `ActionMapper` does with them.
- CLAUDE.md, "The three layers, and who may talk to whom" — both features live
  in `RGame::Engine` and may not name `RGame::Core`.
