# rgame

A small 2D game engine for Ruby, written in Ruby and C. SDL2 + OpenGL in C, wrapped as Ruby C extensions.

## Code comments, documentation and code style

Add top-level comments to modules, classes and C files describing what they are
and do. Public methods of Ruby classes — and their C-layer equivalents, the
functions exposed via `rb_define_method` — get an explaining comment when
they're non-trivial and the name doesn't already tell the whole story. 

Comments inside methods or on private methods get automatically deleted on commit - write them freely, but don't rely on them. Write code that speaks and reads cleanly without those comments.

Documentation rules live in the [write-docs](.claude/skills/write-docs/SKILL.md) skill; specs follow [write-spec](.claude/skills/write-spec/SKILL.md), plans [write-plan](.claude/skills/write-plan/SKILL.md), and the skills themselves [write-skill](.claude/skills/write-skill/SKILL.md).

Prose someone else reads is written with [write-prose](.claude/skills/write-prose/SKILL.md) loaded — load the skill before the first sentence, not from memory. That covers the top-level
comments on modules, classes and C files, and the explaining comments on public
methods. It also covers `CHANGELOG.md` and `README.md`, which have no skill of
their own, and everything the skills above produce.

## Design out misuse: the right thing must be the easy thing

Aim for a design that admits little or no misuse. When something *must* happen
for the engine to work, making it happen is the engine's job — never a rule the
calling code is asked to remember.

Two examples of the shape this takes:

- **Give the user a blank hook, keep the machinery separate.** A node exposes
  an empty `_draw` to override, while `draw` does the bookkeeping and calls
  it. That is better than one `draw` the user overrides and must remember to
  `super` from — because forgetting `super` is silent, and the failure shows up
  somewhere else entirely.
- **The engine makes its own required calls.** A node that can be rotated
  applies that rotation inside its own `draw`; it does not depend on the author
  remembering to wrap their drawing in `renderer.rotated`.

The same principle governs project structure, not just class design, and that
is the test to apply when adding any convention: *if following the rule depends
on someone remembering, the design is wrong.* Concretely — the headless spec
suite lives in its own directory with its own runner, rather than in a shared
one with an `exclude_pattern` that must not be forgotten. A convention that
fails loudly beats one that has to be observed.

### `Node2D` and `Component`: `rgame_` seals a method, `_` marks a hook

These two are the classes a game subclasses, so their non-public methods are
names a game author can collide with without knowing they exist — and in Ruby
`private` limits who may *call* a method, not who may *replace* one. A subclass
method named like the base's machinery is found first and silently switches
that machinery off for the class. (A UI button's draw hook was first named
`draw_content`, and broke every draw.)

So in `Node2D` and `Component`, and **only** there:

- **A private or protected method whose name starts with `rgame_` is
  machinery**, such as `rgame_draw_content`. `Engine::SealedPrivates` raises
  `NameError` when a subclass defines one of the same name, at class definition
  rather than on some later frame. The prefix matches the C layer's
  `rgame_app_push_clip`, and no game names a method that by accident.
- **A private or protected method without the prefix is a seam**, meant to be
  overridden with `super` — `Node2D#draw_children` is the one there is.
  Unguarded by design.

And a method whose name starts with `_` is a **hook**, which the engine calls
and a subclass overrides, such as `_draw` or a component's `_attach`.
`Engine::Hooks` raises `NameError` when a subclass defines a `_` method that no
ancestor has, so a misspelled hook fails where it is written. A class adding a
hook for its own subclasses declares it with `hook :_gain_focus` before the
`def`, as `UI::Button` does. A name starting with `on_` is a signal and nothing
else, and `Signal::DSL` raises when a subclass replaces what it generated.

Adding a non-public method to either class is therefore a decision about which
of the two it is, and `spec/rgame/engine/sealed_privates_spec.rb` lists each
class's seams so that an unprefixed method added without deciding fails there.
The seal covers only the two base classes' own methods: in an engine subclass a
private hook such as `Components::Mover#take_step` is ordinary. The `_` rule
covers every subclass of the two, engine ones included.

## Before building: find the thing it resembles

Reuse is the easy half, and this project already does it well — a new component
reaches for `Pool`, `Timer`, `CollisionBox` without being told. The hard half is
**generalization**: the existing thing that is not the same as what you are about
to build, but is close enough that one shape should have covered both.

