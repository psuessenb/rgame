# Plan — a set of small, single-concept examples

## Why

`test_projects/` (renamed from `examples/`) holds four complete games. They are
the acceptance test for how the three layers are wired, and they are good at
that. They are bad at answering "how do I make a character jump", because the
answer is spread across four files that are also doing five other things.

So `examples/` comes back, with a different job:

| | `examples/` | `test_projects/` |
|---|---|---|
| Answers | "how do I do *X*" | "does the whole stack still work" |
| Size | one concept, ideally one file | a whole game |
| Read by | someone learning the engine | someone changing the engine |
| Driven by | `tools/drive_test_project.rb` (same harness) | same |
| Assets | new, CC0, committed | `media/`, non-redistributable |
| In the gem | **yes**, with its assets | no |

An example is documentation that runs. It gets the same treatment as the rest of
`docs/`: written for a reader who has only the current code, and valid against
it.

## Conventions every example follows

1. **One concept.** If it needs a second heading to explain, it is two examples.
2. **One file where possible.** `main.rb` alone. A second file only when the
   concept *is* the split — a component that is engine code rather than
   example code.
3. **A header comment naming the concept and the pieces it uses**, in the shape
   `test_projects/tiled_world/main.rb` already uses — the list of what it
   exercises is the most useful thing in that file.
4. **Every asset is a new, redistributable asset — and most examples need
   none.** `media/` is off limits: it is gitignored because its contents cannot
   be redistributed, so an example built on it cannot run for anyone but us.
   Anything an example draws is either primitives and the shipped font, or a
   file committed under `examples/assets/` under a licence that permits
   redistribution — and `examples/` ships in the gem, so "redistribution" is
   literal. Sourcing art is the slowest part of this whole plan, so a concept
   that can be shown with rects and text is shown that way. See "Assets" below
   for the full manifest.
5. **A drive script** at `tools/drive/examples/<name>.rb`, so the example is
   covered by tier 3b rather than only by somebody opening a window. The
   harness finds it by mirroring the example's own path — see "Harness change".
6. **Linked from `docs/api/`.** An example nothing points at is an example
   nobody finds. Each one gets a line in the page for its concept.

## Harness change — **done**

`tools/drive_test_project.rb` used to derive the default input script from the
*basename* of the project's directory, which is unique only by luck once there
is more than one tree of projects: `examples/snake` and `test_projects/snake`
would have silently shared one script, and the symptom is a game driven by
another game's inputs — a confusing report rather than an error.

It now mirrors the project's path instead, in `DriveTestProject.default_script_for`:
`test_projects/tiled_world/main.rb` reads `tools/drive/test_projects/tiled_world.rb`,
and a future `examples/walk/main.rb` will read `tools/drive/examples/walk.rb`.
The existing scripts moved into `tools/drive/test_projects/` accordingly, and a
project outside the repo now aborts saying to pass `--script` rather than
reporting a nonsense path as missing.

`test_projects/snake` also got the drive script it never had
(`tools/drive/test_projects/snake.rb`). So **nothing in this section is
outstanding** — a new example only has to drop a script at its mirrored path.

## The examples

Each entry lists what the example demonstrates, what it needs that **already
exists**, what is **new engine work**, and what assets it wants.

### 1. `examples/walk` — a player-controlled sprite — **done**

**Shows** the smallest complete thing: a node, a component stack, and input
reaching it as actions rather than keys.

**Existing:** `RGame::Game`, `Node2D`, `Components::AnimatedSprite`,
`Components::CharacterBody`, `Components::PlayerController`,
`InputMap.default` (`move_x`/`move_y`), `AnimationSet`.

**New: none — and that was the point.** This example was the control: if the
smallest possible game had needed new engine code, that would have been a
finding about the engine before nine more examples were planned on top of it. It
did not. `examples/walk/main.rb` is one file, and the only class it defines
beyond the root is a four-line `Hero < Node2D` whose `on_update` keeps the
walker inside the window — a plain `CharacterBody` moves the node wherever the
intent points, by design, because giving it edges is `TileWorld`'s job and that
is example 2's subject.

Two things it turned out to be worth saying out loud in the file, because both
are silent when got wrong:

- **Build a node whole, then add it.** `add_component` runs `on_attach`
  immediately once the node is live, and `AnimatedSprite`'s attach requires a
  `CharacterBody` sibling. Composing in `initialize` — before anything is in the
  tree — makes the order components go on in stop mattering.
- **The five animation names are a contract**, not a convention.
  `AnimatedSprite` resolves `stand` / `walk_up` / `walk_down` / `walk_left` /
  `walk_right` by name through `AnimationSet#row`, which uses `fetch`.

That contract is now asserted by `spec/example_assets_spec.rb`, headless: the
descriptor declares all five, `walk_left` mirrors `walk_right`'s row, each walk
cycles all six frames, and every frame fits inside `hero.png` — the last one
guarding a re-export at a different size, which slices frames out of empty space
and raises nothing at all.

**Assets:** **A**, delivered.

### 2. `examples/scroll_map` — a Tiled map a player scrolls — **done**

**Shows** loading a `.tmx` through the asset manager, drawing it through a
`WorldView`, and a camera clamped to the map bounds.

**Existing:** the `:tilemap` asset loader on `RGame::Game`,
`Engine::TileMap`, `Core::TileMapRenderer`, `Components::TileWorld`,
`Engine::WorldView`, `Engine::Camera` (it already has `world_width` /
`world_height` and clamps), `Components::CameraFollow`.

**New: none. The open question is settled — the rig wins, and no `CameraPan`.**

The camera is moved by pointing `CameraFollow` at an invisible rig node carrying
`CharacterBody` + `PlayerController`. The worry was that this would read
indirectly and need a paragraph to justify. It needs two sentences, and they
teach the right thing rather than apologising for a workaround: *a camera is
owned by a player and pointed by a component on a node, so moving a camera means
moving a node.* The rig is `examples/walk`'s hero with the sprite left off —
same body, same controller — which makes "the camera follows the player" and
"the player scrolls the map" visibly the same construction rather than two
features. A `CameraPan` component would have hidden exactly that.

Two things the file has to say out loud, both found by building it:

- **The rig needs its own clamp to the world.** `Camera#resolve` already refuses
  to show past the world's edges, but the rig is not the camera: without a clamp
  it walks off into nothing while the view stays pinned, and the player is left
  holding a key that does nothing visible.
- **A colour is not an Integer.** `renderer.line(..., color: 0xFFFFFFFF)` raises
  `TypeError` out of `Color.coerce`, which takes `nil`, `[r, g, b]`, `[r, g, b, a]`
  or a `Color`. The example holds a `Util::Color` constant — an array literal in
  a draw method allocates one per frame, which is what `Game/NoNeedlessAllocation`
  exists to stop.

**Assets:** **B**, delivered.

`spec/example_assets_spec.rb` now covers `town.tmx` as well: that it is larger
than the window on both axes (a map that fits makes this example a still image),
that the fence row is solid at every tile **except** the three-tile gap, and that
the route between the clearings is more than twice the straight line. The last
two are the mistakes made once each while authoring the map, and both were
mutation-checked — punching a second hole in the fence fails them.

### 3. `examples/game_menu` — opening an in-game menu — **done**

**Shows** a menu that opens over a running world, pauses only the player who
opened it, and closes again.

**Existing:** `Engine::PlayerLayer`, `Engine::UI::Menu` / `UI::MenuItem`,
`Node2D#paused`, `Node2D#draw_children` (the "close by not calling `super`"
seam), `renderer.nine_slice`, `ui_cancel` / `ui_confirm` from the default map.

**New engine code:** none, as expected.

**But the asset claim below was wrong, and that is the finding.** This example
was planned as asset-free — "a panel is `renderer.rect` and the shipped font".
It is not, and cannot be: `UI::MenuItem#on_draw` calls `renderer.nine_slice`,
and a nine-slice id resolves by **registration only** — it names an element of
an atlas, never a file — so `UI::Menu` does not draw at all without one
registered. `Menu` also constructs `MenuItem` itself, and its `style:` option
swaps *element names*, not the drawing, so there is no seam to route around it.

So **asset C stopped being cosmetic and became required**, and it shipped here
rather than being deferred to example 6. It is worth stating plainly in
`docs/api/ui.md` at some point: the UI package needs art before it draws
anything.

Two constraints on which art, both found by looking rather than by reading:

- **Several of the pack's panels are frames with transparent middles**, which
  read as solid on the sheet's own dark background and then show the world
  through them in place.
- **`MenuItem`'s label colour is a constant**, so the buttons must be light or
  the label vanishes into them. A widget whose text colour cannot be set
  constrains the art rather than the other way round.

**Assets:** **C**, delivered — `ui.png` + `ui.json`, five 32x32 elements cut
from Kenney's CC0 *UI Pack - Pixel Adventure*, 1 KB.

### 4. `examples/sound` — a sound effect fired by a button — **done**

**Shows** the smallest complete noise, and the seam it travels through.

**Existing:** `Core::Audio#register_sound`, `Core::Sample`, `Engine::AudioBus`,
`Engine::AudioDirector`.

**New:** none.

**The point is the seam, not the noise.** A node may not name `RGame::Core`, so
it cannot reach the audio device — it emits on `AudioBus`, a global signal hub
that knows nothing about sound, and an `AudioDirector` wired up in `main.rb`
forwards it to the real one. That is what lets a headless spec substitute
`FakeAudio` and assert on what was *asked for*.

**A `Sample` layers.** Decoded up front, a fresh voice per `play_sound`, and no
`playing?` — the question has no answer for a sound that may be going five times
at once.

**Nothing is wired here at all any more.** The sample is named by path, and
`RGame::Game` subscribes the `AudioDirector`. Both lines this example used to
carry were removable, and the director one was a footgun: forgetting it was
silent — the game ran, the events fired, and nothing came out.

Two things about the display, and one of them was a bug in our own cop:

- A `"#{n} plays"` label allocates a String every frame, so the play count is
  drawn as a row of pips instead. `Game/NoInterpolationInHotPath` is right; the
  fix is the code.
- **`[n, MAX].min` does not allocate**, and `Game/NoNeedlessAllocation` was
  wrong to say it did. The VM compiles `min` on an array literal to a single
  `opt_newarray_send` that reads the operands off the stack — 0 objects over
  200,000 calls. The cop now allows the four sends the VM optimises (`min`,
  `max`, `hash`, `include?`, each only without a block or extra argument) and
  still flags everything else. Its own spec had used `[a, b].max` as the
  canonical *offence*, so that example was wrong too.

**Assets:** `blip.ogg` (part of **F**).

