# Replacing Gosu — plan index

This folder is the working plan for replacing `lib/platform/` + Gosu with a
C layer under `RGame::Core` (plus whatever is better left in Ruby).

Read in order:

| Document | What it covers |
|---|---|
| [00 — Brief and decisions](README.md) *(this file)* | Goal, hard constraints, decisions already taken, open questions |
| [01 — Inventory](01-inventory.md) | What `lib/platform/` actually is today, every Gosu call it makes, and what each class needs from a C layer |
| [02 — Target architecture](02-architecture.md) | The shape of `RGame::Core`: module layout, the layers inside the renderer, and the C-vs-Ruby split per class |
| [03 — Roadmap](03-roadmap.md) | Phased implementation order. Detailed for phases 0–6 (0–5 implemented), deliberately rough after that |

Phases 0–5 are implemented: the window and loop, input and gamepads, the whole
renderer — images, primitives, transforms, clipping and recordings — text, and
audio. The roadmap's per-step "Landed" notes say where the result differed from
the plan. Phase 6, the port of `lib/platform/` itself, is planned in the same
detail and not started.

---

## The goal

`lib/platform/` is a small Ruby layer over Gosu. It is the **entire** boundary
between the game engine and real hardware — window, GPU, audio device, input.
The plan is to replace `Gosu + lib/platform/` with a C layer (`RGame::Core`),
keeping in Ruby only the parts where Ruby genuinely reads better and costs
nothing.

`docs/c_engine_feature_specs.md` is the feature spec derived from that same
boundary. It is the *what*; this folder is the *how* and the *in what order*.

## Hard constraints