Nothing in the code asks that question for you. Two subsystems that should have
been one look perfectly reasonable side by side — each coherent, each tested,
each with a plausible reason to exist. They only read as a mistake from the one
place that needs both at once, and that place is usually written last.

So when planning a system or component, inventory what exists and sort it into
three piles rather than one:

- **Reuse it.** The existing thing does the job.
- **Extend or generalize it.** The existing thing does most of the job, or the
  same job for a different input. Either it grows a parameter, or both become
  one thing with two callers.
- **Genuinely new.** Nothing resembles it — which is a conclusion to reach, not
  a default to start from.

The middle pile is what this section is for, and the test that fills it is not
"do these share code" but **"do these two answer the same question about
different things?"**

Tile collision and body collision were built independently and each was correct,
and they answered the same question about different things: *what is in the way*.
Unifying them afterwards took six steps and touched every collision file in the
project. The [write-plan](.claude/skills/write-plan/SKILL.md) skill has that case
in full, and the five checks a sweep of existing code runs.

### Two smells, and why nobody smelled them

- **Parallel vocabularies.** Two subsystems whose types line up one-for-one —
  a shape each, a resolver each, a "what stopped me" each — are usually one
  subsystem with two backends. Write the two lists side by side; the rows that
  pair up are the generalization.
- **A hook whose only job is handing one component's data to another.** That is
  the seam where the two should have met, reported at runtime instead of at
  design time.

And the reason both went unnoticed for so long is worth stating on its own,
because it is a second guideline: **two systems verified only in isolation can
both be green and still compose badly.** Each had its own specs and both passed.
What no test covered was a node using both, and counting said why — of every
scene in `examples/`, `test_projects/` and the specs, the number mounting both
systems was **zero**. The case the whole design was eventually reworked for had
never once been built.

So when a new subsystem sits next to an existing one, the acceptance test is not
"does mine pass" but **"what does a caller using both of us look like, and does
anything exercise it?"** If the answer is that nothing does, that is the test to
write first, and it is the cheapest moment this design will ever be questioned.

## RuboCop

Run RuboCop over the Ruby files you touched, as a finishing step:

```
bundle exec rubocop path/to/changed_file.rb
```

**Scope it to the files you changed.** There is a backlog of pre-existing
offenses elsewhere in the project; leave those alone unless clearing them is
the actual task, so unrelated churn stays out of the diff.

`-a` (safe autocorrect) is fine unprompted. `-A` (unsafe autocorrect) can change
semantics, so only with a deliberate look at what it did.

Attempt to fix offenses, but watch for rules that don't fit this codebase. A lot
of RuboCop is written with web applications in mind and this is a game engine,
so some rules make the code worse. In that case add an exception rather than
write worse code:

- a justified one-off → inline `# rubocop:disable Cop/Name -- reason`
- a codebase-wide rule → an entry in `.rubocop.yml`

**Either way, say why.** `.rubocop.yml` already models this: its `Metrics/*`
block explains that a game engine's `update`/`draw` methods run long and its
coordinate variables are idiomatically short. An exception without a reason is
indistinguishable from having given up.

### The custom cops are house rules — don't disable them

`lib/rgame/rubocop/cop/game/` holds six project-specific cops (plus the shared
`HotPath` and `LayerBoundary` mixins). They ship in the gem as a RuboCop plugin
(`lib/rgame/rubocop.rb`, defaults in `lib/rgame/rubocop/default.yml`), and
`.rubocop.yml` loads them through that plugin exactly as a game does — so the
project generated by `rgame new` runs the four game-facing ones plus
`NoCoreInEngineLayer` over its `nodes/` and `spec/`. A change to a cop is a
change to every game's lint; `spec/rgame/cli/generated_project_spec.rb` checks
that each one still fires there.

| Cop | Enforces |
|---|---|
| `Game/NoInterpolationInHotPath` | no string interpolation in per-frame methods |
| `Game/NoNeedlessAllocation` | no throwaway Array/Range literals on a per-frame path |
| `Game/DrawInLocalSpace` | a node's draw methods never read its own position — `Node2D#draw` pushes its transform, so both `x` and `world_x` are already applied |
| `Game/NoCoreInEngineLayer` | no `RGame::Core` reference, and no require of `rgame/core` or `rgame/game`, in `lib/rgame/engine/` or `spec/` — the engine layer must stay headless |
| `Game/NoEngineInCoreLayer` | the mirror: no `Engine` reference in `lib/rgame/core/` or `spec_core/` — Core must not know Engine exists |
| `Game/NoLiteralText` | no String literal as the label of `text`, `text_width` or `text_lines` in `examples/` or `lib/` — text a player reads comes from a translation table |

