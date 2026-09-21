# Possible todos

Work that has a reason to exist but no reason to happen yet. Nothing here is
scheduled, and nothing here is a promise — this file exists so that ideas with
real thought behind them are not lost to a deleted plan or a finished
conversation.

Each entry says what the thing is, why it is not being done now, and what would
make it worth doing. **An entry with no trigger is a wish, not a todo**; if the
answer to "what would make this worth starting" is "nothing in particular", the
entry should be deleted rather than kept.

---

## A low-resolution render target, and the GL loader it needs

**What.** Render a frame into an offscreen buffer at the game's own resolution,
then scale that buffer onto the window — Godot's `viewport` stretch mode, as
against the `canvas_items` one.

**What exists instead.** `RGame::Game.new(scale_mode:)` and
`RGame::Engine::Presentation` scale the *coordinates*: everything still
rasterises at the window's real resolution, and the transform maps a logical
size onto it. That covers most of what a game wants, `:integer` included, and it
needed no C at all.

The difference shows up in one place. Coordinate scaling rasterises text and
shapes at full resolution, which is what you want for anything that is not pixel
art — but a *sprite* drawn at 2x is still sampled from its original texels, so
the crispness depends on the filter and the factor rather than on having been
rasterised at 320x240 in the first place. A render target gives the genuine
low-resolution look, and hands the frame over as a texture, which is also what
any post-processing effect would need.

**Why not now.** It is the project's first call above OpenGL 1.1, and that is a
threshold rather than a line of code. Every `gl*` call in `ext/rgame_core/` today
is GL 1.1 — checked, all 24 of them — which is exactly what "no GL loader" has
bought so far. Windows' `opengl32.dll` exports only GL 1.1, so `glGenFramebuffers`
and friends must be fetched through `SDL_GL_GetProcAddress`. A naive
implementation compiles, links and runs perfectly on Linux and fails on Windows,
which is the failure class the `write-c-code` skill's portability section
exists for.

**What it would take.**

- A keyhole loader: six entry points (`glGenFramebuffers`, `glBindFramebuffer`,
  `glFramebufferTexture2D`, `glCheckFramebufferStatus`, `glDeleteFramebuffers`,
  and `glGenerateMipmap` if wanted) resolved once into a struct. Roughly thirty
  lines, and not GLAD.
- An availability check with a clear failure. We never request a context
  version, so we take SDL's default; a missing FBO must say so rather than draw
  a blank screen.
- Two entries on `backend.h`'s table — bind target, unbind target — which
  `test/support/recording_backend.c` implements too, so "bound, drew, unbound,
  blitted once" stays assertable with no display.
- The Y flip. An FBO-rendered texture is upside down against our
  `glOrtho(0, w, h, 0, …)` top-left origin, so the final blit needs flipped
  texture coordinates. This one is famous for costing an afternoon.

Two things are already in place and do not need designing:
`rgame_texture_sheet_create` takes a raw GL texture name and does not care where
it came from, so an FBO's colour attachment becomes an ordinary sheet the whole
existing sprite path can draw; and the policy half — which scale, which
offsets — is `Presentation`, which is pure and already specced.

**Trigger.** A game that wants a genuine low-resolution look and finds
coordinate scaling not good enough, or the first want for a post-processing
effect.

### Two smaller things in the same area

- **`:overscan`.** `Presentation` has four modes; SDL has a fifth, which fills
  the window on the *smaller* axis and lets the larger overflow. It is two lines
  — `max` where `fit_uniform` takes `min` — and was left out because no example
  asks for it. Adding an unused mode is a claim nothing checks.
- **A minimum window size.** `:integer` never scales below 1x, so a window
  smaller than the logical size crops instead of shrinking. `SDL_SetWindowMinimumSize`
  would design the case out entirely rather than documenting it. It needs C, and
  the case only arises if a player drags a window below the game's design size.

---

## Move the hot paths into C

Only after profiling, and only where there is a measured reason. Carried over
from the roadmap that planned the C engine; the entries have been checked
against what the code does now.

- **`NineSlice`'s tiling loops.** Still Ruby: `draw` walks each band with nested
  `while` loops, five tiled regions per call per frame. Every menu item on screen
  is one of these.
- **`TileMapRenderer`'s per-tile draw loop.** Half of this is already gone, and
  it is the outcome the roadmap hoped for: static tiles are baked into a
  `Recording` on first draw and replayed as one call per texture. What still
  loops per tile is the *animated* ones, which are collected once at construction
  precisely because finding them again each frame would cost more than drawing
  them. A map with a handful of animated tiles is already cheap; one with
  thousands is the case that would justify moving this.