### 5. `examples/music` — a looping track, started and stopped — **done**

**Shows** the other kind of sound, and the guard that makes re-entering a scene
safe.

**Existing:** `Core::Audio#register_music` / `play_music` / `stop_music`,
`Core::Song`, and the same bus and director as example 4.

**New:** none — though it did turn up a **gap in the drive harness**:
`AudioProbe` recorded `play_sound` and `play_music` and silently ignored
`stop_music`, so a game stopping its music was invisible in every report. Fixed.

**A `Song` is not a `Sample`.** Streamed, one voice, stoppable, and it can be
asked `playing?`. The two types exist so that distinction is in the type rather
than in a convention.

**Starting it twice does not restart it** — `Audio#play_music` returns early when
the song is already playing, so a scene emitting `play_music` from `on_add` does
not chop the track back to zero every time the player walks through a door.

**And that is where a driven run stops being able to help.** The report proves
the events were emitted and reached the device. Whether the guard actually
prevented a restart, and whether the loop wraps without a click at 16.6s, are
facts about what came out of a speaker. The example says so rather than implying
its on-screen playhead proves either — the bar is the scene's own timer, and
keeps running on a second press because *this scene* did not reset it, which is
not evidence about the device at all.

**Assets:** `music.ogg` (part of **F**) — and this example is what caught the
first one being unloopable, which no automated tier could have.

### 6. `examples/fullscreen` — toggling fullscreen — **done**

**Shows** a window switching between windowed and fullscreen, and the layout
following it.

**Existing:** the `resize` callback already reaches `Game#resize` →
`Viewports#resize`, so viewport rects and camera clamps re-derive themselves for
free. `Engine::Layout` divides whatever size it is given.

**New — this one is C work, the only example in the list that is:**

| Layer | Work |
|---|---|
| `ext/rgame_core/app/app.c` | `SDL_SetWindowFullscreen` with `SDL_WINDOW_FULLSCREEN_DESKTOP` (desktop, not exclusive — no mode switch, no resolution list, and the resize callback already handles the rest) |
| `include/rgame/core.h` | `void rgame_app_set_fullscreen(rgame_app *, int)` and `int rgame_app_fullscreen(const rgame_app *)` — plain C types, as the header requires |
| `ext/rgame_core/ruby/core_ext.c` | `App#fullscreen?` and `App#fullscreen=` |
| `spec_core/rgame/core/app_spec.rb` | round-trip the flag under Xvfb |

There is no pure-logic half to put in layer 1 here — it is two SDL calls and a
flag read, which is exactly what "thin real shim" in CLAUDE.md's tier list is
for.

**Opening fullscreen is a creation flag, not a switch afterwards**, so
`rgame_app_create` took a `fullscreen` parameter rather than the example calling
the setter on its first tick. Both end up fullscreen; only one of them avoids
showing a windowed frame first, and that flash is what a player reads as a
broken startup. Three call sites, all ours.

**The one real trap was the event.** SDL raises `SDL_WINDOWEVENT_RESIZED` only
when something *outside* the program resizes the window, and
`SDL_WINDOWEVENT_SIZE_CHANGED` for that case *and* for a size the program asked
for. The loop listened for `RESIZED`, so a fullscreen switch changed the window
and told nobody: viewports kept the old rects and the scene drew for the old
size. Listening for `SIZE_CHANGED` covers both, and the driven run is what shows
it — the border coordinates move from 616 to 776 when the switch lands.

**A second answer landed with it.** Re-layout is what this example shows, and it
is right for a HUD; a play area usually wants the opposite — keep the design
size and scale it onto the window. That is `RGame::Game.new(scale_mode:)` over
`RGame::Engine::Presentation`, with `:integer` for pixel art. It also fixed a
bug this example shipped with: a game opened with `fullscreen: true` had its
viewports sized to the *requested* width and height while the window was the
screen, and no resize event ever fires to correct it, because the size never
changes.

One environment note for anyone driving this: under Xvfb with no window manager
the window does not shrink back on the way out of fullscreen, because nothing is
there to restore it. `#fullscreen?` still flips correctly; the size does not.

**Assets:** none. This example runs on a fresh clone.

### 7. `examples/save_load` — saving and restoring game state — **done**

**Shows** writing state to disk and reading it back on the next run.

**Existing:** nothing. There is no persistence anywhere in the project.

**New:**

- `RGame::Util::SaveFile` (pure Ruby, `lib/rgame/util/save_file.rb`). It is a
  value-shaped thing with no OS handle held open, so it is **Util**, not Core —
  the rule in CLAUDE.md, "Value objects go in Util". JSON via stdlib, so the
  "no runtime dependencies" rule holds.
- **Atomic write** (temp file + rename). A half-written save is a corrupted save,
  and a game writing on quit is exactly when a crash happens.
- A per-OS save directory helper: `$XDG_DATA_HOME` / `~/.local/share` on Linux,
  `~/Library/Application Support` on macOS, `%APPDATA%` on Windows. All three are
  CI-gated platforms, so this needs to be right on all three rather than on
  Linux.
- **A corrupt or missing file must not raise into the game.** Returns the
  default. Assert it in the spec, with a deliberately truncated fixture.

**Deliberately not built:** automatic scene-graph serialization. The example
writes an explicit Hash and reads it back. That is not a shortcut — it is what
Godot, Unreal and Unity all land on, for the same reason: **a scene is a recipe
and a save file is state.** Only an ECS whose graph is already data (Bevy's
`DynamicScene`) can serialize the graph itself.

**Which raised the question the example had to answer:** with no node identity —
an rgame node has no name, no path and no id — how does a load put the dog's
position back on the dog? Two answers, and the example uses both:

- **A singular thing needs no identity, because a variable is one.** `@dog` is
  set where the dog is built and written straight to on load. The code that made
  it never lost track of which one it was.
- **Interchangeable things use their order.** The flock is an array; the save is
  an array of positions; loading zips them. If two sheep swapped, nothing
  observable changed — which is what "interchangeable" means.

The example states what breaks that: a flock whose members can die and must keep
their own state needs a real id. `Components::Identity` is the mechanism, and
`examples/save_load_ids` (7a below, 9a in the order) is where it is shown. The engine supplies the
component; a game decides what gets one, what the ids are, and how they are
handed out — the same division as `Timer`, which counts without an opinion about
what happens next. Bolting an id onto anything that needs naming is what
Unreal's save libraries and Unity's GUID packages do, for the same reason.

**Also deliberately not done:** restoring velocity. The sheep resume standing
still, because a `WanderController`'s timer is not saved. The example names it,
because the serious version is a game that saves a falling player's position and
not their velocity and restores them hanging in the air.

**Assets:** none.

### 7a. `examples/save_load_ids` — a save that has to name things — **done**

**Shows** the case `examples/save_load` deliberately does not: a collection whose
members can die, and a reference from one saved thing to another.

**Existing:** `Components::Identity`, written for this example and already
specced. `Components::Targeting`, which holds a *node* and is therefore the
worked example of what a save cannot write. `Util::SaveFile`.

**New:** none expected beyond the example itself.

**Why a second one.** Example 9 restores a dog by variable and a flock by array
order, and both are right for what they are. This one breaks each assumption on
purpose:

- **Sheep can be lost.** Once the middle of a list can be removed, an array index
  stops naming anything — the third record is no longer the third sheep.
- **The dog chases a particular sheep.** That is a reference between two saved
  objects, and it is what genuinely forces ids: a collection can always be
  respawned from its own records, but a reference *into* it cannot be written
  without a name for what it points at.

**The shape it should teach:**

- every sheep gets an `Identity` when it is spawned;
- the save holds a record per sheep including its id, and the dog's target as an
  **id rather than a node** — `Identity.of(target)` is exactly that conversion;
- loading rebuilds the flock from the records, then re-links the dog by finding
  the saved id in the new flock;
- **the id allocator is part of the save.** A counter that restarts at 1 reissues
  ids the restored sheep already hold, and the collision surfaces later as a dog
  chasing the wrong animal. One number, easy to forget, and the best reason this
  is an example rather than a paragraph.

**Also worth showing:** a save whose target no longer exists. The reference has
to survive pointing at something that is gone — the honest answer is that the dog
picks a new target, not that loading raises.

**How it came out.** Three driven runs against one save directory show the whole
thing. Shearing two sheep out of the middle leaves `[1, 4, 5, 6]` in the file —
the survivors keep their numbers, which an array index cannot manage — with
`target: 5` and `next_id: 7`. A second process, given no input at all, draws the
tether ending exactly where sheep 5 was saved. A third presses **N** after
loading and gets sheep **7**; had the allocator not been in the save it would
have been 1, a duplicate of a sheep already standing there.

The example also states something the plan had half-wrong: **a changing
collection does not by itself force ids.** A flock can always be saved as records
and rebuilt from them, whatever died. What cannot be written that way is the
*reference* from the dog to one particular sheep, and that is the honest reason
`Identity` exists.

**Assets:** none.

### 8. `examples/menu_navigation` — a main menu and a settings menu — **done**

**Shows** more than one screen: title → settings → back, and settings that
change something real.

**Built:** `UI::OptionItem`, one row per setting, over fullscreen, the scale mode
and master volume — all applied the moment they change and written to a
`SaveFile` on every change. `Menu` grew `add_option` and a seam: vertical input
belongs to the menu, horizontal to the focused row, which the menu reaches
through `MenuItem#adjust` without knowing what kind of row answered.

**The open question is settled: one control, not two.** An `OptionItem` over
`[0, 25, 50, 75, 100]` is enough for volume, and a `SliderItem` would have been
a second control with its own focus and draw behaviour earning nothing this
example needed. `docs/api/ui.md` now says a continuous control is missing rather
than pretending otherwise.

**Values clamp, focus wraps** — decided while writing. A list of items has no
magnitude, so joining its ends only makes a short list quicker to get around; a
list of *values* usually does, and wrapping turns "one louder" at the top of a
volume range into silence.

**A settings file is untrusted input, and that has teeth here.**
`Game#scale_mode=` raises on a mode it does not know, so a hand-edited file or
one written by a newer version of the game is otherwise a game that will not
start. `Settings#load` checks every value against the list the menu offers, and
`OptionItem#value=` ignores a value the list no longer has — the same rule at
both ends. Driven against `{"scale":"holographic","volume":9999}`, it starts.

**Push and replace turned out to be the example's best half.** A SceneStack
updates only its top scene but draws all of them, so the choice is one question:
should the thing underneath still be there? Settings is *pushed* over the title
and the title keeps drawing behind it, which is why the settings screen needs a
panel at all. Play *replaces* the title. The driven report shows both.