These exist because a steady 60fps frame that allocates is a GC pause waiting to
happen, and the cost is invisible without a guard. Unlike stock cops, these are
the ones that *do* fit here — fix the code, not the cop.

### A label built from a changing value

`Game/NoInterpolationInHotPath` refuses the obvious `renderer.text("Score:
#{@score}", ...)`, and the engine owns the answer: **`RGame::Engine::Text`.**
Build it off the per-frame path; read it with `with` in `_draw`, or pass it to
`renderer.text` as it is when it has no variables — or when something else gave
it its values through `with`, such as a button's label. A `Text` answers
`to_str`, so no `.to_s` is needed.

```ruby
def initialize
  super
  @score = Engine::Text.new('hud.score', :score)   # "Score: %{score}" in the table
end

def _draw(renderer, _view) = renderer.text(@score.with(score: @points), 12, 10)
```

It keeps the last string and renders again only when a keyword differs or
`I18n.generation` moves, so a score that changes once costs one render, a
language switch re-renders on the next read, and the frames between cost
nothing — measured at zero objects over 200,000 unchanged reads, for zero, one
and three variables. Text assembled from several translations, or formatted
rather than translated, uses `Engine::Text.computed(:status) { |status:| ... }`,
whose block runs under the same rule; `examples/pathfinding` is the worked
example, a status line put together from four keys, two of them plurals.

**Reach for it rather than inventing a way round the rule.** Every hand-rolled
dodge is a reader's puzzle: `examples/sound` drew a row of rectangles to avoid
formatting a count, and the comment explaining why was longer than the code.

**Two shapes that need no `with` at all:**

- **Text chosen by state is a table of `Text`s.** A frozen hash keyed by the
  state — `STATE = { true => Engine::Text.new('state.fullscreen'), false =>
  Engine::Text.new('state.windowed') }.freeze` in `examples/fullscreen`, `STATUS`
  in `examples/save_load` — selects a `Text` rather than building a string. A
  `Text.computed` block returning one of several constants is strictly worse to
  read, and a table of Strings is text no translation can reach. A `Text` is
  safe in a constant; a `Text.computed` made at the top level of a file is not,
  because its block keeps that file's locals — `game` among them — alive.
- **A value that never changes and is not words.** Build it once in `initialize`
  and keep it in an ivar, the way a `Sheep` in `examples/save_load_ids` keeps
  `id.to_s`. A number has nothing to translate, and a cache for something that
  cannot change is indirection with no payer.

## What exists

The C engine — window, fixed-timestep loop, input, images, a z-sorted batching
renderer, text and audio — is wrapped by `ext/rgame_core/ruby/`, and the Ruby
half under `lib/` is backed by a second, graphics-free extension. The gem
packages both and is published on RubyGems.

**Split-screen, and the input layer with it.** A game has *seats*
(`Game.new(players: 2)`); an `RGame::Engine::Player` owns a device, a binding
table, a camera and a region of the screen; the shared world is updated once and
drawn once per viewport by a `WorldView`; and which player a node answers to is
inherited down the tree like its transform. A device is seated when somebody uses
it, not when it is plugged in. See `docs/api/scene_graph.md`, `input.md`, `ui.md`.

**The UI package is a beginning, not a toolkit.** `PlayerLayer` and `UI::Menu`
cover a region per player, focus and activation — the minimum for
keyboard-and-controller navigation. Layout, nesting, scrolling lists and text
entry are all still open, and `docs/api/ui.md` says so under "What this is not".

**Text on screen is translated by default.** `RGame::Game` loads every
`locales/**/*.yml` and picks the player's language from the OS; a node draws an
`Engine::Text` built from a key, and a UI button's `label:` is a key. Every
example keeps an `en.yml` beside its `main.rb`, and a driven run exits 1 on a
missing key. `test_projects/` are games rather than teaching material and still
draw Strings. Engine code measures text with `Util::Typeface`, headless, and
`UI::Label` draws a translated paragraph a page at a time, broken to its width in
every language. Button slots keep a fixed width by choice, so a longer translation
can still overflow one. See `docs/api/text.md` and `docs/api/localization.md`.