1. **The public API of the `Platform::*` classes is preserved.** A pure-Ruby
   engine layer sits on top of these — `lib/engine/`, in the repo since before
   phase 6, see ["The engine layer is here
   now"](#the-engine-layer-is-here-now--constraint-1-became-checkable) — and it
   must not have to change. Method names, argument shapes, keyword arguments
   and return values stay as they are. Only the *class names* and the
   *implementation* move.

   Two deliberate exceptions, both decided below: **mouse input is dropped**
   rather than ported, and **`GameWindow`'s accumulator loop moves into C**,
   which changes `update` from no-arg to `update(dt)`. Everything else is a
   rename-and-reimplement.

2. **Class renames are fine and expected.** `Platform::GosuInput` →
   `RGame::Core::Input`, `Platform::GosuRenderer` → `RGame::Core::Renderer`,
   `Platform::GameWindow` → `RGame::Core::App`, and so on. The `Gosu` prefix
   was only ever there to name the backend.

3. **Everything Ruby-visible from the new C layer lands under `RGame::Core`.**

4. **`require "rgame"` must still load zero graphics libraries.** This is the
   existing Platform/Util rule in CLAUDE.md and it survives the rewrite intact
   — see "Naming" below for how `Core` fits into it. The check stays:

   ```
   ruby -Ilib -e 'require "rgame"; puts File.read("/proc/self/maps").scan(/libSDL2|libGL\./).uniq.inspect'
   # => []
   ```

5. **The layering discipline in CLAUDE.md applies to all of it**: pure logic
   first (Check-tested, no SDL/GL), then a recording fake backend, then a thin
   real SDL/GL shim. Most of what is hard in a 2D renderer — z-sorting,
   transform composition, clip intersection, glyph atlas packing, tile
   culling — is pure arithmetic and needs no window to test.

## Decisions already taken

These come out of the framing of the work and are not up for re-litigation
inside the plan; they are recorded here so the reasoning is not lost.

### `RGame::Core` replaces `RGame::Platform`

`Core` is the new name for the SDL/GL-linked half. It is a rename, not a third
namespace:

| | before | after |
|---|---|---|
| Ruby namespace | `RGame::Platform` | `RGame::Core` |
| Extension dir | `ext/rgame_platform/` | `ext/rgame_core/` |
| Required as | `rgame/platform_ext` | `rgame/core_ext` |
| Opt-in require | `require "rgame/platform"` | `require "rgame/core"` |

`RGame::Util` is untouched and keeps its job: everything with no SDL/GL
dependency, loaded by the default `require "rgame"`. The split is what makes
constraint 4 hold, so it must not be collapsed.

One consequence worth stating plainly, because it will come up repeatedly:
**a pure-logic C module that `RGame::Core` needs cannot live in
`RGame::Util`.** They are two separate `.so` files. Sharing a C type across
them (say, a `Color` struct that Core unwraps from a Util-owned object) means
exported symbols and a shared header between two independently-built
extensions — real complexity for little gain. So the rule becomes:

> Pure-logic C that only `Core` uses lives in `ext/rgame_core/` as an
> internal module with its own Check tests. It is still layer 1 and still
> fully testable headlessly; it just isn't Ruby-visible from `Util`.
> `ext/rgame_util/` is for pure logic that **Ruby** calls on its own.

`Color` looked like the concrete case for that, and was originally placed in
`Core` on those grounds. That was reversed: the deciding question is not "who
uses it" but "is it a value or a handle". A colour is a value, the engine layer
may hold Util values but may not name `Core` at all, so `Color` belongs in
`Util`. See CLAUDE.md, "Value objects go in Util; only handle-owners go in
Core".

### `App` absorbs `GameWindow`'s shape, not the other way round

`RGame::Platform::App` today is a *callback sink*:

```ruby
app.run(update_proc, draw_proc, needs_redraw_proc)
```

`Platform::GameWindow` is a *subclass* of `Gosu::Window` that overrides
`update` / `draw` / `needs_redraw?` / `button_down`. The engine layer above is
written against the second shape. So `App` changes to be subclassable and the
proc-passing form goes away. Details in [02](02-architecture.md#appwindow).

### The fixed-timestep accumulator lives in C

`GameWindow#update` currently runs the accumulator itself: add elapsed time,
loop 0–5 simulation steps, drop the backlog if the cap is hit. That moves into
the C layer, where `frame_loop.c` already implements it (with the best test
coverage in the project) and already drives `rgame_app_run`.

Consequences, all of them simplifications:

- `update(dt)` means **one fixed tick**. The Ruby side stops counting steps.
- `@dirty` falls out for free — if `update` ran at all, a step ran, so
  `@dirty = true` inside `update` reproduces `steps.positive?` exactly.
- `Platform::Clock` is deleted; nothing else reads wall-clock time.
- `STEP` and `MAX_STEPS` become C constants (`RGAME_TICK_SECONDS`,
  `RGAME_MAX_TICKS_PER_FRAME`, already in `app.c`).

Note this contradicts `docs/c_engine_feature_specs.md` §1, which says the
accumulator "stays on the engine side of the boundary". That line was written
before `frame_loop.c` existed. Its actual concern — that the *game* never sees
variable frame time — holds either way, and is better served by the C loop
handing Ruby a guaranteed-fixed `dt`. **The feature spec should be amended when
this lands**, so the two documents don't disagree.

The one property this would otherwise lose is `GameWindow`'s "poll input once
per frame, reuse across all catch-up steps"; it comes back structurally via a
per-frame input snapshot in C plus a `frame_begin` hook — see
[02](02-architecture.md#input-is-snapshotted-per-frame).

### Mouse input is not carried over

The current layer handles the mouse: `GosuInput#pointer_x`/`#pointer_y`, the
`:pointer` binding onto `Gosu::MS_LEFT`, and mouse buttons riding the same
"is held" path as keys. **None of it is ported.** So the new `Core::Input` has
no `pointer_x`/`pointer_y` and no `:pointer` entry in its binding table, the
button-id space covers keyboard and controllers only, and no
`SDL_MOUSEBUTTON*`/`SDL_MOUSEMOTION` handling goes into the event pump.

This is the one place the rewrite deliberately *shrinks* the API rather than
preserving it. `docs/c_engine_feature_specs.md` §1 and §5 still list mouse
state as required; they should be amended alongside the accumulator note above.

### Gamepads and split-screen are in scope — this is an extension, not just a port

`docs/c_engine_feature_specs.md` lists both under "required (planned, not yet
implemented)", and this is where the current Gosu + Ruby layer gets *extended*
rather than merely replaced. Neither can be deferred to "later" the way
optional polish can, because both change the shape of code written before them:

- **Controllers** need the button-id space, the "is held" query and the event
  callbacks designed around multiple devices from the start. Retrofitting a
  device index into a single-device `down?(id)` API touches every caller.
- **Split-screen** needs the transform and clip stacks to support several
  concurrent viewport regions composed and torn down within one frame — a
  proper push/pop stack, not one global mutable region. A renderer built
  assuming a single active clip/transform has to be rebuilt to get this.

So: gamepad support is part of phase 2 (not a follow-up), and split-screen is a
stated requirement on the phase 3 transform/clip design even though no scene
uses it yet. What is *not* required is a second camera in any Ruby code — only
that the C layer can express one.

### `gosu_patches.rb` disappears entirely

It exists solely to strip a `|*args|` splat out of Gosu's generated per-frame
callback wrappers. A hand-written C binding uses fixed-arity function pointers
from the start (`core.h` already does), so the problem cannot occur. This is
called out in the feature spec §4 as a design requirement, and it is already
satisfied.

The RuboCop cop `Game/PreferGosuModuleMethod` becomes obsolete at the same time
and should be retired with it. The *principle* it enforced — no allocating
shim on a per-frame path — is preserved structurally rather than by lint.

### The default font is vendored, not looked up

`Gosu::Font.new(18)` needs no path, and constraint 1 says
`GosuRenderer#initialize`'s signature survives the port — so the new `Font`
needs a default from somewhere. There were three candidates: ask the operating
system the way Gosu does, embed a font, or require an explicit path and accept
the API change.

**How Gosu does it** (read from gosu 1.4.6's sources, not from memory):

- It ships **no font file at all**. `Font.hpp:25` defaults the name to
  `default_font_name()`, a per-platform constant: `"Liberation Sans"` on
  Linux/BSD, `"Arial"` on macOS and Windows. Liberation Sans is the Linux choice
  because it is metric-compatible with Arial, so a layout measured on one
  platform occupies the same space on the others.
- Name → file goes through the OS font database, one backend per platform:
  **fontconfig** on Linux (`TrueTypeFontUnix.cpp`), **CoreText** on macOS,
  **GDI** on Windows. The gem's `.so` links `libfontconfig` and `libfreetype`.
- It is not one lookup but a **fallback stack**, walked per glyph
  (`TrueTypeFont.cpp:237`). On Linux: Arial Unicode MS → DejaVu → Unifont →
  fontconfig's `sans-serif` match → the hardcoded path
  `/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf`. A literal
  Debian path in a cross-platform library is a fair summary of how well this
  goes.
- Rasterisation is `stb_truetype`, vendored in the gem's `dependencies/stb` —
  the same upstream `stb_image.h` came from.

**The decision: vendor Liberation Sans 2.x and do no lookup at all.**

Copying Gosu means three platform backends plus a **fontconfig system
dependency on Linux** — exactly what `ext/rgame_core/vendor/README.md` credits
itself with avoiding for PNG ("the only dependency the gem does not have to ask
for"). The font is the same trade at a comparable size:

| | |
|---|---|
| `LiberationSans-Regular.ttf` (Liberation 2.x) | 410 KB — against the 276 KB `stb_image.h` already vendored |
| Licence | SIL OFL 1.1 (Liberation **1.x** is GPL-2+-with-exception; take 2.x) |
| Coverage | 2327 codepoints, verified from the cmap |

Coverage was checked rather than assumed: Latin-1 Supplement and Latin
Extended-A are complete, so English, German, French, Italian, Spanish,
Portuguese, Nordic and Polish are covered in full, including `ß`, capital `ẞ`,
`« »`, curly quotes and `€`. Greek and Cyrillic come along too. Not covered:
CJK, Arabic, Hebrew, Devanagari — no font of this size covers those, DejaVu
Sans (739 KB) included. A game needing them passes its own font path.

Vendoring also buys something the system lookup structurally cannot: **text
renders identically on every machine.** Gosu's own five-deep fallback chain is
the evidence — a UI laid out against one font on the developer's box and
another on a player's is a layout bug nobody can reproduce.

So `Font.new(app, 18)` uses the shipped font, `Font.new(app, 18, path: '…')`
loads a file, and there is **no font-name lookup** — "find me something called
Arial" is not something this engine offers.

### Audio is vendored too, and it is not SDL_mixer

The roadmap originally recommended SDL_mixer "for v1", on the grounds that it
gives ogg, looping and a playing-query almost free and that audio is not where
this rewrite's interesting problems are. Both halves of that are true. The
recommendation was still wrong, and measuring is what showed it.

**What SDL_mixer actually costs.** It is a *system* dependency, needed twice:
`libsdl2-mixer-dev` to build the gem and `libsdl2-mixer-2.0-0` to run it. On
this machine `apt install libsdl2-mixer-dev` pulls **~8 MB**, six of which is
`timgm6mb-soundfont` — a General MIDI instrument bank, because SDL_mixer plays
MIDI. For an engine that wants to play a few ogg files.

**What everyone else does.** Read from sources, not memory:

| Engine | Device layer | Codecs | New system deps |
|---|---|---|---|
| raylib | `miniaudio.h`, vendored | stb_vorbis, dr_wav, dr_mp3, dr_flac — vendored | none |
| DragonRuby | MojoAL, vendored | stb_vorbis, vendored | none (ships one binary) |
| Gosu | MojoAL, vendored | SDL_sound, vendored | libvorbis, libsndfile, mpg123 |
| SFML 3 | `miniaudio.h`, bundled | dr_mp3 bundled; Vorbis/FLAC found by CMake | vorbis, FLAC |
| Godot | its own ALSA/Pulse/CoreAudio/WASAPI drivers, `dlopen`ed | libogg + libvorbis vendored | none |
| LÖVE | OpenAL | ModPlug, Vorbis, mpg123 | several |
| **ruby2d** | **SDL_mixer** | via SDL_mixer | **SDL2 + image + mixer + ttf** |

Nobody in the small-C-engine category uses SDL_mixer. The one that does is
ruby2d — the closest peer to this project — and the price is visible in its
`extconf.rb`: a hand-maintained table of package names for yum, pacman, zypper,
apt and pkg, plus **~20 prebuilt static archives** shipped in the gem for macOS
and Windows because system libraries are hopeless there. That is the real cost
of depending on the SDL satellite libraries: either your users fight their
package manager or you become a distributor of binaries.

**The two finalists, both prototyped and measured** against the whole feature
set this engine needs — load an ogg, overlapping one-shots, looping music,
`playing?`, stop, volume:

| | miniaudio + stb_vorbis | MojoAL + stb_vorbis |
|---|---|---|
| New system dependencies | **none** | **none** (SDL2 is already required) |
| Source vendored | 4200 KB | 393 KB |
| Object code added | 983 KB | 188 KB |
| Compile time for the vendored TU | 5.5 s | 0.6 s |
| Links | `libm`, `libc` — ALSA/Pulse are `dlopen`ed | libSDL2, already linked |
| Glue for the feature set | **149 lines, written and working** | 83 lines *without* streaming or real voice management |
| Streaming music | free (`MA_SOUND_FLAG_STREAM`) | must be written: queue/unqueue buffers plus a pump |
| Overlapping one-shots | free | must be written: a voice pool and a stealing policy |
| Maintenance | active (0.11.25, 2026-03) | active; the `sdl2` branch still gets fixes (2026-04) |

**Decision: miniaudio, with stb_vorbis for ogg.**

The deciding factor is not the table's top half but its bottom. MojoAL is ten
times smaller and compiles ten times faster, and if that were the whole story it
would win. But OpenAL hands back exactly the two things the roadmap called "a
real project on its own": streaming and voice management. Streaming in
particular needs a pump, and a pump driven from our frame loop turns a slow
frame into an audio dropout — a quality problem, not a line-count one. miniaudio
runs its own device thread and gives both away.

Two things worth knowing before implementing:

- **miniaudio does not decode Ogg Vorbis out of the box.** It does wav, mp3 and
  flac; vorbis needs a custom decoding backend, and miniaudio's own reference
  one uses *system* libvorbis, which would give the dependency straight back.
  The 149 lines above are a backend over vendored stb_vorbis instead. It works —
  one-shots, streaming, looping, `playing?`, stop and volume all verified
  against a real `.ogg`.
- **It needs both `onInitFile` and `onInit`.** The low-level `ma_decoder` path
  uses the first; the high-level `ma_engine` (which is where voices and
  streaming live) reads through miniaudio's VFS and calls the second, with
  read/seek callbacks. stb_vorbis has no callback-based open, so `onInit` reads
  the *compressed* file into memory and uses `stb_vorbis_open_memory`. That is a
  few MB per music track, not the ~40 MB a full PCM decode would cost.

**What would reverse this**: 983 KB of object code roughly doubles `core_ext.so`
(761 KB today), and 4 MB of vendored source would be ten times everything else
vendored here combined. If that weight turns out to matter more than the
streaming work, MojoAL is the fallback and Gosu and DragonRuby both prove it
viable. It is a reversible decision — the glue is small on either side.

## The engine layer is here now — constraint 1 became checkable

This section used to say the opposite, and it was true for phases 0–5:
`lib/platform/` referenced an `Engine::` namespace that did not exist in the
repo, so constraint 1's promise ("the layer above must not have to change") was
a promise nothing local could verify, and the guidance was "when in doubt, keep
it byte-identical".

That changed before phase 6 started. `lib/engine/` (3,083 lines, 57 files),
`lib/son_gosu_game.rb`, two runnable games under `examples/`, and the engine's
own documentation under `docs/engine/` are all in the tree. So:

- **The two examples are phase 6's acceptance test.** `examples/14_asteroids`
  and `examples/15_tiled_world` running on `RGame::Core` is what "the port
  worked" means. That is a far better check than reading the old file beside
  the new one, and phase 6 is structured around it.
- **The engine layer needs no change to be ported to.** Grepped: `lib/engine/`
  names `Gosu` and `Platform::` in **comments only** — not one constant
  reference in code. It reaches everything through duck-typed seams
  (`renderer`, `node.root.context.assets`, an audio server behind
  `Engine::AudioDirector`). Constraint 1 was honoured by the layer itself, not
  just promised to it.
- **What does change is boot code**, and only boot code: `SonGosuGame` and
  `examples/14_asteroids/main.rb`. `examples/15_tiled_world/main.rb` names the
  platform zero times and is untouched.

The mouse remains the one real cost, and it is now measurable rather than
feared. Outside the UI package (which is outdated and being replaced anyway),
it is six lines: `ActionMapper#poll` calls `backend.pointer_x`/`pointer_y`
**unconditionally**, so polling does not run at all against a `Core::Input`
that has neither, plus `Actions#pointer_x`/`#pointer_y` and the `Clickable`
component. Fixing that is engine-layer work, not this plan's — see
`docs/plans/engine-replacement/`, which collects what was found while checking
this.

## Open questions

Recorded here rather than guessed at. None of them block phase 0–2.

1. ~~**Default font.**~~ **Settled — the engine ships a font.** See
   ["The default font is vendored, not looked up"](#the-default-font-is-vendored-not-looked-up)
   under decisions already taken.
2. ~~**Audio dependency.**~~ **Settled — miniaudio, vendored.** See
   ["Audio is vendored too, and it is not SDL_mixer"](#audio-is-vendored-too-and-it-is-not-sdl_mixer)
   under decisions already taken.
3. ~~**Whether `Renderer` stays one class.**~~ **Settled — one class, and
   `Audio` likewise.** The primitives exist now and took the by-object shape
   (`renderer.image(image, …)`), so a by-id layer is needed on top either way;
   two façade classes would need two names for a role that already has one, and
   `Audio` is now the sound device. Both registries fold into the existing
   classes. See [roadmap 6, "Decisions to take before writing any of
   it"](03-roadmap.md#decisions-to-take-before-writing-any-of-it-2), which also
   records what it costs.