**One gotcha worth carrying to the next example.** A proc written at the top
level of a script captures that script's locals — including `game` — and a
constant holding that proc pins them for the life of the process. The window is
then never released, and it surfaces not as a leak but as the process dying on
the way out with the driven report still in an unflushed buffer. The tables in
this example live inside a class for that reason.

**Assets:** **C**, already shipped by example 3.

### 9. `examples/jump_topdown` — a hop in a top-down view — **done**

**Shows** that in a top-down game a jump is a *drawing* offset, not a change of
position: the character's ground position stays authoritative for collision
while the sprite arcs above it.

**Existing:** `Components::TileCharacterBody`, `Components::TileWorld`,
`Components::AnimatedSprite`.

**New:**

- `Components::Hop` — starts on a jump action, integrates a parabola in
  `update(dt)`, exposes `height` and `airborne?`. Two rules it must not break:
  it never reads a clock (CLAUDE.md, "`draw` renders state"), and the height is
  applied at *draw* time as an offset, not by moving the node — otherwise the
  feet box leaves the ground and collision goes with it.
- A shadow: an ellipse under the character that shrinks with height. The
  renderer has `circle`; a squashed one can be drawn inside `renderer.scaled`.
- `airborne?` is the seam a game reads to let a hop cross a one-tile gap. Whether
  `TileWorld` should consult it is an **open question** — it may be enough to
  leave that to the game and keep the component ignorant of tiles.

**Assets:** **A** and **B**, both already committed by then. No new art.

**Landed.** `examples/jump_topdown/main.rb` plus its drive script,
`Components::Hop` with its spec, and `Node2D#elevation`, which `Sprite` and
`AnimatedSprite` draw lifted by. The scene is `examples/collision_tiles` less the
spiky ball: `TileWorld`, a `Hero` with `AnimatedSprite`, `FeetCollider`, a blocked
`CharacterBody`, `PlayerController`, `Hop` and `CameraFollow`. The hero's
`on_draw` draws the shadow and the feet box, which is the half of the hero that
stays on the ground.

Run: `rake spec` 1412 examples, 0 failures; RuboCop clean. `make test` and
`rake spec:core` were not run: nothing in C or `RGame::Core` changed. Deleting
`Hop`'s elevation write, either sprite's lift, or reading `held?` for `pressed?`
each fails the new specs. The driven run at 170 ticks reports `sprite` y
spanning −18.0..0, the shadow's `circle` radius spanning 0.5..1.0, `rect` and
`circle` at constant local positions, and the last `tilemap` at camera
(72.0, 77.0) — the hero stopped at the fence despite a hop pressed there with
south still held.

What the sketch did not know:

- **The height needed somewhere to live, and it is the node.** Components draw
  one after another inside `draw_content`, so `Hop` cannot wrap its siblings'
  drawing in a translate. The alternatives were the sprite looking up an optional
  `Hop` sibling — one component handing its data to another, the smell CLAUDE.md
  names — or offsetting the node's whole draw, which lifts the shadow and the feet
  box too and makes each cancel it. Decided in the prompt: `Node2D#elevation`,
  outside the transform, written by `Hop` and read by the two sprite components.
  Any later lift (a knockback, a bob) uses the same field.
- **The open question is answered no.** `TileWorld` does not consult
  `airborne?`, and `Hop` knows nothing about tiles. Which tiles a hop clears is a
  rule of one game; the example says so under "What this does not solve".
- **The arc is closed-form, not integrated.** Height is `4·peak·t·(T−t)/T²` of the
  accumulated time, so it peaks at exactly `peak` whatever the step size, and a
  spec asks for the height at 0.125s rather than stepping there.
- **First and last could not see a hop.** A run starts and ends on the ground, so
  the harness report showed a sprite that never moved. `Report` keeps each numeric
  argument's range and prints `spans` for the ones that varied, which is what shows
  the picture leaving the ground. The same span cannot show a shadow shrinking
  through `renderer.scaled`, because the presentation's own `scaled(1.0, 1.0)`
  shares that line and swamps the range. The shadow shrinks through the circle's
  radius instead.
- **`:jump` stays out of `InputMap::DEFAULT_ACTIONS`.** The example merges it in,
  the way `examples/fullscreen` declares `:fullscreen`; one example needing a
  button is not a reason for every game to have the action.
- **`jump` returns nothing.** Returning whether a hop started trips
  `Naming/PredicateMethod`, and `airborne?` already answers it.

Documented in `docs/api/components.md` (a `Hop` section, and the lift under
`AnimatedSprite` and `Sprite`), `docs/api/scene_graph.md` ("Elevation"), and
`docs/api/examples.md`.

### 11. `examples/radial_menu` — a controller-driven radial menu — **done**

**Shows** selection by *direction* rather than by list position, which is the
thing a stick is good at and a d-pad list is not.

**Existing:** `PlayerLayer`, `Players` / device seating, `ActionMapper` axes,
`renderer.circle` / `triangle` / `line` / `text`, `--gamepad` mode in the drive
harness (so this is testable with a synthetic SDL pad, no hardware).

**New:**

- `Engine::UI::RadialMenu`. Reads two axes, applies a **dead zone**, converts the
  vector to an angle and snaps it to a sector. Below the dead zone nothing is
  selected — releasing the stick at centre must not activate whatever was last
  under it.
- Needs raw stick axes as actions. `move_x`/`move_y` exist and are already on
  the left stick; whether the radial should read those or declare its own
  `ui_radial_x`/`_y` is an **open question** — reusing `move_x` couples the menu
  to the walk controls, which is fine for one player and wrong the moment both
  are live at once.
- **Drawing wedges.** Start with icons/labels placed on a circle plus a
  highlight ring, using only primitives that exist. Only if that reads badly, add
  a `Renderer#pie` (an arc as a triangle fan). That is a renderer method, so it
  would also need the `a_renderer` shared contract, `FakeRenderer`, and its
  refusals matched — CLAUDE.md, "A fake must refuse what the real thing
  refuses". Avoid it if the icon ring is enough.

**Assets:** none to start — sectors labelled with the shipped font. Asset **D**
(an icon sheet) is what a real radial menu shows, and is deferred until the
menu itself works; the mechanism being taught is direction-to-sector, not the
picture in the sector.

**Landed.** `Engine::UI::RadialMenu` with its spec, two new actions in
`InputMap::UI` (`ui_radial_x` / `ui_radial_y`), `examples/radial_menu/main.rb`,
and two drive scripts: `tools/drive/examples/radial_menu.rb` on the keyboard and
`radial_menu_pad.rb` for `--gamepad`. Eight colours on a ring, one of them
disabled; the chosen one fills the middle, and a caption drawn last names it.

Run: `rake spec` 1434 examples, 0 failures; RuboCop clean over every touched file.
`make test` and `rake spec:core` were not run: nothing in C or `RGame::Core`
changed. `game_menu` and `input_glyphs` drive to the same reports as before the
new actions joined every map. `RadialMenu#on_control` allocates 2 objects over
200,000 calls.

The acceptance evidence is the caption, read off the last `text` call at several
budgets. Keyboard: Yellow at 35, still Yellow at 65 with the arrows on Blue,
**still Yellow at 100** after Enter pressed at rest, still Yellow at 130 with
Locked confirmed, Teal at 180. Making the selection sticky below the dead zone
turns the 100-tick result into Blue, and fails two specs. Synthetic pad: nothing
chosen at 38 after A on a 0.35 nudge (pointer tip at 35.3, inside the 75 px dead
zone disc), Yellow at 60, still Yellow at 112 after A at rest.

What the sketch did not know:

- **The open question is answered: its own axes.** `ui_radial_x` / `ui_radial_y`
  join the universal UI set, bound to the left stick, the arrows and the d-pad.
  Same stick as `move_x` by default, but separate actions, so a game can move the
  wheel to the right stick without rebinding how its players walk. Being in the
  universal set is what lets the example declare nothing, the way a `Menu` does.
- **"No assets" was half wrong, the same way it was for `game_menu`.** The items
  are `UI::MenuItem`s, which draw nine-slices, so the example registers asset
  **C**. That was the three-pile sort's answer rather than an accident: `Menu` and
  `RadialMenu` answer the same question about an item — which one is focused,
  and activate it — and what an item *is* does not change with how it is chosen.
  Only the focus rule is new. `Menu`'s focus bookkeeping was not shared: it moves
  relative to itself, wraps, and is never empty, where this one is absolute and
  empty below the dead zone, and the overlap came to a handful of lines.
- **No `Renderer#pie`**, so the second half of the open question is answered too.
  A filled disc for the backdrop, a smaller one for the dead zone drawn to scale,
  and a line for the pointer read clearly; nothing in the contract changed.
- **The dead zone is a length, and it sits on top of the per-axis one.**
  `ActionMapper` already takes 0.15 off each axis and rescales, so a raw 0.35
  reaches the wheel as 0.235, and the wheel's 0.5 corresponds to about 0.58 raw
  along an axis. The two are kept apart on purpose: the per-axis one stops drift
  and is far too small to decide a player means a direction.
- **`each_with_index` allocates.** `Menu#focus` uses it and is fine, because it
  runs on a keypress; `RadialMenu` refocuses every frame, and the first version
  allocated one object per frame for it. `each_index` does not.
- **A digital diagonal is longer than a stick.** Two arrow keys read as (1, 1), so
  the example clamps its pointer to the ring. The menu itself does not care: only
  the angle and whether the length clears the dead zone matter.
- **A pad script needs `--gamepad`**, so the example has two scripts rather than
  one. Under the scripted backend the keyboard holds the seat and a pad track
  would first have to take it over; the keyboard script is the default, and the
  pad script is the one that can exercise a deflection that is real but too
  small.

Documented in `docs/api/ui.md` (a `RadialMenu` section, and "What this is not"
widened to two menus), `docs/api/input.md` (the universal set), and
`docs/api/examples.md`.

### 12. `examples/pathfinding` — a character walking a computed route

**Shows** a click-free "go there" — pick a target tile, compute a route around
the solid tiles, walk it.

**Existing:** `Engine::Path` (an ordered polyline with precomputed segment
lengths) and `Components::PathFollow` (walks a `Path` at a constant speed,
allocation-free, emits `on_finished`). **These are the output end and they
already exist** — the missing half is only the search that produces the
waypoints.

**New:**

- `Engine::NavGrid` — walkability derived from a `TileMap` / `TileWorld`, so the
  search does not have to know what a tile is.
- `Engine::AStar.find(grid, from, to) #=> Engine::Path | nil` — A* with a
  Manhattan/octile heuristic and a binary-heap open set. Pure Ruby, pure logic,
  no graphics: fully spec-able headless, which is the whole argument for it
  living in `lib/rgame/engine/`.