**Build a new feature in C** under `ext/rgame_core/`, and extend the Ruby wrapper
once the C API is settled — unless it is engine-layer work, which is pure Ruby by
definition.

## The Core / Util split

**This is the first question to answer about any new code: does it depend on
SDL, OpenGL, or on something that does?**

- **Yes** → `RGame::Core`, built from `ext/rgame_core/`, required as
  `rgame/core_ext`, loaded via `require "rgame/core"`.
- **No** → `RGame::Util`, built from `ext/rgame_util/`, required as
  `rgame/util_ext`, loaded via `require "rgame"` — which also loads
  `RGame::Engine`, since between them they are everything that runs without a
  window.

Everything Ruby-visible is under the `RGame` module — no other top-level
constant. Both `Init_` functions call `rb_define_module("RGame")`, which is
idempotent, so load order between the two extensions doesn't matter.

The split is load-bearing, not cosmetic. `require "rgame"` loads `RGame::Util`
and `RGame::Engine` with **zero graphics libraries in the process**, which is
what lets game logic and its specs run with no display and no SDL present.
So `lib/rgame.rb` must never require `rgame/core`, directly or
transitively — that would silently destroy the property for every consumer.

`spec/rgame/no_graphics_spec.rb` asserts it, so `rake spec` catches a breach
rather than a human remembering to look. By hand it is:

```
ruby -Ilib -e 'require "rgame"; puts File.read("/proc/self/maps").scan(/libSDL2|libGL\./).uniq.inspect'
# => []
```

The three entry points, each a strict superset of the last:

| | |
|---|---|
| `require "rgame"` | `Util` + `Engine` — no graphics |
| `require "rgame/core"` | the window, the GPU, the sound device |
| `require "rgame/game"` | all of it, wired; what a game writes |

`rgame/util`, `rgame/engine` and `rgame/core` stay separately requirable, so
nothing is forced through `rgame.rb`. That is how `spec_core/` loads exactly one
layer and gets a `NameError` if it names another.

If a subsystem has both a pure part and an SDL-driven part, split it across
the two rather than putting the whole thing in Core — that's the same
layering rule as below, applied at the extension boundary.

### Value objects go in Util; only handle-owners go in Core

The sharper form of the same question, and the one to apply when a type could
plausibly sit on either side:

> **Anything that is a shareable *value* belongs in `Util`. Only something that
> owns a GPU or OS *handle* belongs in `Core`.**

A colour, a vector, a rect, a grid are values: cheap, comparable, no resources.
A window, a texture, a font, an audio device own something the OS gave us and
must give back. `Tensor` is a value and lives in Util; `App` owns a window and
lives in Core.

`RGame::Util::Controls` is the worked example. It is nothing but integers — the
ids for keys, pad buttons, axes and device slots. Those started in Core, because
the C engine defines them and asserts them against SDL's own scancodes. But an id
is a value, and a game's control config has to be able to name one:

```ruby
controls = RGame::Util::Controls
map = RGame::Engine::InputMap.default.merge(
  fire: { buttons: [controls::KEY_SPACE, controls::PAD_A] }
)
```

In Core that is impossible for engine-layer code, which may not name Core at
all. In Util it is ordinary — and it is what lets the whole binding table live
in `RGame::Engine::InputMap`, one per player, built out of Util values.
`RGame::Core::Input` keeps only the raw query. The C `#define`s stay where they are — `src/main.c`
includes only `rgame/core.h` and needs them — so the numbers exist twice, and
`spec/rgame/util/controls_spec.rb` parses the header and compares every one.
Duplication with a guard beat putting a value out of reach.

This is not tidiness — it is what makes the engine layer below usable. Engine
code may hold Util types as attributes but may **not** hold Core types at all,
so putting a value type in Core would put it permanently out of reach of the
scene graph that wants to store it.

## The three layers, and who may talk to whom

```
RGame::Engine   scene tree, signals, sprites, tile maps, pathfinding — pure
                game concepts, no SDL, fully spec-able headless
      |  may hold Util types as attributes
      |  may CALL methods on Core objects it is handed, by name
      |  may NOT name, require or hold a Core class
      v
RGame::Core     App, Input, Renderer, ... — owns windows, GPU and OS handles
RGame::Util     Tensor, and every other shareable value type
```

