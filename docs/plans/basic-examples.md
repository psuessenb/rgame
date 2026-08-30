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
   concept *is* the split (the sidescroller's body component is engine code, not
   example code).
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

### 3. `examples/game_menu` — opening an in-game menu

**Shows** a menu that opens over a running world, pauses only the player who
opened it, and closes again.

**Existing:** `Engine::PlayerLayer`, `Engine::UI::Menu` / `UI::MenuItem`,
`Node2D#paused`, `Node2D#draw_children` (the "close by not calling `super`"
seam), `renderer.nine_slice`, `ui_cancel` / `ui_confirm` from the default map.

**New:** none. `test_projects/tiled_world/inventory.rb` already does exactly
this; the example is that idea stripped to the concept, with the world reduced
to something that visibly keeps moving while the menu is up.

**Assets:** none. A panel is `renderer.rect` and the shipped font. Asset **C**
(a nine-slice UI sheet) would make it prettier and is deliberately deferred —
see "Assets".

### 4. `examples/fullscreen` — toggling fullscreen

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
for. Check the `windows-portability` skill before writing the binding.

**Assets:** none. This example runs on a fresh clone.

### 5. `examples/save_load` — saving and restoring game state

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
writes an explicit Hash and reads it back. Reflective save of a live tree is a
much larger design question and nothing here needs it yet.

**Assets:** none.

### 6. `examples/menu_navigation` — a main menu and a settings menu

**Shows** more than one screen: title → settings → back, and settings that
change something real.

**Existing:** `Scene::SceneStack` (`push` / `pop` / `replace`), `UI::Menu`,
`ui_cancel` for back.

**New:**

- `Engine::UI::OptionItem` — a menu row whose value cycles with
  `ui_left` / `ui_right` and which draws `Label   < value >`. This is the first
  genuinely new UI control, and it is what a settings menu *is*.
- Possibly `Engine::UI::SliderItem` for volume. **Decide when writing:** an
  option item over `[0%, 25%, 50%, 75%, 100%]` may be enough, and one control is
  cheaper to justify than two.
- Both need a `docs/api/ui.md` section, and "What this is not" in that page needs
  its list trimmed to what is still missing.

**Consumes 4 and 5:** the settings this menu offers should be real —
fullscreen on/off (example 4) and master volume (`Core::Audio#volume=` already
exists, reachable from a node as `root.context.audio`) — and should persist
through example 5's `SaveFile`. That is why it comes after both.

**Assets:** none required; text and rects.

### 7. `examples/jump_topdown` — a hop in a top-down view

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

### 8. `examples/jump_sidescroller` — jumping in a side view

**Shows** gravity, ground contact, and a jump that is a real change of position.

**Existing:** `Components::TileWorld` for solid-tile queries, `Engine::Camera`,
`Components::Velocity` (integrates a velocity, but has no gravity and no
collision response).

**New — the largest gameplay addition in this list:**

- `Components::PlatformerBody`. `TileCharacterBody` cannot be reused: it is a
  top-down *feet box* with symmetric sliding, and a side view needs a full AABB
  resolved **one axis at a time** (horizontal first, then vertical) so that
  walking into a wall does not cancel the fall and landing does not cancel the
  walk. That axis split is the whole of why this is a separate component.
- Gravity, terminal velocity, a jump impulse, and `on_ground?` derived from the
  vertical resolution rather than tracked separately.
- **Coyote time and jump buffering** — a few frames of grace after leaving a
  ledge, and a jump pressed just before landing still firing. Both are what
  separates a jump that feels right from one that does not, and both are pure
  `dt` accumulation, so they belong here and are fully spec-able headless.
- A `jump` action added to `InputMap::DEFAULT_ACTIONS`? **Open question** — the
  default map is deliberately small. Leaning toward: the example declares it via
  `InputMap.default.merge(...)`, the way `tiled_world` declares `:cutscene`.

**Assets: none — decided, not deferred.** A side view needs a side-view tileset
and a side-view character, and neither exists or can be lifted from `media/`.
Sourcing both is more work than the component itself and teaches nothing extra:
a platformer body is about gravity, ground contact and coyote time, and a
coloured rect falling onto another coloured rect shows every one of them. Build
the level from `renderer.rect` and say so in the example's header, so the next
reader knows it is a choice rather than an omission.

### 9. `examples/radial_menu` — a controller-driven radial menu

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

### 10. `examples/pathfinding` — a character walking a computed route

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
- Path smoothing (drop waypoints a straight line already covers) — worth it,
  because raw A* output on a grid zig-zags and looks wrong when walked.

**Performance note:** A* runs on demand, not per frame, so plain Ruby is the
right call and the `Game/NoNeedlessAllocation` cop's concerns do not apply.
If profiling on a large map ever says otherwise, `ext/rgame_util/` is where it
would go — pure logic, no SDL — but **do not start there**.

**Assets:** **A** and **B**. Nothing new — though **B**'s map wants a shape
with a wall worth going around, or the search has nothing to show. Note that
under "Assets".

---

## New engine work, gathered

Sorted by where it lands, because that decides who may use it.

| What | Layer | For | Size |
|---|---|---|---|
| `rgame_app_set_fullscreen` / `_fullscreen` + Ruby binding | C + `Core::App` | 4 | S |
| `Util::SaveFile` + save-dir helper | `Util` (pure Ruby) | 5, 6 | S |
| `UI::OptionItem` (+ maybe `SliderItem`) | `Engine::UI` | 6 | S |
| `Components::Hop` | `Engine` | 7 | S |
| `Components::PlatformerBody` | `Engine` | 8 | **L** |
| `UI::RadialMenu` | `Engine::UI` | 9 | M |
| `Engine::NavGrid` + `Engine::AStar` | `Engine` | 10 | **L** |
| `Components::CameraPan` | `Engine` | 2 | S, *maybe not needed* |
| `Renderer#pie` + contract + fake | `Core` + contracts | 9 | M, *avoid if possible* |

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