- Returning an existing `Path` is the design point worth stating out loud: the
  new code is one function, and everything downstream is already written and
  already tested.
- **`nil` for unreachable, not an exception and not an empty path.** An
  unreachable target is an ordinary answer.
- **The walker can be blocked.** `PathFollow` is a `Mover`, so
  `PathFollow.new(path:, speed:, blocked_by: %i[tiles npc])` walks the route and
  waits behind anything standing on it, then resumes where it stopped. The route
  itself avoids solid tiles. `blocked_by` covers what the search could not know
  about, such as another character.
  It waits rather than going round: a held `PathFollow` rewinds its step and aims
  at the same point again, so it does not slide along a blocker the way a
  `Velocity` does. A walker that should get past a character standing on its route
  has to replan.
- **Open question — where does the walker get its facing?** `AnimatedSprite`
  reads `move_x`/`move_y` off a sibling `CharacterBody`, and `PathFollow` has no
  intent, so a hero walking a path would slide around the map unanimated. This was
  deferred from the component-architecture sweep to be answered when this example
  is written. It blocks the example's animation, not its walk.
- Path smoothing (drop waypoints a straight line already covers) — worth it,
  because raw A* output on a grid zig-zags and looks wrong when walked.

**Performance note:** A* runs on demand, not per frame, so plain Ruby is the
right call and the `Game/NoNeedlessAllocation` cop's concerns do not apply.
If profiling on a large map ever says otherwise, `ext/rgame_util/` is where it
would go — pure logic, no SDL — but **do not start there**.

**Assets:** **A** and **B**. Nothing new — though **B**'s map wants a shape
with a wall worth going around, or the search has nothing to show. Note that
under "Assets".

### 13. `examples/sprite` — one frame, no animation — **done**

**Shows** the plain sprite: an image drawn at a node, with no animation state
behind it. It is the half of `AnimatedSprite` that is left once the walk cycle
is taken away, and most things in a game are this — a crate, a pickup, a rock.

**Existing:** `Components::Sprite`, `renderer.register_image`, `Image#subimage`.

**New:** nothing.

The points worth making, and there are exactly three:

- **It passes no position and no angle.** `Node2D#draw` has already pushed the
  node's transform, so drawing at `(0, 0)` *is* drawing at the node, correctly
  rotated. Passing either would apply it twice. Rotate the node and the sprite
  turns for free — which is the clearest possible demonstration of what the
  transform stack is for.
- **`z` is the render layer, not the node's transform z.** The component keeps it
  under `@layer` to say so, and an example is where that distinction stops being
  a comment nobody reads.
- **`scale` is writable** because a pooled entity retunes it on reset — a forward
  reference to example 17 rather than something this example needs.

**Open question — what image.** `Sprite` takes an image *id*, and both assets on
hand are sheets, so drawing `'hero.png'` whole shows the entire strip. Leaning
toward showing both id spaces: one node drawing a whole image by path, another
drawing a registered `subimage` of the sheet, which also makes the point that
slicing a sheet costs no second decode. Decide when writing; a new asset is not
warranted for this.

**Assets:** **A**, already committed.

### 14. `examples/velocity` — movement with nobody driving — **done**

**Shows** the other way a node moves. Every example so far has used
`CharacterBody`, which turns an *intent* in -1..1 into a step at a speed. A rock
has no intent: it has a velocity, and something integrates it.

**Existing:** `Components::Velocity` (vx / vy / spin), `Components::ScreenWrap`,
`Components::World`.

**New:** nothing.

- **`spin` is why this pairs with 13.** Angular velocity integrated into the
  node's angle, and the sprite on it turns without the sprite knowing.
- **`ScreenWrap` needs to know how big the world is, and does not ask the
  scene.** It reads `node.system(WorldBounds)` — a *contract*, answered here by
  `Components::World` and in a tiled game by `Components::TileWorld`, so the same
  component wraps correctly in both without a branch. That indirection looks like
  ceremony until you see the two implementations, which is what this example is
  for.
- Bounds are re-resolved on every attach rather than cached, so a recycled entity
  wraps against the scene it landed in. Another forward reference to 17.

**Assets:** none — coloured shapes, and the drift is the subject.

### 15. `examples/signals` — a node announcing that something happened — **done**

**Shows** declaring a signal of your own. Every example so far has *consumed*
signals the engine declares — `on_activated`, `on_changed` — and none has
written `signal :on_something`, which is the half a game actually does.

**Existing:** `Engine::Signal::DSL` (`signal :name`, `Signal.define(:field)` for a
typed one), the connect handle and `disconnect`, `Components::ActionTrigger`.

**New:** nothing.

- **Why a signal rather than the node calling its listener.** A pressure plate
  does not know what a door is, and should not have to be handed one to be
  useful. The example is a plate and two unrelated things that react to it, and
  the whole point is that the plate names neither.
- **`connect` returns a handle, and `disconnect` takes it.** A listener that
  outlives its interest and is never disconnected is the leak nobody sees; show
  one being dropped.
- **A typed signal carries a payload**, and `Signal.define(:action)` is what
  `ActionTrigger` uses — so the example ends with one component emitting an
  action name and a listener filtering on it, which is the shape a game reuses
  for "fire" here and "jump" somewhere else.
- **Emitting is private.** The DSL generates a public `on_x(&block)` to subscribe
  and a private `on_x_signal` to emit on, so only the host can fire its own
  signal. Worth a sentence: it is the same "give the user a blank hook, keep the
  machinery separate" rule the rest of the engine follows.

**Assets:** none.

### 16. `examples/timer` — things that happen on a clock — **done**

**Shows** periodic behaviour that no input drives: a spawn cadence, a fire rate,
a wave clock.

**Existing:** `Components::Timer` (repeating and one-shot, `on_timeout`), and the
pure `Engine::Timer` underneath it.

**New:** nothing.

- **The remainder rolls over.** `consume` carries the leftover forward, so a
  cadence does not drift against a variable frame — and a metronome next to a
  hand-rolled `@elapsed += dt; if @elapsed > interval; @elapsed = 0` drifts
  visibly against it in a driven run. That comparison is the example.
- **It rides the node's tick**, so nothing can forget to advance it. Contrast
  with `examples/sound`, which accumulates its own flash by hand — correct there,
  because a fade is not an interval.
- **The countdown restarts in `on_attach`**, which is the line that makes a
  pooled node safe: a recycled projectile gets its full life rather than
  inheriting the previous one's. Say it here; example 17 relies on it.
- **One component per slot**, so a node wanting two cadences names them with
  `as:`.

**Assets:** none.

### 17. `examples/pooling` — spawning without allocating — **done**

**Shows** why a game that spawns things does not build them. A steady 60fps
frame that allocates is a GC pause waiting to happen, and a bullet is the
canonical thing there are suddenly two hundred of.

**Existing:** `Components::Pool` and `Engine::Pool`, `queue_free`,
`Components::DespawnOffscreen`, plus the Timer from 16 to drive the spawn.

**New:** nothing.

- **The game writes `pool.spawn` and `node.queue_free`, and nothing else.**
  Acquire, add as a child, reclaim on free — all of it rides the tick inside the
  component. A hand-written acquire/add/reclaim bridge is exactly the remembered
  rule "Design out misuse" rejects.
- **A pooled node is an ordinary child.** The scene's normal traversal updates
  and draws it; the pool only manages membership. That is the sentence that stops
  a reader thinking pooling is a parallel world with its own rules.
- **Measure it.** Spawn on a timer for a few hundred ticks and report allocations
  in steady state — the number is the argument, and every other claim in this
  file is prose. `ObjectSpace.count_objects` around a stretch of ticks is enough.
- `DespawnOffscreen` retires them, resolving bounds the same way `ScreenWrap` did
  in 14, so the pair reads as one idea seen twice.

**Assets:** none.

### 18. `examples/collision` — two shapes touching — **done**

**Shows** object-to-object collision: a scene-scoped system that pairs up shapes
each frame and tells them they overlapped.

**Existing:** `Components::CollisionWorld`, `BoxCollider`, `CircleCollider`,
their `on_hit` signal, and `Velocity` from 14 to move things into each other.

**New:** nothing.

- **The system lives on the scene and the shapes live on the nodes.** Colliders
  register on entering the tree and unregister on leaving, so a spawned or
  despawned entity cannot leak a registration — the engine fires both hooks, and
  no game code is asked to remember.
- **`layer` is an opaque tag and the system does not read it.** `CollisionWorld`
  reports contacts; what a contact *means* is the listener's business. Two layers
  and one handler that ignores same-layer pairs is enough to show why.
- **A box and a circle collide with each other**, because both answer one
  broadphase and narrowphase protocol and settle the pair between themselves. Do
  not hide that: a reader assuming shapes only meet their own kind will build
  around a limitation that is not there.
- **An AABB does not rotate with its node.** Put a spinning thing on a
  `CircleCollider` and a still one on a `BoxCollider`, and say that is the
  choice rather than a preference.
- **The broadphase is a spatial hash**, and `cell_size` is the one number a game
  has to pick. A sentence on how to pick it — about the size of the things being
  bucketed — is worth more than the algorithm.

**Assets:** none — shapes, drawn as shapes.

### 19. `examples/collision_tiles` — walking into a wall — **done**
**Landed.** `examples/collision/main.rb` plus `tools/drive/examples/collision.rb`.
A scene mounting `CollisionWorld` and `World`; a `Mover` base carrying the
`CircleCollider` and the one-line layer rule, with `Drifter` (velocity + spin)
and `Walker` (character body + player controller) under it; four `Crate`s with
`BoxCollider`s, two of them overlapping on purpose. The broadphase lattice is
drawn on the backdrop at `cell_size`, which is what makes that number a thing a
reader can look at rather than a constant to take on trust.

Run: `rake spec` 1134 examples, 0 failures; RuboCop clean; the driven run at 240
ticks reports 240 ticks / 240 frames, 21 `rect` and 7 `text` per frame flat, 4
`circle` and 4 `line`, 478 `rotated` (two spinners, less the first frame at angle
zero), one clip per frame, and `visits: 3` as the last `text` — the three
arrivals the script drives.

What the sketch did not know:

- **`on_hit` is level-triggered *and* can fire twice in one step.** The
  `SpatialHash` dedup contract lets a collider be yielded once per shared cell,
  and `CollisionWorld#update` does not deduplicate, so a pair overlapping across
  two cells reports two contacts per step. Measured: a circle centred in a crate
  gives 2 emits per step, and the two overlapping crates give 4 between them. A
  counting handler is therefore wrong twice over, and the first draft's per-crate
  counter read 419 contacts in 240 ticks. The crate now records *that* a contact
  happened and detects the edge in `on_update` — which is safe because a child's
  `on_update` runs after the scene's components. This was documented in
  `SpatialHash` and nowhere a user of `CollisionWorld` would look;
  `docs/api/components.md` now says it under `CollisionWorld` and from both
  colliders' `on_hit` bullets.
- **The counter's honest unit is "the crate went from untouched to touched".**
  Telling two simultaneous visitors apart needs the set of colliders in contact
  last step, which is a per-frame collection where this is two booleans. The file
  and the drive script both name the compromise rather than letting the number
  look like something it is not.
- **An example node built in `initialize` needs no `on_add` at all.** The
  collider's `on_attach` wants the scene's system, and attachment is deferred
  until the node enters the tree, so the whole component stack composes in
  `initialize` and the order is irrelevant — the same rule `examples/pooling`
  arrived at from the other direction.

### 19. `examples/collision_tiles` — walking into a wall

**Shows** the *other* collision problem, and that it needs different machinery.
A character against a grid of solid tiles is not a pairwise overlap test: there
are no pairs, there is a grid query.

**Existing:** `Components::TileWorld` (already shown in `examples/scroll_map`, as
the thing that owns the map), `Components::TileCharacterBody`, asset **B**.

**New:** nothing.

- **Read against 18, deliberately.** No `CollisionWorld`, no colliders, no
  `on_hit` — and the reason is that a tile map already knows what is where, so
  bucketing it into a spatial hash would be paying twice for an index that
  exists. Two examples that both say "collision" and share no code is the point.
- **A feet box, not the sprite's box.** A top-down character collides with a
  small rectangle at the bottom of the sprite, which is what lets them walk
  "behind" the top half of a wall. Draw the box.
- **Sliding is the whole feel.** Walking diagonally into a wall keeps the
  component of the movement that is not blocked, and a version that simply
  stopped would feel broken without a player being able to say why.

**Ordering note.** Plain collision comes first because it is the general
mechanism; the tiled one comes second because it is the specialised one *and*
because Phase E's jump example builds straight on top of it.

**Assets:** **B**, already committed. Its map may want a wall arrangement worth
sliding along, the same way example 12's wants one worth routing around.

### 20. `examples/split_screen` — two players, one world — **done**
**Landed.** `examples/collision_tiles/main.rb` plus its drive script. The scene
is `examples/scroll_map`'s three steps — tilemap asset, `TileWorld`,
`WorldView` + `TileMapLayer.mount` — with a `Hero` that has an `AnimatedSprite`,
a `TileCharacterBody`, a `PlayerController` and a `CameraFollow` offset onto the
feet. The hero draws its own `collision_box` translucently over the sprite, which
is the "draw the box" the sketch asked for and costs one `rect` at a constant
local position.

Run: `rake spec` 1134 examples, 0 failures; RuboCop clean; the driven run at 240
ticks reports 240 ticks / 240 frames, 3 `text`, 2 `tilemap`, 1 `sprite` and 1
`rect` per frame, two clips per frame, and the last `tilemap` at camera
(0.0, 160.0).

What the sketch did not know:

- **The map needed no new wall arrangement.** `town.tmx`'s fence — full width but
  for the gap at columns 12 to 14, authored for the pathfinding example — is
  already the best sliding demonstration available, and it doubles as the
  acceptance test: the hero starts ten tiles east of the gap holding down-and-left
  and can only reach the south of the map by sliding into it. A body that dropped
  the whole blocked step would sit at the fence for the entire run, so the
  camera's southern clamp appearing in the report *is* the proof that sliding
  works.
- **The first frame is drawn before anything updates.** Its `tilemap` call reports
  the camera at (0, 0) and the second reports (72, 51), which is where
  `CameraFollow` puts it. Worth knowing before reading a first-frame coordinate
  out of any report as though it were a starting position.
- **Nothing about the two collision examples needed reconciling.** They share no
  class, no component and no vocabulary beyond the English word, which is what
  the pair was for; the file says so at the top and points both ways.

### 20. `examples/split_screen` — two players, one world

**Shows** the thing CLAUDE.md calls a headline feature and no example has ever
run: a shared world updated once, drawn once per viewport, with a camera and a
set of bindings per player.

**Existing:** all of it — `Game.new(players: 2)`, `Engine::Players` and seating,
`PlayerLayer`, `WorldView`, `Viewports`, and the drive harness's one-timeline-
per-device scripts. `test_projects/tiled_world` already does this; what is
missing is a file that does *only* this.

**New:** nothing expected.

- **The world does not know how many times it is drawn.** That is the sentence
  the whole design exists to make true, and a split-screen example is the only
  place it can be shown rather than asserted.
- **The screen splits when someone joins, not when a pad is plugged in.** Start
  with one seat filled and one empty: the game opens full-screen, and a `ui_confirm`
  on the controller seats player two and splits it. `Players#on_seated` is how the
  scene learns to spawn the second avatar.
- **Ownership is inherited down the tree**, so each player's HUD reads that
  player's input without either subtree mentioning players. Give both a small
  per-player overlay so the point lands.
- Keep the world trivial — a floor and two walkers. Every earlier example put its
  subject in the world; this one's subject is the plumbing around it.

**Drive script:** two absolute timelines, keyboard and `controls.gamepad(0)`,
modelled on `tools/drive/test_projects/tiled_world_2p.rb`. The report should show
one clip per active viewport per frame, going from one to two at the join.

**Assets:** **A**, already committed.

### 21. `examples/input_glyphs` — the prompt matches the thing in your hand — **done**
**Landed.** `examples/split_screen/main.rb` plus its two-timeline drive script.
A `Ground` node under a `WorldView`, a `Walker` per player (the walk example's
hero with a `CameraFollow` and a coloured banner), and a `Badge` under a
`PlayerLayer` per player counting that player's `:fire` presses. The scene bounds
every seat's camera — including the empty one's — mounts the world, and spawns on
`each_active` plus `on_joined`.

Run: `rake spec` 1134 examples, 0 failures; RuboCop clean; the driven run at 240
ticks reports 240 ticks / 240 frames, three clip rectangles (the full window 302
times, and each half 418 times), 499 `sprite` calls, 898 `:hud` layers against
2005 `:world`, and `waves: 1` as the last `text`.

What the sketch did not know:

- **The signal is `Players#on_joined`, not `on_seated`.** The plan named a method
  that does not exist.
- **The walkers had to start side by side, and that turned into the best thing in
  the file.** Started far apart, each is culled out of the other's viewport and
  the sprite count is a flat one per viewport — which reads as "each player sees
  only themselves" and is the opposite of the point. Side by side they appear in
  both halves and then drop out as they separate: 499 sprite draws rather than the
  449 of one each, with the extra 50 being the frames both halves could see both.
  `Engine::Culling` exists because of split-screen, so the example now shows it.
- **A node's own `on_draw` is not culled, only clipped.** Culling lives in the
  components that know a node's footprint, so `Walker`'s banner is drawn in every
  viewport and scissored away in the wrong one. Said in the file, because a reader
  comparing the sprite count against the rect count would otherwise find it
  inconsistent.
- **Ownership was verified by its counterfactual, not by inspection.** A run in
  which only the keyboard waves three times leaves player two's badge reading
  `waves: 0`; if either subtree read the other's device, or the raw input, it
  would read 3.
- **`--gamepad` cannot drive this example.** That mode points player one at slot 0
  and leaves the real backend in place, so no device is unassigned and nobody can
  join. The scripted backend is the right tier for a join, which is what
  `tiled_world_2p.rb` already did.

### 21. `examples/input_glyphs` — the prompt matches the thing in your hand

**Shows** switching between keyboard and controller mid-session, and a UI that
says "Press A" or "Press Space" depending on which was used last. It is the most
visible piece of polish in this whole list and the one players notice
immediately when it is missing.

**Existing:** `Players#on_unassigned_input = :takeover` — with a single seat, a
press on an unassigned device hands it to the primary player rather than seating
a second one, which *is* keyboard-to-controller switching and is already the
default for a one-seat game. `Player#device` says which device that is.

**New — the largest addition in this phase, and it lands in two layers:**

- **A device-kind question, in `Util`.** `Controls` has `KEYBOARD = 0`,
  `GAMEPAD_FIRST = 1` and `PAD_A = 4096`, so the two id spaces are already
  disjoint — but there is no named boundary and no predicate, so every caller
  would rediscover the constant. Add `Controls.gamepad?(device)` and a pad-button
  test with the boundary named once. Values, no handles: `Util`, and specced
  against the C header the same way the ids are.
- **"Which of this action's ids apply to my device?"** An `InputMap` entry lists
  keyboard and pad ids together on purpose, because a device only answers for its
  own kind. A prompt has to undo that: given `:fire` and a gamepad, it wants
  `PAD_A` and not `KEY_SPACE`. That is a query on `InputMap` — engine layer, pure,
  spec-able headless.
- **A glyph is an id rendered as a picture**, which is a sprite lookup keyed by
  button id. Keep it in the example first. Promote it to `Engine::UI` only if
  writing it twice proves it wants to be shared.

**Open question — does it switch back?** Takeover fires on a `ui_confirm` press
on an *unassigned* device, and once the pad has taken over the keyboard is
unassigned, so Enter or Space should hand it back. **Verify this before
building the example**, because a game wants "any key returns to the keyboard"
and `ui_confirm` is a narrower promise. If it is narrower, decide whether that
is the engine's bug or the example's constraint, and say which in the file.

**Assets: G, and it is new.** A glyph sheet — key caps and pad face buttons —
with the same CC0-or-authored-here rule as everything in `examples/assets/`.
Kenney's *Input Prompts* is CC0 and is the obvious source; take only the handful
of glyphs the example names, the way **A** was repacked rather than copied
whole. Fewer than a dozen small images.

**Landed.** Engine work in both layers, asset **G**, and
`examples/input_glyphs/main.rb` with its two-timeline drive script.

- `RGame::Util::Controls` gains `BUTTON_GAMEPAD_FIRST`, `gamepad?(device)` and
  `pad_button?(id)`. The boundary is the C engine's own
  (`RGAME_BUTTON_GAMEPAD_FIRST`) and joins the constant map the header spec
  already checks, so it cannot drift.
- `RGame::Engine::InputMap#button_for(action, device)` — the first id bound to
  that action which that device can press, or nil. Allocation-free, so a HUD may
  call it per frame.