`RGame::Engine` lives in `lib/rgame/engine/` and is the layer a game is
actually written against. Its hard rule:

- **It may hold `RGame::Util` types.** `RGame::Engine::TileMap` packs its per-layer gid
  rows into a `Util::Tensor` — the C one — which is the worked example: a value
  with no OS handle behind it, so the layer above may own one outright.
- **It may not name `RGame::Core` at all** — no `require`, no constant
  reference, no attribute. Not even in its specs.
- **It reaches Core only through objects handed to it**, duck-typed. A node's
  `draw` receives a `renderer` and calls methods on it that it knows by name.
  It never stores that renderer, and never asks what class it is.

That is what keeps the whole engine layer, and any game built on it,
spec-able with no window, no GPU and no clock — specs drive `update(dt)`
directly and can run a simulated hour in milliseconds.

Two things enforce it rather than merely asking for it:

- Engine specs never load `rgame/core`, so `RGame::Core` is simply an
  undefined constant during those runs — a stray reference raises `NameError`
  instead of quietly working.
- `Game/NoCoreInEngineLayer` (see the RuboCop section) flags any `RGame::Core`
  reference under `lib/rgame/engine/` or `spec/`, which also catches the
  branches a test run never reaches.

### The rule points both ways: Core must not name Engine either

`RGame::Engine` is built **on top of** `RGame::Core`, so Core should not know
it exists. Not one constant, not one require, anywhere under `lib/rgame/core/`
or `spec_core/`.

This is the easier of the two to break, because nothing catches it at runtime.
Loading Engine into a Core spec works perfectly well; the inversion would go
unnoticed until someone tried to use Core on its own, or until a change in a
scene concept forced a change in the texture layer. `Game/NoEngineInCoreLayer`
is the only guard, and it flags both spellings — `RGame::Engine` and the bare
`Engine` the layer still has before it is ported — because the interim is
exactly when the mistake gets made.

Where a Core class genuinely needs something Engine has, it takes the object and
calls it by method name — the same duck-typing the engine layer uses on a
renderer, pointed the other way. `Core::TileMapRenderer` is the worked example:
it needs a tile grid, so it is *handed* one and calls `map.gid(layer, col, row)`
and `map.above_layer?(index)`, and could not tell you what class answered.

**The one place allowed to name both layers is the glue**, a single class
directly under `RGame`. Wiring the two halves together is what a glue class is
*for*, and confining that to one file is what keeps the rule above checkable
everywhere else. Reading a `.tmx` into an `RGame::Engine::TileMap`, handing the result
to a `Core::TileMapRenderer` and registering the pair with the asset manager is
three lines, and they belong there rather than smeared across either layer.

Because the engine may only call a renderer by name, that method list is a real
interface with more than one implementation — the live `RGame::Core::Renderer`
and every recording fake a spec substitutes. Both must be checked against the
same shared example group, or the fake drifts and a fully green headless suite
stops predicting whether the game runs. See "Testing" below.

## `draw` renders state; time enters through `update`

**Nothing on a draw path reads a clock.** Not `App#ticks_ms`, not
`Process.clock_gettime`, nothing. A frame is drawn from state, and state is
advanced by `update(dt)`.

This is not a style preference, it falls out of the loop:

- **`draw` is not called on a schedule.** `needs_redraw?` can skip it entirely,
  and the catch-up loop can run several `update`s between two draws. So `draw`
  has to be a pure function of state — and the one thing that varies between
  frames without being state is the clock.
- **A wall clock cannot be paused, slowed, or reproduced.** Freeze the
  simulation and wall-clock animation keeps running. A spec cannot assert
  "the third frame of the walk cycle" without sleeping.

So a cosmetic animation — one with no game state behind it — accumulates its own
elapsed time in `update` and hands the *number* to the renderer at draw time:

```ruby
def update(dt) = @elapsed += dt
def draw(renderer) = renderer.tilemap(@id, camera.x, camera.y, w, h, elapsed: @elapsed)
```

`RGame::Engine::Animator` and `RGame::Engine::Timer` are both built this way, and
`DebugOverlay` is *handed* the frame rate rather than asking for it.