Two asset sets are unavoidable, and between them they cover four of the ten
examples. Three more are deferred, and one is refused outright.

| | Asset | Files | Used by | Status |
|---|---|---|---|---|
| **A** | Character sprite sheet | `hero.png` + `hero.json` | 1 walk, 7 jump_topdown, 10 pathfinding | **done** |
| **B** | Top-down tileset + a map | `tileset.png`, `tileset.tsx`, `town.tmx` | 2 scroll_map, 7 jump_topdown, 10 pathfinding | **done** |
| **C** | UI nine-slice sheet | `ui.png` + `ui_atlas.json` | 3 game_menu, 6 menu_navigation | deferred |
| **D** | Radial icon sheet | `icons.png` + `icons.json` | 9 radial_menu | deferred |
| **E** | Side-view tileset + character | — | 8 jump_sidescroller | **refused** — rects instead |

**A and B are in `examples/assets/`**, about 10 KB in total, with full
provenance in `examples/assets/README.md`. A is sodri's CC0 *Character 4
directional walking*, background keyed out and repacked into a uniform 16x22
grid; B is Kenney's CC0 *Tiny Town* copied unchanged, with a `.tsx` and a
`.tmx` authored here. What follows is what they had to satisfy, kept because it
is what a replacement would have to satisfy too.

Nothing else in the list needs a file: 4 fullscreen, 5 save_load and
6 menu_navigation draw with primitives and the shipped font.

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

**C and D are deferred on purpose.** Both are cosmetic: a menu works with rects,
a radial menu works with labels, and neither concept is any clearer with art.
Deferring them keeps the sourcing work — the slowest step here — down to one
character and one tileset before anything can be written. Pick them up only if
the plain versions read badly.

**E is refused.** See example 8: the physics is the point, and rects show it.

### Consequence for the order

None any more — this was the only external dependency in the plan and it is
discharged. Everything from here is code.

## Implementation order

The order is chosen so that each phase either needs no new engine code or needs
exactly one new thing, and so that nothing is built before the thing it consumes.

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
5. `examples/game_menu` (no assets)

Three examples that add nothing to the engine come first on purpose. They set the
house style for what an example looks like, and they are the check that the
engine can already express the basics — if one of them turns out to need new
code, that is a finding about the engine and worth knowing before nine more are
planned on top of it.

**Phase B — small self-contained additions, in dependency order. No assets.**

6. `examples/fullscreen` (C + Core; the only C work in the batch)
7. `examples/save_load` (`Util::SaveFile`)
8. `examples/menu_navigation` (`UI::OptionItem`; consumes 6 and 7 so its settings
   are real and persist)

This whole phase is asset-free.

**Phase C — new gameplay components, small before large.**

9. `examples/jump_topdown` (`Components::Hop` — small, and it is the one that
   makes the "a jump is a draw offset" point that the sidescroller then
   contrasts with; reuses **A** and **B**)
10. `examples/jump_sidescroller` (`Components::PlatformerBody` — the big one; do
    it after the small jump so the contrast between the two is deliberate. No
    assets, by decision)

**Phase D — the two largest, both independent of everything above.**

11. `examples/radial_menu` (no assets)
12. `examples/pathfinding` (reuses **A** and **B**; `town.tmx` already has the
    obstacle worth routing around — see "Assets")

Both are self-contained and could move earlier if wanted. Pathfinding is last
only because it is the largest single algorithm; it has no dependency on
anything in phases B or C.

## Open questions, collected

*(The asset-sourcing question is settled: Kenney *Tiny Town* for the tileset,
sodri's character sheet repacked. See "Assets".)*

- **6** — one `OptionItem` cycling discrete volume steps, or an `OptionItem` plus a
  `SliderItem`?
- **7** — should `TileWorld` know about `airborne?` (hop over a gap), or does that
  stay the game's business?
- **8** — does `jump` join `InputMap::DEFAULT_ACTIONS`, or does the example merge it
  in like `tiled_world` does with `:cutscene`?
- **9** — does the radial read `move_x`/`move_y`, or declare its own axes? And can
  the icon ring avoid needing `Renderer#pie` entirely?
- **Discoverability** — a shipped example lands inside the installed gem's
  directory, which nobody browses. Should the `rgame` command grow an
  `rgame examples` that lists them (and maybe copies one into the working
  directory, the way `rgame new` scaffolds)? Leaning yes, but *after* the
  examples exist — it is a CLI feature, not part of this plan, and
  `docs/api/cli.md` is where it would be argued.
- **General** — do examples get an index page (`examples/README.md`) as well as
  links from `docs/api/`? Leaning yes: a directory of ten example folders needs a
  table saying which one answers which question.

## When this lands

Per CLAUDE.md's rule for `docs/plans`: fold what is still true into
`docs/api/` (each new component into `components.md`, `ui.md`, `toolbox.md`;
fullscreen into `app.md`; `SaveFile` into `values.md`), add the examples index,
update `docs/project_structure.md` with the `examples/` and `examples/assets/`
entries — and delete this file. Git history keeps it.

Three things are **not** part of that fold-in, because they are permanent:
`examples/assets/README.md` (the file that keeps the licensing answerable a year
from now), the gemspec's `examples/**/*` glob entry, and the packaging examples
that hold it up.