- Asset **G** is `examples/assets/glyphs.png` + `glyphs.json`: five 64x64 frames
  in one 3 KB strip, cut out of Kenney's *Input Prompts* (CC0) at 5 MB.

Run: `rake spec` 1147 examples, 0 failures (13 new); `rake spec:core` 367
examples, 0 failures; RuboCop clean over everything touched.

**Acceptance — the open question answered by measurement.** The same drive script
at four tick budgets, reading the last `sprite` call, whose column is the glyph
the `Wave` row drew:

| ticks | column | device |
|---|---|---|
| 40 | 0 | keyboard, Space |
| 100 | 3 | controller, A |
| 150 | 0 | keyboard again, after Enter |
| 240 | 3 | controller again |

What the sketch did not know:

- **Takeover does switch back, through `ui_confirm` and nothing else.** Measured
  headlessly before anything was built: `PAD_A` takes the seat, `KEY_SPACE` hands
  it back, `KEY_W` does not. It is the example's stated constraint rather than the
  engine's bug — the narrowness is the same rule that stops a resting stick
  seating a player, and `:ignore` plus `seat` is the documented way to want
  something else. `docs/api/input.md` said "using it again takes them back", which
  is not true of any key, and now says which press.
- **`button_for` had to return nil for an axis, and that shaped the example.**
  Movement is `move_x`/`move_y`, which are a stick and pairs of keys rather than
  buttons, so the three prompts are all single buttons and the file says why a
  picture for "the arrow keys" is a different question.
- **The glyph lookup stayed in the example**, as the plan leaned. It is one frozen
  hash from button id to column; nothing wrote it twice.
- **The sheet's column order is checked against the example's table.**
  `spec/example_assets_spec.rb` parses `GLYPH_COLUMN` out of the source and
  asserts every column exists in the PNG and that the keyboard glyphs precede the
  pad ones — the same guard as the hero sheet's, for the same reason: a column
  past the end of the strip draws nothing and raises nothing.
- **Anchor a regex that reads an example's source.** The file's own header quotes
  the table in prose, so the first unanchored match read the comment and the spec
  saw one entry instead of five.


---

### 23. `examples/localization` — the same screen in two languages

**Shows** a label that follows the language: text resolved from a translation
table, a value interpolated into it, a count that picks its plural, and a switch
that changes every label at once — without looking anything up per frame.

**Existing:** `Engine::I18n` (`t(key)`, `%{var}` interpolation, `count:`
pluralization, a fallback locale, and `generation`, which ticks on every locale
change), `Engine::CachedLabel`, `UI::Menu` for the switch.

**New:** probably nothing in the engine; the one candidate is below.

The points worth making:

- **`t` is not a per-frame call.** It interpolates, and `**vars` builds a Hash on
  every call. The text is resolved once and re-resolved when `I18n.generation`
  moves, which is the whole reason the counter exists — and the example is where
  that stops being a sentence in `toolbox.md`.
- **A label that depends on both the locale and a value.** "3 apples" has to
  rebuild when the count changes *and* when the language does. `CachedLabel`
  keys on one value, and passing `[count, I18n.generation]` allocates the Array
  it exists to avoid. Whether that wants a two-value `CachedLabel`, a label keyed
  on the generation that is rebuilt by hand on count changes, or something
  simpler is an **open question** — decide it by writing the example, not before.
- **The fallback is visible.** One key missing from the second locale shows the
  first locale's text rather than a raw key, and the example says why that is the
  right failure.
- **The tables are data.** Two YAML files beside `main.rb`, loaded with
  `I18n.load_file`, so the example shows the shape a game's own locale files take.

Before writing it, read `lib/rgame/engine/i18n.rb` properly: its header still
compares it to `EventDispatcher`, which went with Gosu, so it has not been read
against the current engine in a while.

**Assets:** none — the shipped font covers both languages if the second one is
German or another Latin-script language. A non-Latin script would need a font the
engine does not ship, and that is a different example.

## New engine work, gathered

Sorted by where it lands, because that decides who may use it.

| What | Layer | For | Size |
|---|---|---|---|
| `rgame_app_set_fullscreen` / `_fullscreen` + Ruby binding | C + `Core::App` | 4 | S |
| `Util::SaveFile` + save-dir helper | `Util` (pure Ruby) | 5, 6 | S |
| ~~`UI::OptionItem`~~ | `Engine::UI` | 6 | **done** — no `SliderItem`, see 8 |
| ~~`Components::Hop`~~ | `Engine` | 7 | **done** — with `Node2D#elevation` |
| ~~`UI::RadialMenu`~~ | `Engine::UI` | 9 | **done** — with `ui_radial_x` / `ui_radial_y` |
| `Engine::NavGrid` + `Engine::AStar` | `Engine` | 10 | **L** |
| ~~`Controls.gamepad?` + a named pad-button boundary~~ | `Util` (values) | 21 | **done** — plus `pad_button?` and `BUTTON_GAMEPAD_FIRST` |
| ~~"which ids of this action apply to this device"~~ | `Engine::InputMap` | 21 | **done** — `#button_for(action, device)` |
| `Components::CameraPan` | `Engine` | 2 | S, *maybe not needed* |
| ~~`Renderer#pie` + contract + fake~~ | `Core` + contracts | 9 | **not needed** — discs and a line read fine |
| a label keyed on a value *and* the locale | `Engine` | 23 | S, *maybe not needed* |

Everything in the `Engine` rows is pure Ruby with no graphics library, gets specs
in `spec/`, and must not name `RGame::Core` — including in its specs. Everything
in the `Core`/C rows gets `spec_core/` coverage and, for `Renderer#pie` only,
must go through the shared renderer contract *and* `FakeRenderer` before it is
done.

## Assets

### The constraint

**`media/` cannot be used.** Its contents are gitignored because they cannot be
redistributed — the licences do not permit it — which is why a fresh clone does
not have them and why `test_projects/` cannot be run by anyone who has not
assembled that directory themselves. That is tolerable for a test project a
maintainer drives; it is not tolerable for an example, whose entire job is to
run for someone who just cloned the repo.

So: **every asset an example uses is a new file, committed to the repo, under a
licence that permits redistribution.** No exceptions, and no borrowing from
`media/` "just for now" — an example that works only on this machine is worse
than no example, because it looks finished.

### Where they live, and they ship

`examples/assets/`, beside the examples that use them — and **`examples/` is
added to what the gem packages.**

That is a decision, not a detail. An example is documentation that runs, and
`gem install rgame` should put it where someone can run it, the same way the
default font ships as runtime data rather than being looked up on the user's
machine. It also means the licensing rule below is not a formality: these files
are redistributed, by us, to everyone who installs the gem.

**Done.** `examples/**/*` joins the `packaged` glob list in `rgame.gemspec`,
beside `lib/**/*`, `ext/**/*`, `exe/**/*` and `docs/api/**/*`. That was the whole
change — the glob is over whole directories by design, so dropping a file under
`examples/` is enough to get it packaged, and no enumeration has to be kept in
step. A built gem grew by 14.5 KB and carries all six asset files.

**`spec/packaging_spec.rb` gained four examples** (three plus the inverse), in
the shapes that file already used. All four were mutation-checked by removing
the glob entry and confirming they go red:

- **`packages every example, including its assets`** — `sources('examples/**/*') - files`
  is empty. Mirrors `packages every project template`, and for the same reason:
  a missing asset is not a load error, it is an example that crashes at its
  first draw on a machine that installed the gem rather than checking it out.
- **`has no dotfile among the example assets`** — stated *without* going through
  `sources`, exactly as the template dotfile guard is. Both the gemspec and the
  spec derive their lists with `Dir.glob`, which does not match a leading dot, so
  a check that shares the blind spot it is guarding is not a guard. This is a new
  shipped directory, so it inherits the rule: no asset may be named with a
  leading dot.
- **`ships the asset provenance record`** — `examples/assets/README.md` is in
  the gem. Shipping the art without it would distribute the files and leave
  where they came from behind.
- **`excludes the test projects and the drive harness`** — `test_projects/` and
  `tools/` stay out. They depend on `media/`, which cannot be
  redistributed, so shipping them would put files in the gem that only work on
  a machine that has assembled that directory. This is the guard that keeps the
  new glob from being widened into `test_projects/**/*` by anyone who reads the
  two directories as interchangeable.

**Size.** The gem is 1.3 MB today, most of it vendored headers and the shipped
font. A 16×16 tileset and a small character sheet are a few KB each; keep the
whole of `examples/assets/` under a couple of hundred KB and this is noise. If
an asset ever wants to be a megabyte, it is the wrong asset for an example.

**An installed example has to run where it lands.** Two things follow, and
neither costs anything if they are got right the first time:

- The `$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)` line that
  `test_projects/` uses works unchanged, because `examples/` and `lib/` are
  siblings in the installed gem exactly as they are in the checkout — it
  resolves to the gem's own `lib`, which is already on the path. Keep the line
  and keep the comment explaining it.
- `media_root:` must be derived from `__dir__` (`File.join(__dir__, '../assets')`),
  never from the working directory. An example run as
  `ruby ~/.gem/.../examples/walk/main.rb` from somewhere else entirely has to
  find its own art.

### Licensing

**CC0 / public domain, or authored in this repo. Nothing else.** This is a hard
requirement rather than a preference: the gem redistributes these files to every
person who installs it, so anything with an attribution or share-alike
obligation would attach that obligation to `rgame` itself and to everyone
downstream. CC0 has no such tail.

**The test to apply is not "is this licence permissive" but:**

> *Would shipping this file in the gem count as redistributing it?*

Always yes — `gem install` copies the raw file onto a stranger's disk, and so
does a public git clone, so the restriction bites before the gem does. That
question is what settled the one real candidate this ruled out: an itch.io pack
whose terms read "you may use these assets for personal and commercial
projects" but also "redistribution or resale of the raw assets is not allowed".
Permissive for a *game*; disqualifying for a *library*, which is nothing but
redistribution. Asking "is it CC0" was the easy question; this was the one that
needed asking.

The project already has the pattern for shipped third-party content, twice:
`lib/rgame/fonts/` puts `OFL.txt` beside the font it ships, and
`ext/rgame_core/vendor/README.md` names every vendored source and its licence.
Follow it — `examples/assets/README.md` names each asset, where it came from,
and under what licence, with the licence text beside it where one is required.
Both of those precedents are for content the gem *ships*, which is exactly the
case here; the README ships with the assets, by the same glob.

Practical sources for CC0 game art: Kenney (kenney.nl, everything CC0),
OpenGameArt filtered to CC0. Drawing a 16×16 tileset by hand is also entirely
reasonable at this size and sidesteps the question.

### The manifest