The point is not that a number gets passed either way — it is **who owns the
number**. Core reading the clock means Core has an opinion about what time it
is; the game passing one means pause is "stop accumulating", slow motion is
"accumulate slower", and a spec is "pass 2.5". It also allows two clocks at
once, which one wall clock cannot express at all: a pause overlay has to keep
animating while the world it covers is frozen.

Elapsed time is in **seconds**, like `dt` and everything else here. Convert at
the boundary if some format speaks milliseconds — Tiled's frame durations do —
and convert once per draw rather than once per item.

`App#ticks_ms` still exists and is still correct: it is the raw clock, for the
shell that measures frames. It is not for drawing.

## Structure and why it looks like this

**Every file's own top comment says what it is and why it is shaped that way** —
that is this file's first rule, and those comments are the reference.

**All engine C lives in `ext/rgame_core/`**, not a top-level `src/`, grouped by
subsystem. Where a new source or Ruby-visible class goes, what `extconf.rb` needs
from it, the three layers every subsystem is split into, and the C conventions
are all in [write-c-code](.claude/skills/write-c-code/SKILL.md).

**`tools/` and `rakelib/` don't ship.** `tools/platform_gem.rake` is deliberately
*not* in `rakelib/`, which rake would load on every invocation: rake-compiler
would warn about `make ext`'s object files every time, and the Linux build image
has no bundle to load the `Rakefile`'s RSpec tasks from.

### `lib/`

Two kinds of file live there. Most are the Ruby side of a **C-backed class** — a
require of the extension plus a comment saying what moved to C, and the obvious
place to add a Ruby convenience later. The rest are **whole classes in Ruby**
(`sprite_sheet.rb`, `nine_slice.rb`, `ui_atlas.rb`, `tile_map_renderer.rb`,
`asset_manager.rb`). What makes those `Core` is not that C is behind them —
nothing is — but that they **hold handles**: an image is a GPU texture, so
anything owning one belongs on this side of the line.

- `lib/rgame/game.rb` — the only class directly under `RGame`, and by
  construction the only one allowed to name both layers.
- `lib/rgame/engine/` — the scene graph, and the layer a game is written against.
- `lib/rgame/boot.rb` — enables YJIT if this Ruby has it. **This Ruby has no
  YJIT**, so locally it is a verified no-op.
- `lib/rgame/version.rb` — the version and nothing else. The gemspec loads it
  before either extension is compiled.
- `spec/spec_helper.rb` requires only `lib/rgame`. A Core file reached from there
  would pull SDL into the process and the suite would stop meaning what it says.

### `exe/rgame` and the project generator

Two rules hold up the CLI. **It requires only stdlib and `rgame/version`** —
never `rgame`, `rgame/core` or `rgame/game` — so scaffolding works before either
extension is built, and the CLI can be specced from `spec/`, where a stray
require fails loudly.

And **no file under `lib/rgame/cli/templates/` may be named with a leading dot.**
`Dir.glob('lib/**/*')` derives `spec.files` and does not match dotfiles, so a
template called `.gitignore` would be absent from the installed gem while working
perfectly in the checkout. Dotfile templates are stored under plain names
(`gitignore.tt`) and renamed on the way out through `NewProject::DOTFILES`.
`spec/packaging_spec.rb` asserts it *without* going through `Dir.glob`: a guard
that shares the blind spot it is guarding is not a guard.

`spec/rgame/cli/generated_project_spec.rb` generates a project and runs its RSpec
and RuboCop for real — the promise is worth nothing described.

## Build

Plain Makefile for the C (written to mirror what `mkmf` emits, so the mental
model carries over), with targets that shell out to the mkmf-generated
Makefiles for the extensions:

```
make              # builds build/rgame (standalone C binary)
make run          # build + run
make test         # build + run the Check unit tests
make ext          # build both extensions
make ext-core # ext/rgame_core -> lib/rgame/core_ext.so
make ext-util     # ext/rgame_util     -> lib/rgame/util_ext.so
make clean        # includes ext-clean
```

`make ext-util` is a prerequisite for `rake spec` — `lib/` requires the
compiled `rgame/util_ext`, so those specs can't even load without it.
`make ext-core` is a prerequisite for `rake spec:core`.

Ruby-side tasks come from the `Rakefile`:

```
rake spec         # headless: RGame::Util + RGame::Engine, no SDL in the process
rake spec:core    # RGame::Core; opens real windows, boots its own Xvfb
rake build        # package the gem into pkg/ (from bundler/gem_tasks)
rake              # make test, then both suites
```

Ruby is 4.0.5, pinned in `.ruby-version` and installed via mise. Requirements
are listed in README.md.

## Packaging

`rgame.gemspec` ships both halves as one gem. Both `extconf.rb` files are in
`spec.extensions`, so `gem install` compiles each one and lands its `.so` in
`lib/rgame/` — the same place `make ext` puts it, which is why nothing about
the load path changes between a checkout and an installed gem.

### What ships, and what must never be listed by hand

A version is four gems — a source gem plus three platform gems carrying the
extensions already built. How they are built, checked and published is in the
[release](.claude/skills/release/SKILL.md) skill.

**`spec.files` is a glob over whole directories, never a list.** Anything the
installed gem compiles from or reads at runtime — a new `.c`, a font, any data
file — must ship, and the failure mode when it doesn't is invisible locally: the
checkout still has the file, so it only breaks on someone else's machine, at
`require` time or at the first call that reads it. Dropping a file under `lib/`
or `ext/` is therefore enough to get it packaged, by design. Do not replace the
glob with an enumeration, and do not keep a "remember to add it to the gemspec"
checklist — that is exactly the remembered rule "Design out misuse" rejects.

`spec/packaging_spec.rb` is what makes that safe rather than merely intended. It
re-derives what must ship from the directory tree and asserts it against the
gemspec's own derivation, in both directions: every C source and header, every
`extconf.rb`, everything under `lib/` including non-Ruby data, the vendored
sources and their licences — and, the other way, that no build artifact, spec
directory or plan is in the gem. If the two derivations ever disagree, one of
them is wrong and the suite says which file.

One exclusion is deliberate and it is asserted: **build artifacts**
(`lib/rgame/*.so` and friends) — that is *this* machine's binary, and shipping
it would shadow the one `gem install` compiles.

**When an exclusion comes out, replace it with an example asserting the thing
ships** rather than deleting it. A rule that used to be stated and is now merely
true goes silent, and this is the one file whose job is saying out loud what
ships.

Publishing is CI's job, not a local `gem push`; the steps are in the
[release](.claude/skills/release/SKILL.md) skill.

The version lives in `lib/rgame/version.rb` and nothing else may go in that
file: the gemspec loads it directly, long before either extension is compiled,
so a require reaching for `rgame/util_ext` there would break `gem build`.

## Testing