- **`Renderer`'s per-draw id lookups.** Now one hash fetch on a registry that
  caches the resolved asset, so this is a much smaller item than when it was
  written. Left here only because it is the third thing to look at if a profile
  ever points this way.

**Why not now.** Each is a straightforward move once the pure geometry is
separable, and doing any of them early trades readability for a speedup nobody
has measured.

**Trigger.** A profile. Not a suspicion.

---

## Edge margins derived from the node's size

**What.** `ScreenWrap` and `DespawnOffscreen` derive their `margin` from how big
the node is, rather than taking it by hand.

**What exists instead.** Every caller sets `margin` to a radius or more itself.
Asteroids' rock uses its largest tier's radius for all four tiers.

**Why not now.** It needs a footprint convention first, and there is none:
`node.width`/`height` do not say where the box sits. `Sprite` culls a box centred
on the origin and `AnimatedSprite` one cornered at it, each deciding for itself,
and the wrapped and despawned nodes draw centred.

**Trigger.** A caller whose hand-set margin is visibly wrong, or a second place
that needs a node's footprint and has to pick a convention.

---

## Text layout past a label

**What.** Three things `Util::Typeface`, `Engine::Paragraph` and `UI::Label`
were built without, each with its own trigger:

- **Ascent and descent on `Typeface`.** The C face has both
  (`rgame_typeface_ascent`), and Ruby sees only `height`.
- **Breaking between characters.** `rgame_typeface_fit` breaks at spaces and
  newlines only, so a script written without spaces never breaks.
- **A panel behind a label, and vertical alignment.** `UI::Label` draws text
  from its top-left corner and nothing behind it. The design had a `style:`
  like `UI::TextButton`'s, but a style draws per button state, which a label
  does not have.

**What exists instead.** A caller steps lines by `height` and aligns them
horizontally. `examples/intro` places its block of text with its own arithmetic
and draws its own backdrop.

**Why not now.** Nothing asks for any of them. The shipped font covers no
script written without spaces, and nothing aligns two faces on one line.

**Trigger.** Ascent and descent: a caller aligning two faces on one line.
Breaking between characters: a font shipped or loaded that covers such a script.
The panel and vertical alignment: the dialogue box, whose design they belong to.

---

## A twin-stick example for `ThrustController` and `Targeting`

**What.** One example, `examples/twin_stick` or similar: a ship that turns and
thrusts with `Components::ThrustController`, and a turret that aims at the
nearest enemy through `Components::Targeting`.

**What exists instead.** Every other public engine class has an example. These
two have specs and sections in `docs/api/components.md`, but no running file:
`ThrustController` is used only by `test_projects/asteroids`, which does not
ship, and nothing builds a `Targeting` at all. `examples/save_load_ids` explains
in its header why it does *not* use `Targeting`. Every example moves things in
screen axes, so nothing flies, and the two together are most of a twin-stick
shooter, which is why this is one example rather than two.

**Why not now.** The single-concept examples plan that found the gap is done,
and neither class has a caller asking for one.

**Trigger.** The next change to either class, which then has no example to check
it against — or a reader asking how to aim at something. If `Targeting` still
has no caller when this is picked up, deleting it is the other answer.

---

## `rgame examples`: finding the examples in an installed gem

**What.** An `rgame examples` command that lists the examples shipped in the gem
with their one-line descriptions, and perhaps copies one into the working
directory the way `rgame new` scaffolds a project.

**What exists instead.** `examples/` ships inside the installed gem, and the
README and `docs/api/examples.md` describe each one. But the gem's directory is
somewhere nobody browses, and `rgame` knows only `new`, `version` and `help`.

**Why not now.** It was deliberately deferred until the examples existed, and
nobody has yet failed to find them. It is a CLI feature, and `docs/api/cli.md`
is where its shape would be argued.

**Trigger.** Someone who installed the gem asking where the examples are, or the
first release announced to people who will not clone the repository.

---

## A snapshot of the loaded translation tables

**What.** `I18n.snapshot` and `I18n.restore`, so a spec suite puts its tables
back before each example without parsing them again.

**What exists instead.** The `spec_helper` that `rgame new` generates calls
`I18n.reset` and loads every table before every example, because `I18n` is
global and a spec that switches the locale or loads a table would otherwise leak
into the next one. Measured when it was written (Ruby 4.0.5, no YJIT): 0.03 ms
for the generated one-key table, 8.1 ms for 1,000 keys — 5.0 ms of YAML parsing
and 2.9 ms of compiling. Compiled tables are frozen, so a restore could hand the
same objects back for a constant cost.

**Why not now.** No game's suite is slow because of it. The generated project
has one key.

**Trigger.** A game whose spec run is measurably slowed by reloading its tables.

---

## A packed asset format