Four sets are committed and cover most of the list. One more is needed and one
is deferred.

| | Asset | Files | Used by | Status |
|---|---|---|---|---|
| **A** | Character sprite sheet | `hero.png` + `hero.json` | 1 walk, 7 jump_topdown, 10 pathfinding | **done** |
| **B** | Top-down tileset + a map | `tileset.png`, `tileset.tsx`, `town.tmx` | 2 scroll_map, 7 jump_topdown, 10 pathfinding | **done** |
| **C** | UI nine-slice sheet | `ui.png` + `ui.json` | 3 game_menu, 6 menu_navigation | **done** — and it was never optional |
| **D** | Radial icon sheet | `icons.png` + `icons.json` | 9 radial_menu | not needed — labels read fine |
| **F** | A sound effect and a music loop | `blip.ogg`, `music.ogg` | 4 sound, 5 music | **done** |
| **G** | Input prompt glyphs | `glyphs.png` + `glyphs.json` | 21 input_glyphs | **done** |

**A and B are in `examples/assets/`**, about 10 KB in total, with full
provenance in `examples/assets/README.md`. A is sodri's CC0 *Character 4
directional walking*, background keyed out and repacked into a uniform 16x22
grid; B is Kenney's CC0 *Tiny Town* copied unchanged, with a `.tsx` and a
`.tmx` authored here. What follows is what they had to satisfy, kept because it
is what a replacement would have to satisfy too.

Nothing else in the list needs a file: 4 fullscreen and 5 save_load draw with
primitives and the shipped font, 6 menu_navigation adds only the nine-slices of
**C**, and everything in Phase D except `sprite`, `collision_tiles`,
`split_screen` and `input_glyphs` is coloured shapes on purpose — the subject in
each case is the movement, the cadence or the contact, and art would only be
something else to look at.

**G is delivered**, and it went exactly the way the sketch expected: five 64x64
frames cut out of Kenney's CC0 *Input Prompts* into one 3 KB strip, against a
5 MB download. Space, Enter and Escape from the keyboard set; A and B from the
**Xbox** set, because SDL's button names are Xbox's and a sheet whose faces
disagreed with `PAD_A` would make every prompt a translation. The column order is
the example's own lookup table, and `spec/example_assets_spec.rb` reads that table
out of the example and checks it against the strip.

**A — character sprite sheet.** A four-direction walk cycle plus an idle, which
is what `Components::AnimatedSprite` and `AnimationSet` expect — they resolve
`stand` / `walk_up` / `walk_down` / `walk_left` / `walk_right` by name, so those
five keys are the real contract. The `.json` descriptor is **ours**, in the
format `docs/api/assets.md` documents. `flip_x` mirrors a frame inside the same
rectangle, so `walk_left` reuses the `walk_right` row and the sheet is three
rows rather than four — verified frame by frame against the source rather than
assumed. The delivered sheet is 6 columns x 3 rows of 16x22.

Two things worth knowing if this is ever replaced: the source had **no
transparency** (opaque white background, which had to be keyed out after
checking white was never used inside the art), and **no idle frame**, so
`stand` is a single column off the walk cycle.

**B — tileset and map.** 16×16 or 32×32 tiles, with enough variety for ground,
a solid obstacle and an edge. Two things about the authoring, both of which
have to be right or the examples that use it silently misbehave:

- **Solidity is baked into the `.tsx`, not into the engine.** `Engine::Tileset`
  reads a tile as solid when it carries a Tiled collision shape — an
  `<objectgroup>` on the tile — so the collision has to be drawn in Tiled's
  collision editor. There is no solid-tile list in code to fall back on.
- **Layer data must be base64 + zlib.** `TileMap.parse` inflates the layer and
  unpacks little-endian `uint32` gids; CSV does not load. Tiled writes this when
  the layer format is "Base64 (zlib compressed)".
- **The map's shape is part of what example 10 teaches.** A* over an open field
  produces a straight line and demonstrates nothing. `town.tmx` is 60x40 tiles
  (960x640 px, larger than the window on both axes) with a fence right across
  the middle and exactly one gap.

Two mistakes were made getting that gap right, both caught by walking the grid
with a BFS rather than by looking at it:

- **A gap between the start and the goal is not an obstacle.** At x=29..31 the
  shortest route cost exactly the straight-line distance — 55 steps against a
  55-step Manhattan distance. Moved far west, the same trip is 84 against 22,
  and the walker has to head *away* from its goal to get through.
- **A fence has to span the whole interior.** Stopping it one tile short of the
  border left a second gap at x=58, and the route quietly used that instead.

The `.tsx` and `.tmx` are ours; only the `.png` is sourced. One map serves all
three examples that use it.

**F is the only asset that costs anything.** At 93 KB the music is three
quarters of this directory, and that is *after* a 76% reduction:
`tools/shrink_ogg.c` downmixes to mono and re-encodes, because the CC0 loops
worth having are encoded for listening (stereo, 44.1 kHz, ~128 kbps) rather than
for a library gem. Three constraints, all easy to get wrong:

- **The engine plays Ogg Vorbis and WAV only.** MP3 and FLAC are compiled out of
  miniaudio, so an MP3 that plays everywhere else fails at load here. That ruled
  out one otherwise-ideal CC0 loop distributed only as WAV and MP3.
- **Never trim a loop to save bytes.** It is seamless at exactly its own length.
  Channels and quality are free; length is not.
- **A seam figure alone does not tell you a track loops.** The first music file
  shipped here measured 2.6% on the seam and looped audibly badly: it ends with
  0.79s of silence, so the wrap has no click but a *gap* — and silence joining
  silence is a perfectly smooth seam, which is exactly why the number could not
  see it. The tool reports head and tail silence too now, and the track was
  replaced. Both figures, or neither means anything.

**C was not optional after all.** It was deferred as cosmetic — "a menu works
with rects" — and that was simply wrong: `UI::MenuItem` draws its background
with `renderer.nine_slice`, nine-slice ids resolve by registration only, and
`Menu` builds its own items, so there is no way to have a menu without an atlas.
It shipped with example 3. See that example for the two constraints the widget
puts on the art.

**D was not needed.** `examples/radial_menu` shipped with text labels on asset
**C**'s buttons — its items are `MenuItem`s, so it has exactly the chrome a list
menu has, and the labelled wheel reads well.

### Consequence for the order

**Nothing outstanding.** Asset G — the input prompt glyphs — was cut from
Kenney's *Input Prompts* while building `examples/input_glyphs`. A, B, C, F and G
are all discharged, and everything remaining in the plan is code.

## Implementation order

The order is chosen so that each phase either needs no new engine code or needs
exactly one new thing, and so that nothing is built before the thing it consumes.

**These numbers are execution positions, not the `### N` numbers above.** The
catalogue in "The examples" is in the order the entries were written and its
numbers are cited all over this file — asset rows, the engine-work table, the
open questions — so it does not get renumbered when the order changes. Below,
examples are named rather than numbered wherever one is referred to.

**Phase 0 — done.**

1. ~~Source assets **A** and **B** (CC0) and commit them under
   `examples/assets/` with the README naming source and licence.~~
2. ~~Add `examples/**/*` to the gemspec's `packaged` glob, and the
   `packaging_spec.rb` examples that hold it up.~~

Both landed, along with the harness change. **Nothing outside the repo is
needed from here on** — everything below is code.

**Phase A — establish the shape, no new engine code.**

3. ~~`examples/walk`~~ — **done**; needed no new engine code, as hoped.
4. ~~`examples/scroll_map`~~ — **done**; no new engine code either.
5. ~~`examples/game_menu`~~ — **done**; no new engine code, but it needed asset
   **C**, which the plan had wrongly called optional.

Three examples that add nothing to the engine come first on purpose. They set the
house style for what an example looks like, and they are the check that the
engine can already express the basics — if one of them turns out to need new
code, that is a finding about the engine and worth knowing before nine more are
planned on top of it.

**Phase B — audio, and no new engine code.**

6. ~~`examples/sound`~~ — **done**.
7. ~~`examples/music`~~ — **done**.

Moved up from the back of the queue to answer a question rather than to tick a
box: audio is the one asset kind that **cannot** be resolved by path, and these
two are what a change to that would have to keep working. They are also the last
easy examples — everything after this adds engine code.

The one thing they turned up was in the harness rather than the engine:
`AudioProbe` did not record `stop_music`, so a game stopping its music left no
trace in any report. Fixed while writing example 7.

**Phase C — small self-contained additions, in dependency order. No assets.**

8. ~~`examples/fullscreen`~~ — **done**; the only C work in the batch.
9. ~~`examples/save_load`~~ — **done**.
9a. ~~`examples/save_load_ids`~~ — **done**; no new engine code, `Identity` was
    written with it in mind.
10. ~~`examples/menu_navigation`~~ — **done**; consumes 8 and 9, so its settings
    are real and persist.

**Phase D — engine that already exists and nothing shows. Easiest first.**

11. ~~`examples/sprite`~~ — **done**.
12. ~~`examples/velocity`~~ — **done**.
13. ~~`examples/signals`~~ — **done**.
14. ~~`examples/timer`~~ — **done**.
15. ~~`examples/pooling`~~ — **done**; driven by 14, as planned.
16. `examples/collision` (`CollisionWorld` + `BoxCollider` + `CircleCollider`,
    moved by 12; no assets)
17. ~~`examples/collision_tiles`~~ — **done**; no new engine code and no map
    change: `town.tmx`'s fence was already the wall worth sliding along.
16. ~~`examples/collision`~~ — **done**; no new engine code, but it turned up an
    undocumented `on_hit` contract (see its landed note).
17. `examples/collision_tiles` (`Components::TileCharacterBody`; reuses **B**)
18. `examples/split_screen` (`players: 2`; reuses **A**)
19. ~~`examples/input_glyphs`~~ — **done**; `Controls.gamepad?` and
    `pad_button?`, `InputMap#button_for`, and asset **G** cut from Kenney's
    *Input Prompts*.
18. ~~`examples/split_screen`~~ — **done**; no new engine code, and it is where
    `Engine::Culling` finally has an example.
19. `examples/input_glyphs` (`Controls.gamepad?`, an `InputMap` query, and asset
    **G** — the only new engine work in this phase)

**This phase is a coverage phase rather than a feature phase**, and that is why
it comes before the two that add components. Everything up to `split_screen`
already exists, is already specced, and is already used by a test project — but a
reader browsing `examples/` never meets any of it, and a test project is a whole
game rather than a thing that makes one point. Only `input_glyphs` adds engine
surface.