C tests use [Check](https://libcheck.github.io/check/), which forks each test, so
a segfault fails that test rather than aborting the suite.

**Verification tiers**, matching the layers above. Pick the cheapest one that can
answer the question.

| Tier | Covers | Needs |
|---|---|---|
| `make test` | layers 1 and 2 — pure logic, and fake backends asserting on recorded calls | nothing |
| `rake spec` | `RGame::Util`, `RGame::Engine`, what the gem packages, and whether `docs/api/`'s examples run and its links resolve | `make ext-util`; **no SDL in the process at all** |
| `rake spec:core` | `RGame::Core`'s Ruby-visible surface, the names `docs/api/` mentions, and whether every public name is documented or tagged `@api private` | `make ext-core`; opens real windows, boots its own Xvfb |
| `make run`, `ruby ext/rgame_core/example.rb` | layer 3, by eye | a human |

The first three are expected to pass for every change. The
[verify](.claude/skills/verify/SKILL.md) skill has the rest: the live-window
tier, leak checking, and mutation testing.

### The test projects are the acceptance test for wiring — but only if they are *driven*

Anything that changes how the layers are wired together — `RGame::Game`, the
asset loaders, input polling, the renderer's id registries — is verified by
running the games under `test_projects/` and `examples/`, the only tier where all
three layers are present at once.

**Booting one is not enough.** A polling bug that consumed every input edge
before a tick could read it left a game whose menu answered nothing, and a plain
boot of it reported "90 ticks, 90 frames" and looked healthy. Drive it instead:

```
ruby tools/drive_test_project.rb examples/collision_tiles/main.rb --ticks 240
```

`tools/drive_test_project.rb` boots the project unmodified, feeds it a scripted
input backend through `RGame::Game`'s `input:` keyword, stops on a tick budget,
and reports draw calls, clips, sounds, scenes entered and ticks against frames.
A script holds **one timeline per device**, so a two-player run is two `on`
blocks playing at once, every track absolute from tick 0.

**A script's path mirrors its project's**, so the line above reads
`tools/drive/examples/collision_tiles.rb`. Deriving it from the directory's
basename would let two trees of projects collide silently, a game driven by
another game's inputs reporting something confusing rather than failing.
`--script` overrides it, which is how one project has several.

Four flags change what a run proves:

| | |
|---|---|
| `--seed N` | seeds the project's own RNG through `RGAME_SEED`, so two runs are byte-identical. **Exact draw counts are comparable only with it**; otherwise assert on structure — scenes entered, sounds fired, clip and translate counts |
| `--texts` | every distinct string drawn with `text`, which is how two runs are compared string for string |
| `--gamepad` | a synthetic SDL controller instead of the scripted backend, exercising the real device path |
| `--installed` | leaves the load path alone, so `rgame` resolves to whatever is installed — how CI's `smoke` job plays the examples out of a platform gem |

A key `I18n` could not answer is drawn as itself and listed under "missing or
mismatched keys", and a project that loaded translation tables then exits 1 — so
a key left out of an example's `en.yml` fails the run rather than reaching the
screen. Every run names the `core_ext` and `util_ext` it loaded, at the top of
its report; that is what tells an `--installed` run from a checkout one, because
the draw counts do not.

### Why the Ruby specs are two suites, in two directories

They are two *processes*, and that is the entire point. RSpec loads everything
under its root into one process, so a single `require "rgame/core"` anywhere
would define `RGame::Core` for every other example in the run — and the
engine layer's guarantee (that it cannot even name Core) would silently
evaporate. An `exclude_pattern` would technically work and is exactly the kind
of rule someone forgets; separate directories with separate runners cannot be
forgotten. See "Design out misuse" above.

So:

| | `spec/` | `spec_core/` |
|---|---|---|
| Runner | `rake spec` | `rake spec:core` |
| Covers | `RGame::Util`, `RGame::Engine` | `RGame::Core` |
| Loads | `require "rgame"` only | `require "rgame/core"` |
| SDL in process | **never** | yes |
| Display | none | its own Xvfb |
| Needs | `make ext-util` | `make ext-core` |

`spec_core/` exists because the layer it covers is ours. The library that used
to sit in this position came with its own tests; writing the window, the
renderer and the sound device ourselves made testing them our job too.

### Fakes and what the suites skip

The engine layer calls a renderer, an audio server and a tile map only by method
name, so each has a real implementation and a recording fake that must not drift
from it. **Read the skip count, not just the colour** — a green `rake spec:core`
on macOS or Windows covers strictly less than a green one on Linux. The
[verify](.claude/skills/verify/SKILL.md) skill has the three contracts, the four
rules for writing a refusal, and which capability each platform probes at
runtime.

## Conventions

- C is C17, `-Wall -Wextra` and warning-clean, on legacy-profile GL with no
  loader — see [write-c-code](.claude/skills/write-c-code/SKILL.md).
- Ruby: `# frozen_string_literal: true` at the top of every file, single
  quotes, RuboCop (+ `-performance`, `-rspec`) via the `Gemfile`. Configured in
  `.rubocop.yml`, which also loads the project's own cops from
  `lib/rgame/rubocop/` — see the RuboCop section above.
- One runtime gem dependency, and no more: `rexml`, declared in
  `rgame.gemspec`. The Tiled loaders parse XML with it, and Ruby ships it as a
  *bundled* gem rather than a default one, so Bundler hides it from a project
  that does not declare it. 0.2.0 and 0.3.0 left it out, and `require "rgame"`
  failed in every Bundler project. Everything else `lib/` requires is a default
  gem or plain stdlib, and `spec/packaging_spec.rb` fails on a require that is
  neither nor declared. Reach for a core method before a second dependency —
  `tile_map.rb` decodes Base64 with `unpack1('m')` for exactly this reason — and
  treat adding one as a deliberate decision, not a drive-by change. The
  `Gemfile` holds development gems (RSpec, RuboCop) and the two bundled gems
  the Core specs need to call C directly (`fiddle`, `base64`), never a gem
  `lib/` needs: the checkout would load it while an installed gem could not.