**What.** Read a game's assets out of one or a few pack files instead of loose
files, for a release on a store such as Steam.

**What exists instead.** Loose files under the media root. Steam does not require
packs: SteamPipe splits every file into ~1 MB chunks and uploads only the chunks
that differ, so loose files patch well. Its advice for packs — keep changes
localized, keep asset order stable, compress per asset, no table of contents of
absolute offsets — constrains the tool that *writes* a pack. The reader only
needs every read to go through one seam
([Steamworks: Uploading to Steam](https://partner.steamgames.com/doc/sdk/uploading)).

Translation tables already do: `AssetManager#glob` lists them and the `:locale`
loader reads them. What does not:

- `image.c` and `font_atlas.c` `fopen` a path. A pack needs
  `stbi_load_from_memory` and a font read from a buffer.
- `audio.c` calls `ma_decoder_init_file` and `ma_sound_init_from_file`. A pack
  needs miniaudio's VFS (a resource manager with a custom `ma_vfs`), which
  `vorbis_decoder.c`'s `onInit` entry point already reads through.
- `AssetManager#resolve` is `File.expand_path`. That is the Ruby seam, and it is
  already the only one.

**Why not now.** Nothing ships through a store yet, and loose files are what
SteamPipe patches best.

**Trigger.** A release whose file count or install layout makes loose files a
problem, or a store that requires a pack.

---

## Pathfinding beyond one hero walking a fixed map

The pathfinding plan built `Util::SolidGrid`, `Util::RouteSearch`, `Util::TileSweep`,
`Engine::NavGrid` and `Components::Navigator` for one hero on an unchanging map, and
checked the design against five additions it did not build. What each would start
from:

- **Maps that change at runtime.** `SolidGrid#set_solid`, `revision`, and region
  labels that relabel lazily all exist and are tested, and `TileWorld`'s
  `blockers`, `nav_grid` and `solid?` share one store. Missing: an engine-level API
  on `TileWorld`, deliberately not a bare reader of the store — a solidity change
  without the drawn tile is an invisible wall — and a decision about what a walking
  `Navigator` does when `revision` moves under its route (today it stands at the
  new wall, `on_blocked` by `:tiles`, with nothing saying why). **Trigger:** a door,
  a destructible wall, or a bridge a game wants.
- **Replanning around moving actors.** The search state lives in `RouteSearch`,
  separate from the grid, so a per-query overlay of blocked cells is a parameter of
  `find`, not a second grid. **Trigger:** a game whose navigator must go around
  another character rather than wait (today it waits, by decision).
- **Crowds.** ~0.19 µs per expanded cell in C on an open map (measured on
  `beach_large.tmx`), untuned. A struct-of-entries heap and cheaper seen/closed
  stamps are the first moves. **Trigger:** a profile of many navigators.
- **Avoidance, and `travel?` on the other blocker sources.** "Clear" means no
  resolve falls short of the intended landing, so a system travels exactly when
  every source does: `CollisionSystem#travel?` would be `all?` over its sources.
  `BoundsBlockers` would answer in closed form (blocked only when the segment ends
  past an edge it moves toward). `ActorBlockers` is the open design — snapshot
  semantics over moving actors, its existing-overlap rule, its own sweep versus a
  closed-form swept box — and needs avoidance as a caller to settle. The shared
  group `a blocker source answering travel?` is ready for each. **Trigger:**
  steering that must rejoin a route.
- **Flow fields.** `rgame_route_neighbours` is the one neighbour-and-corner rule A*
  uses, public in `route_search.h`; a distance field from a goal is its second
  caller. **Trigger:** many walkers converging on one target.
- **Colliders larger than a tile.** Smoothing takes the next cell untested, sound
  only up to one tile, so `go_to` raises. Needs a search over cells the box fits
  (clearance per cell) and a smoothing that tests every step. **Trigger:** a large
  creature that must path.

---

## Precompiled gems beyond three platforms and one Ruby

The precompiled binary gems plan shipped `arm64-darwin`, `x86_64-linux-gnu` and
`x64-mingw-ucrt` for Ruby 4.0, and left five questions open that it did not need
to answer. Every other machine and every other Ruby installs the source gem and
compiles, which works, so none of these blocks anything.

- **Bundler lockfiles across platforms.** A game's `Gemfile.lock` written on
  Linux lists only Linux under `PLATFORMS`. Recent Bundler adds the running
  platform on `bundle install`, but whether that picks the platform gem or the
  source gem on a teammate's Mac has never been tried. **Trigger:** the first
  published version with platform gems — it can be checked the day one exists,
  and until then there is nothing to check against.
- **Ruby 4.1**, due December 2026. A platform gem is bounded to one ABI, so a
  4.1 user falls back to the source gem and compiles. Covering 4.1 means either
  one gem per ABI or one gem holding a directory per ABI with a loader that
  picks. **Trigger:** Ruby 4.1 existing, plus someone who wants binaries on it.
- **More platforms.** Intel Macs, ARM Linux, musl Linux and Windows on ARM each
  add a `build-gem` leg and a `smoke` leg. The machinery takes a new platform by
  adding it to `CheckPlatformGem::PLATFORMS` and the CI matrix; nothing else
  knows the list. **Trigger:** someone asking for one.
- **Whether the source gem should use the pinned SDL2 too.** It would make every
  install run the same SDL version, but it would need CMake and a network fetch
  during `gem install`, which is a lot to ask of the path taken when everything
  else failed. The recommendation is no. **Trigger:** a source install that
  breaks on a system SDL2 old or odd enough to be worth the cost.
- **Native Wayland decorations.** The Linux build image cannot build SDL with
  libdecor, so under `SDL_VIDEODRIVER=wayland` on GNOME — which draws no
  server-side decorations — a window has no title bar. SDL2 picks X11 through
  XWayland by default, so nothing hits this without asking for it. Building
  libdecor from source in the image is possible. **Trigger:** someone wanting
  native Wayland.

---

## CI runs the whole matrix twice for every step

**What.** Stop a merge to `main` re-running what the pull request just ran.

**What exists instead.** `.github/workflows/ci.yml` triggers on `pull_request`
and on a push to `main`, and every roadmap step is a branch, a pull request and
then a merge — so the same commit is verified twice. Measured on the step 5
merge: the squash of #60 produced tree `580b4e8`, byte-identical to the branch
head the pull request run had already checked, so all ten non-`release` jobs
re-verified an identical tree. That identity holds only while a branch is
current; when `main` has moved underneath one, the merge produces a tree nothing
has tested, which is the case the second run would genuinely be for.

`release` is the only job on `main` whose output is new, and it declines on
nearly every push — four published versions across twenty `main` runs.

**Why not now.** It costs nothing measurable. The repository is public and the
runners are standard, so every job reports a `billable.duration_ms` of `0`. The
six-minute critical path — `build-gem windows` at 5m, then `smoke windows` at 1m
— is waited on only for the pull request, because the `main` run happens after
the merge when nobody is watching it. Trimming `main` would save neither money
nor attention, and would amend release machinery that has only just landed.

**What it would take.** Four shapes were weighed:

- **Release on a tag.** `on: push: tags: ['v*']` runs the full matrix and
  publishes; a merge to `main` runs nothing. It fits how releasing actually
  happens here — a deliberate act, not a side effect of merging — and it would
  let the job stop manufacturing the tag it now creates just before the first
  `gem push`, since the tag would be the trigger and `tools/release_gems.rb`
  would verify HEAD against it rather than supply the evidence itself. The cost
  is that a merge which breaks `main` waits for the next pull request or the
  next release to surface it, which is safe only while branches are current and
  one step is in flight at a time — precisely what
  [implement-step](../../.claude/skills/implement-step/SKILL.md) stops
  guaranteeing when step N+1 branches off step N's branch.
- **Trim the pull request run** to Linux and keep all three platforms on `main`.
  The only shape that shortens the wait, and it gives up the one thing no local
  run provides: macOS and Windows before the merge rather than after it.
- **Gate `main` on a version bump**, skipping the matrix unless
  `lib/rgame/version.rb` changed in that push. That is `release_gems.rb`'s own
  question asked in seconds, ahead of six minutes of building rather than after.
- **Leave it**, which is what was chosen.

**Trigger.** The pull request wait growing long enough to be felt, or these runs
starting to be billed — which is what making the repository private would do,
since the free minutes are a property of it being public.

---

## State machines for per-frame behaviour

**What.** A state machine that decides every frame rather than a few times a
minute: an enemy that patrols, chases and flees, or a sprite whose animation
follows idle, run and jump. Each state would get an update hook, and a
transition would fire from a test run every tick rather than from an event.

**What exists instead.** `Engine::StateMachine` runs decision graphs: a quest's
stages and a conversation's beats. State moves when a player chooses or an event
arrives, and nothing in it runs per frame. Its conditions run on every
`available?` call, and its transitions list is built for a menu of choices, not
for a loop that must allocate nothing. The dialogue plan kept per-frame
behaviour out on purpose (its decision 6).

**Why not now.** No NPC or animation in this repository hand-rolls a state
machine, so nothing says what shape the per-frame one should take, or whether
it should share a graph with the decision one at all.

**Trigger.** The second hand-rolled state machine in NPC or animation code — a
`case @state` in an `update` written for the second time.