Ordering inside it is by how much a reader has to absorb, not by how much code it
takes to write. The first four are one component each. `pooling` leans on
`timer`, because a pool wants something to drive it; `collision` leans on
`velocity`, because two shapes have to move into each other; and
`collision_tiles` comes after `collision` so the general mechanism is read before
the specialised one — which also lands it next to Phase E, whose jump builds on
it directly.

**Phase E — a new gameplay component.**

20. ~~`examples/jump_topdown`~~ — **done**; `Components::Hop`, and the height
    lives on the node as `Node2D#elevation`.

It follows `examples/collision_tiles`, so tile collision is something the reader
has already met and the jump example does not have to introduce it.

**Phase F — the two largest, both independent of everything above.**

21. ~~`examples/radial_menu`~~ — **done**; `UI::RadialMenu`, its own two axes, and
    asset **C** again, because its items are `MenuItem`s.
22. `examples/pathfinding` (reuses **A** and **B**; `town.tmx` already has the
    obstacle worth routing around — see "Assets")

Both are self-contained and could move earlier if wanted. Pathfinding is last
only because it is the largest single algorithm; it has no dependency on
anything in phases C, D or E.

**Phase G — localization.**

23. `examples/localization` (`Engine::I18n` with `CachedLabel` and `UI::Menu`; no
    assets)

Last by decision rather than by dependency: it was added once the component
sweep (a plan since folded back and deleted; `git log` has it) found `I18n` had no caller
anywhere, and the answer was to keep it and give it an example. Nothing above
depends on it and it depends on nothing unbuilt.

## Audio resolves by path now — and what that cost

Phase B existed partly to set this question up, and the answer was yes.
`Audio#play_sound` and `#play_music` take the same two id spaces the renderer's
draw-by-id does: a String is a path resolved through the asset manager and
remembered, a Symbol is a name only registration can bind, and registration
overrides a path. `examples/sound` and `examples/music` now name their files and
register nothing; `test_projects/asteroids` still uses Symbols and still works,
which is the check that both spaces survive.

Caching turned out to be a **correctness** requirement rather than an
optimisation: `play_music` asks the song whether it is already playing, so
resolving one path to two Songs would defeat that guard and restart the track on
every request.

**The interesting part was the lifetime bug it exposed.** Giving `Audio` the
asset manager added one edge to a graph that already had a permanent root:

```
AudioBus (a module — process-global, never unsubscribed)
  -> the connected block -> AudioDirector -> the Audio device
  -> the asset manager        <- the new edge
  -> the App -> the GL window
```

Every audio-using project broke under `tools/drive_test_project.rb`, which tears
down its Xvfb after a `GC.start` meant to close the window first. Measured:
subscribing a director and playing nothing left one live `App` after three full
collections. It was not the resolution that was wrong — any path resolution
downstream of the bus reaches the App, because the asset manager needs the app
to build images — it was that a module-level hub held a listener for ever.

So `RGame::Game` owns the director now: it subscribes one in `start` and
releases it in `ensure`. That deletes a line from every game's `main.rb` which
was a footgun in its own right — forgetting to subscribe was **silent**, the
tree running and the events firing and nothing playing.

Worth keeping in mind for the rest of this plan: **a global that never lets go
is invisible until something else reaches through it.** The bus had been holding
the audio device for ever the whole time, and nobody noticed until the device
started holding the window.

## Open questions, collected

*(The asset-sourcing question is settled: Kenney *Tiny Town* for the tileset,
sodri's character sheet repacked. See "Assets". So is 6: one `OptionItem` and no
`SliderItem` — see example 8.)*

- ~~**7** — should `TileWorld` know about `airborne?` (hop over a gap), or does that
  stay the game's business?~~ **Resolved:** the game's business. `TileWorld`
  does not consult it and `Hop` knows nothing about tiles; see the landed note
  on `examples/jump_topdown`.
- ~~**7** — does `jump` join `InputMap::DEFAULT_ACTIONS`, or does the example merge it
  in like `tiled_world` does with `:cutscene`?~~ **Resolved:** merged in by the
  example, and `DEFAULT_ACTIONS` is unchanged.
- ~~**9** — does the radial read `move_x`/`move_y`, or declare its own axes? And can
  the icon ring avoid needing `Renderer#pie` entirely?~~ **Resolved:** its own,
  `ui_radial_x` / `ui_radial_y` in the universal set, on the same stick by
  default; and no `pie` — see the landed note on `examples/radial_menu`.
- **13** — one node drawing a whole image and one drawing a registered
  `subimage`, or a single still image? Leaning toward both, because it shows the
  two id spaces again and costs no new asset.
- ~~**21** — does takeover switch *back*?~~ **Yes, through `ui_confirm` and
  nothing else** — `PAD_A` takes the seat, `KEY_SPACE` or `KEY_RETURN` hands it
  back, `KEY_W` does not. Settled as the example's stated constraint rather than
  the engine's bug: one action rather than any input is what stops a resting stick
  seating a player, and it is the same rule in both directions. A game that wants
  any key sets `on_unassigned_input = :ignore` and calls `seat` itself.
- ~~**21** — does the glyph lookup stay in the example?~~ **It stayed**, as the
  leaning said. One frozen hash from button id to sheet column; nothing has
  written it twice.
- **Discoverability** — a shipped example lands inside the installed gem's
  directory, which nobody browses. Should the `rgame` command grow an
  `rgame examples` that lists them (and maybe copies one into the working
  directory, the way `rgame new` scaffolds)? Leaning yes, but *after* the
  examples exist — it is a CLI feature, not part of this plan, and
  `docs/api/cli.md` is where it would be argued.
- **General** — do examples get an index page (`examples/README.md`) as well as
  links from `docs/api/`? Leaning yes — and Phase D turns this from a preference
  into a requirement. Twenty-odd example folders with names like `velocity` and
  `collision_tiles` need a table saying which one answers which question, because
  the directory listing alone stops being one.

## What still has no example when all of this is done

Taken from the whole of `lib/rgame/engine/` against every example above,
built and planned. **Reviewed once Phase F lands** — the question for each is
whether it wants an example or whether `docs/api/` is enough, and that is easier
to answer with the rest of the list in front of you than now.

Everything named here has specs and a `docs/api/` entry already. Nothing is
undocumented; what these lack is a running file a reader can open.

### Public, used by a test project, never by an example

One component, from `test_projects/asteroids`:

| | What it does | Why no example took it |
|---|---|---|
| `Components::ThrustController` | turns an action into acceleration along the node's facing | every example moves things in screen axes; nothing in the list flies |

`ThrustController` is not obscure and would make a small example — together with
`Targeting`, below, most of a twin-stick shooter, which is an argument for one
example rather than two.

### Public, used nowhere at all

Two — not used by an example, not by a test project, and not by `lib/` either.

| | What it does |
|---|---|
| `Engine::I18n` | locale tables, `t(key)` with `%{var}` interpolation, a fallback locale, and a generation counter so cached UI text knows when to re-resolve |
| `Components::Targeting` | holds a *node* as a target and answers whether it is still valid |

`I18n` is the largest genuinely unexercised subsystem in the engine. **Now
scheduled as example 23**, so its row closes when that lands. Its own header still
compares itself to `EventDispatcher`, which went with Gosu, so it has not been
read in a while either. A localized menu is a plausible example and would want the
generation counter and `CachedLabel` together.

`Targeting` was listed under "used by a test project" until the component sweep
found asteroids never builds one. `examples/save_load_ids` names it in a comment —
as the component with the same problem it solves by hand — and never builds one
either.

**`CachedLabel` was the other row here and is resolved.** The question was
whether the engine's answer to `Game/NoInterpolationInHotPath` or the examples'
hand-rolled ones were right, and it turned out to be both, along a line worth
writing down. A **constant string chosen by state** — `STATE` in
`examples/fullscreen`, `STATUS` in `examples/save_load` — selects a string rather
than building one, so there is nothing to cache and a frozen hash is clearer.
A label built from a **changing** value is what `CachedLabel` is for, and exactly
one example had one: `examples/sound` drew a row of rectangles to count plays
*because* a formatted count was refused, with a comment longer than the code
explaining the dodge. It now draws the count through a `CachedLabel`, four
constants and a loop lighter. The rule is in CLAUDE.md under "A label built from
a changing value", so the next example reaches for it instead of inventing a
third way round.

### Orphans — the question is deletion, not documentation

Live, specced code with no caller anywhere in `lib/`, `examples/` or
`test_projects/`:

- **`Engine::Matrix`** — a flat-backed 2-D grid. `TileMap` packs into the C
  `Util::Tensor` instead.
- **`Engine::Resettable`** — value classes for pooling. `Engine::Pool` recycles
  nodes, which reset themselves.

An example is the wrong fix for either. Something should use them or they should
go, and the honest first step is finding out which.

**`Engine::Actor` was the third of these and is deleted.** It was a character
composing a collision box, an animator, a sprite id and a controller — the
pre-component shape of what `Node2D` plus components does now — and its only
caller was its own spec. `Engine::PlayerController` went with it: a bare class
whose whole job was answering `intent(dt, input)` for an `Actor`, unrelated to
the live `Components::PlayerController`. `CollisionSystem#move` stays, because
`Components::TileCharacterBody` calls it.

### Internals, correctly absent

Reached transitively by things the examples do use, and an example that named one
would be teaching plumbing rather than a concept: `Body`, `CollisionBox`,
`CollisionSystem`, `Culling`, `SpatialHash`, `TileCollision`, `Layout`, `View`,
`AnimationSet`, `Animator`, `Tileset`, `DebugOverlay`, `AudioDirector`,
`ActionMapper` and `Actions`.

These belong in `docs/api/internals.md` and nowhere else. Listed so that a later
pass over this section does not have to re-derive why they are missing.

## When this lands

Per CLAUDE.md's rule for `docs/plans`: fold what is still true into
`docs/api/` (each new component into `components.md`, `ui.md`, `toolbox.md`;
fullscreen into `app.md`; `SaveFile` into `values.md`; the device-kind predicate
into `input.md`), add the examples index, update `docs/project_structure.md` with
the `examples/` and `examples/assets/` entries — and delete this file. Git history
keeps it.

**"What still has no example" is the one section to resolve before deleting**,
rather than fold in. Its rows are decisions the plan raised and did not take: an
example, a documentation-only answer, or — for the three orphans — a caller or a
deletion. Whatever is decided goes into `docs/api/` or into the code; what must
not happen is the list quietly disappearing with the plan.

Three things are **not** part of that fold-in, because they are permanent:
`examples/assets/README.md` (the file that keeps the licensing answerable a year
from now), the gemspec's `examples/**/*` glob entry, and the packaging examples
that hold it up.
