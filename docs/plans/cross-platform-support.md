# Cross-platform support — macOS and Windows

**Status: steps 0–2 landed; B7 is what blocks a green leg on both platforms.**
Written 2026-08-21 from a read of the build wiring, the engine C, and the spec
scaffolding; revised twice since, after each CI run. Anything marked *(sketch)*
was never executed; anything marked *(measured)* came off a real runner.

**If you are picking this up on a Mac or a Windows box, start at
"Working on the machines directly", then run the experiment it names.** The
development loop changed after the second run: the work is debugged on the
machine and gated by CI, not driven through CI. Everything needed to build,
test and debug on either platform is in that section.

The question this answers: *what would the gem need to run on macOS and Windows,
and can that work be done on Linux and merely tested elsewhere?*

Per CLAUDE.md, this is a working document. When the work lands, whatever is
still true gets folded into `README.md` and CLAUDE.md's "Platform support"
section, and this file is deleted — git history keeps it.

## Verdict

**The engine is already portable. Everything that breaks is build wiring and
test scaffolding.**

That was not the expected answer. The risk going in was that the renderer would
need a modern-GL port before Windows could work at all, because Windows'
`opengl32.dll` exports only OpenGL 1.1 and everything after that needs a loader
(GLAD/GLEW). Measured rather than assumed, that risk is absent — see below.

So the work splits cleanly:

| | Scope | Where it fails today *(measured)* |
|---|---|---|
| **A. Build wiring** | 3 items, small, mechanical | macOS cannot link `make test`: `ld: library 'GL' not found` |
| **B. Test scaffolding** | 5 items, most of the effort | unreached — nothing Ruby-side runs until A is done |
| **C. Deliberate decisions** | 4 open questions | not blocking, but they shape A and B |

## What is already portable, and why

Stated with evidence, because "it looks fine" is not a finding and each of these
is a thing that did *not* need doing.

**Our own C contains no POSIX at all.** Grepping `ext/rgame_core/` outside
`vendor/` turns up no `unistd.h`, no `pthread`, no `dirent`, no path separators,
no `sys/*`. The only platform-conditional code in the tree is inside the
vendored libraries, which carry their own `#ifdef` ladders by design.
`fopen(path, "rb")` in [image.c](../../ext/rgame_core/graphics/image.c) and
[font_atlas.c](../../ext/rgame_core/text/font_atlas.c) already opens in binary
mode, which is the one detail that bites on Windows.

**The GL surface is OpenGL 1.1 throughout.** The complete list of entry points
the engine calls is `glBindTexture`, `glBlendFunc`, `glClear`, `glClearColor`,
`glColorPointer`, `glDeleteTextures`, `glDisable`, `glDisableClientState`,
`glDrawArrays`, `glEnable`, `glEnableClientState`, `glGenTextures`,
`glLoadIdentity`, `glMatrixMode`, `glOrtho`, `glPixelStorei`, `glScissor`,
`glTexCoordPointer`, `glTexImage2D`, `glTexParameteri`, `glTexSubImage2D`,
`glVertexPointer`, `glViewport`. Every one of those is GL 1.1, which is exactly
what `opengl32.dll` exports — **so Windows needs no extension loader.** The only
symbol from a later version is the enum `GL_CLAMP_TO_EDGE` (GL 1.2), and SDL's
`SDL_opengl.h` pulls in `SDL_opengl_glext.h`, which defines it. On macOS, SDL
hands back a legacy 2.1 compatibility context when no profile mask is requested,
and that supports the whole fixed-function pipeline this renderer is built on.

The decision recorded in CLAUDE.md's Conventions — no GL loader, legacy
profile — therefore costs nothing here. It is what makes the port small.

**Audio is already configured for all three platforms.**
[`miniaudio_impl.c`](../../ext/rgame_core/vendor/miniaudio_impl.c) enables
`MA_ENABLE_ALSA`, `MA_ENABLE_PULSEAUDIO`, `MA_ENABLE_COREAUDIO`,
`MA_ENABLE_WASAPI` and `MA_ENABLE_NULL`. miniaudio runtime-links its backends,
so macOS needs no frameworks on the link line and Windows needs nothing at all —
which is why `-lpthread`/`-ldl` are already *probed* rather than assumed in
[`extconf.rb`](../../ext/rgame_core/extconf.rb) and will simply not be appended
off Linux. The feature macros living in the `_impl.c` rather than in build
flags (CLAUDE.md, "Structure and why it looks like this") is what guarantees the
gem and the standalone binary support the same formats on every platform.

**The gemspec already excludes the right artifacts.** Its `artifacts` regex
covers `.bundle` and `.dylib` alongside `.so`, so a stale macOS build in `lib/`
cannot ship. Nothing to do.

## A. Build wiring — what actually breaks

### A1. `#include <SDL2/SDL.h>` — optional robustness *(measured: not a blocker)*

**This was the sketch's headline finding and the first CI run falsified it.**
On `macos-14` with Homebrew's SDL2, every SDL-including source compiled: the
run got as far as linking `build/test_rgame`, which requires
`build/librgame_core.a`, which requires `app.o`, `gl_backend.o`, `image.o` and
`font_atlas.o` — all five of the includes below. `-Wl,-framework,Cocoa` on that
link line confirms Homebrew's `sdl2.pc` was found and used.

The reasoning was sound and the premise was wrong: it generalised from the
*Debian* `sdl2.pc` read on the development machine, and Homebrew's evidently
publishes the parent include directory as well. **A1 is therefore not required
and not urgent.** It remains defensible as robustness — an SDL2 framework
install, MacPorts, or a non-default Homebrew prefix could still expose it — so
it stays in the plan, at the back.

The original analysis follows, since the mechanism is real even where the
conclusion was not. Look at what pkg-config publishes on Debian:

```
$ pkg-config --cflags sdl2
-D_REENTRANT -I/usr/include/SDL2
```

The include directory is `.../include/SDL2`, so the correct spelling is
`#include "SDL.h"`. `<SDL2/SDL.h>` resolves on Linux **by accident**: the parent
`/usr/include` happens to be a default system search path, so both spellings
work and the wrong one has never been caught. On Homebrew/Apple Silicon the
prefix is `/opt/homebrew/include`, which is *not* on clang's default path, so
`<SDL2/SDL.h>` is simply not found.

Affected — five includes across four files:

- [`app/app.c`](../../ext/rgame_core/app/app.c) (`SDL.h` and `SDL_opengl.h`)
- [`input/gamepad.c`](../../ext/rgame_core/input/gamepad.c)
- [`graphics/gl_backend.c`](../../ext/rgame_core/graphics/gl_backend.c)
- [`graphics/image.c`](../../ext/rgame_core/graphics/image.c)
- [`text/font_atlas.c`](../../ext/rgame_core/text/font_atlas.c)

Plus the probe in `extconf.rb`, which currently asks
`have_header('SDL2/SDL_opengl.h')` and would abort the install with a message
blaming a missing `libsdl2-dev` — a diagnosis that is wrong on a machine where
SDL2 is installed correctly. Both the include and the probe move to the
unprefixed spelling together; changing one without the other trades a compile
error for a confusing abort.

This one is verifiable on Linux in a weak sense: the unprefixed form is what
pkg-config's `-I` was always for, so it keeps working here. What cannot be
verified here is that nothing *else* in the search path shadows it.

### A2. OpenGL is linked three different ways

[`extconf.rb`](../../ext/rgame_core/extconf.rb) aborts honestly today — its own
comment says macOS wants `-framework OpenGL` and that only `-lGL` is
implemented. The fix is a branch on `RbConfig::CONFIG['host_os']`:

| Platform | Link flag | Probe |
|---|---|---|
| Linux, BSD | `-lGL` | `have_library('GL', 'glClear')` |
| macOS | `-framework OpenGL` | `have_framework('OpenGL')` |
| Windows (mingw) | `-lopengl32` | `have_library('opengl32', 'glClear')` |

Keep the aborts and keep them platform-specific: the current message names the
Debian package to install, and the macOS/Windows equivalents should name their
own. The value of that abort is that a missing GL surfaces as one sentence
rather than as an undefined `glClear` at the end of a long build, and that value
is highest on the platforms nobody here has tested.

### A3. The root Makefile hardcodes Linux — *(measured: this is what fails first)*

**Promoted from last to first by the CI run.** The sketch filed this as
developer-only and "lower priority than 1–2 if nobody is doing that yet". That
was wrong for a structural reason worth naming:

> **CI runs `make test` before anything else, and `make test` uses the root
> Makefile, not `extconf.rb`.**

So the root Makefile is the first thing *every* platform hits, on every run —
not a convenience for someone developing on a Mac. macOS died here with
`ld: library 'GL' not found`, at the `$(TEST_BIN)` link.

Note `-lpthread -ldl` survived that same link: macOS accepts both. Only the GL
branch is strictly load-bearing, but branch both rather than depend on that.

The items:

- `GL_LIBS := -lGL` and `AUDIO_LIBS := -lpthread -ldl`, same three-way branch as
  A2.
- The `.so` suffix in `LIB_CORE_SO` / `LIB_UTIL_SO` and the `$(EXT_*_SO)` copy
  targets. mkmf's `DLEXT` is `bundle` on macOS, so `make ext` would build the
  extension successfully and then fail to find `core_ext.so` to copy. Read the
  suffix from `RbConfig::CONFIG['DLEXT']` via a `$(shell ruby -e ...)` rather
  than branching on the host, so it tracks whatever the running Ruby actually
  produces.

`pkg-config --cflags check` for the Check suite works on Homebrew and MSYS2,
so the test binary's build needs nothing beyond the same GL/audio branch.

**Already fixed, ahead of the rest of A3:** `CC ?= gcc` at the top of the
Makefile had never taken effect on any platform. `?=` assigns only when a
variable is undefined, and make ships a built-in `CC = cc` whose origin counts
as defined — so every build this project has ever done used `cc`. Harmless on
Linux and macOS, where `cc` is the right compiler; not harmless under MSYS2,
where `/usr/bin/cc` is the msys-runtime gcc targeting a Cygwin-like ABI and
produces objects RubyInstaller's Ruby cannot load. It now forces `gcc` through
an `$(origin CC)` guard that still yields to an explicit `make CC=clang`.

## B. Test scaffolding — where the effort actually is

[`HeadlessDisplay`](../../spec_core/support/headless_display.rb) already gets
this right: it starts Xvfb on Linux, returns `:native` elsewhere, and gates
key-injection specs behind `can_inject_keys?`. The design is in place. What is
missing is everything underneath it.

### B1. Three support files hardcode Linux sonames or Linux-only mechanisms

| File | Problem | Fix |
|---|---|---|
| [`rendered_frame.rb`](../../spec_core/support/rendered_frame.rb) | `Fiddle.dlopen('libGL.so.1')` | `/System/Library/Frameworks/OpenGL.framework/OpenGL`, `opengl32.dll` |
| [`virtual_gamepad.rb`](../../spec_core/support/virtual_gamepad.rb) | `Fiddle.dlopen('libSDL2-2.0.so.0')` | `libSDL2-2.0.0.dylib`, `SDL2.dll` |
| [`x_keys.rb`](../../spec_core/support/x_keys.rb) | XTEST is X11-only | CGEvent (macOS), SendInput (Windows) |

The gamepad one is the easy case and stays honest on every platform: its own
comment already notes that `SDL_JoystickAttachVirtual` is SDL-level rather than
OS-level, so only the library name changes. Note the dlopen must find the copy
SDL *already loaded* rather than a second one; by-name dlopen does that on all
three, but it is worth asserting rather than assuming on Windows.

### B2. The back-buffer read makes a software-rasteriser assumption

This is the subtle one, and the one most likely to be misread as a bug in the
port. `rendered_frame.rb` documents that it reads the previous frame's pixels at
the start of the next frame, and that this **relies on the buffer swap being a
copy rather than a page flip — which is what Mesa's llvmpipe does under Xvfb**.

macOS and Windows CI runners have real drivers. If one of them page-flips, the
back buffer is undefined at that moment and the pixel specs fail. Its comment
argues that is safe because such a driver would make the specs *fail* rather
than silently pass — correct, and it means the failure will be loud and will
look like a rendering regression rather than a harness assumption.

The durable fix is to read **before** `SDL_GL_SwapWindow` rather than at the
start of the following frame, which needs no assumption about swap semantics at
all. Worth doing as part of this work rather than after the first confusing red
CI run.

### B3. Key injection is missing on two platforms, and the suite stays green

`filter_run_excluding(:needs_key_injection)` means a macOS or Windows run passes
while covering strictly less. That is the right behaviour — CLAUDE.md's
"Platform support" says so — but it makes "the suite is green on macOS" a
weaker claim than it reads as, and that should be stated wherever the result is
reported.

The two backends:

- **macOS: Quartz `CGEventCreateKeyboardEvent` + `CGEventPost`.** Needs
  accessibility permission, granted interactively, once per machine. **A CI
  runner cannot click that dialog**, so these specs stay skipped on macOS CI
  regardless of whether the backend is written. That makes this the lowest-value
  item in section B, and it should be scheduled last or dropped.
- **Windows: `SendInput` via Fiddle.** No permission prompt, so this one does
  pay for itself on CI.

### B4. `test_vorbis_decoder.c` hardcodes `/tmp` and `mkstemp`

[`test/test_vorbis_decoder.c`](../../test/test_vorbis_decoder.c) writes its
malformed-input fixtures through `mkstemp("/tmp/rgame_vorbis_testXXXXXX")`.
Fine on macOS; on Windows it needs `GetTempPath`/`tmpnam_s`. The file already
carries a comment explaining the `-std=c17`/POSIX feature-macro dance, so the
reasoning for whatever replaces it belongs in the same place.

### B5. Check loses fork isolation on Windows

Check runs each test in its own forked process, which is why a segfault fails
one test instead of aborting the run — a property CLAUDE.md calls out
explicitly as mattering *given how easy it is to crash while learning
pointers/SDL/GL*. MSYS2 provides `fork`, but it is slow and unreliable enough
that `CK_FORK=no` is the common setting there.

**Promoted from a footnote by the second run.** The audio crash (B7) hit both
platforms; macOS's fork isolation contained it to 19 reported errors, while
Windows lost the entire suite to the first one and reported a bare
`make: *** [Makefile:291: test] Segmentation fault` — not even which test.
Worse, Check's suite list is printed up front and buffered, so the truncated
list in the log says nothing about where it died.

Still nothing to fix in Check itself; what changed is that Windows now needs
the backtrace step in [`ci.yml`](../../.github/workflows/ci.yml) to say anything
useful at all, whereas on Linux and macOS that step is a convenience.

### B6. `no_graphics_spec` has no guard off Linux

[`spec/rgame/no_graphics_spec.rb`](../../spec/rgame/no_graphics_spec.rb) skips
itself without `/proc/self/maps`, and its own comment argues one platform
checking the property is enough. That reasoning holds — the property being
checked is about *what `lib/rgame.rb` requires*, which cannot differ per
platform. **Leave it alone.** Recorded here only so the skip is not mistaken for
an oversight during the port.

### B7. Opening a *real* audio device crashes on macOS and Windows *(measured)*

**This is the current blocking item on both platforms**, and it was not
predicted anywhere in the sketch — which had audio down as the one subsystem
already configured for all three (`MA_ENABLE_COREAUDIO`, `MA_ENABLE_WASAPI`,
and no link dependencies). Compiling and linking for all three, it turns out,
is not the same as opening a device on all three.

The macOS run localises it exactly, because Check's fork isolation reported
every test separately. Of 26 tests in `test/test_audio.c`:

| What the test opens | Count | Result |
|---|---|---|
| A **real** device (`rgame_audio_create`) | 19 | **all segfault** |
| The **offline** engine (`noDevice = MA_TRUE`) | 4 | all pass |
| Nothing — NULL-argument guards | 3 | all pass |

The correspondence is exact, and it clears almost the whole subsystem: the
offline tests load an `.ogg` through the vendored vorbis backend, mix it, and
assert on the PCM that comes out. So `calloc`, `ma_resource_manager_init`, the
custom decoding backend registration, the engine config and the mixer are all
proven working on macOS. **Only `ma_engine_init` with a device attached
crashes.**

Two hypotheses, and the evidence to hand does not separate them:

1. **miniaudio's runtime linking of CoreAudio.** It `dlopen`s the frameworks
   rather than linking them, and a failed symbol lookup would be called anyway.
   The fix would be `MA_NO_RUNTIME_LINKING` plus
   `-framework CoreFoundation -framework CoreAudio -framework AudioToolbox` —
   which is C3, already in this plan for the unrelated reason of notarization.
2. **No audio device on the runner at all.** GitHub's macOS and Windows images
   have no sound hardware, and a backend enumerating zero devices is a
   plausible crash surface. `MA_NO_RUNTIME_LINKING` would not help.

The comment in `create_audio` that says the null-device fallback is *"Verified:
with ALSA and PulseAudio unavailable, the chosen backend is Null"* is true and
was verified — **on Linux.** `a_device_opens_even_with_no_sound_card` is the
test asserting that property, and it is the first one to crash, so the property
does not hold off Linux. That test must keep opening a real device; skipping it
on CI would delete the only check of the thing that is broken.

**Next step is a backtrace, not a fix.** Guessing between the two hypotheses
costs a round trip either way, and one of them is a no-op. `ci.yml` now runs a
debugger automatically when the C suite fails — `CK_FORK=no` so the stack is
the crashing process rather than Check's parent.

## Can this be done from Linux? *(asked, answered, then superseded)*

**Write it on Linux: yes. Verify it on Linux: no — and the gap is the whole
problem.**

Every item in section A and most of section B share a failure mode that is
*invisible* here: a header search path that only differs off Debian, a `DLEXT`
that is only `bundle` on macOS, a dlopen soname, a buffer-swap semantic that
only differs on a real GPU. Writing them blind is possible; confirming them is
not, and blind changes to build wiring have a poor hit rate.

Which inverts the obvious ordering:

> **CI comes first, before any of the porting work.**

There is no `.github/` in the repo today. A three-runner matrix is what turns
"do it on Linux, test it elsewhere" from a hope into a working loop: push from
Linux, let the runner say which of the five things is wrong.

Two things the matrix will never cover, and they need a human on the machine:

- **The manual tier** — `make run` and `tools/drive_example.rb` against a real
  window server. Retina in particular: the window is created without
  `SDL_WINDOW_ALLOW_HIGHDPI`, so on a Mac it renders *correctly* but at half
  resolution and visibly soft. Whether that is acceptable is a judgment call, not
  an assertion (see C2).
- **macOS key injection**, per B3.

Cross-compiling with mingw and running under Wine was considered and rejected as
a Windows substitute: GL and audio under Wine test Wine, and a green run there
would not predict a real machine.

### Superseded: there are machines

**The reasoning above rests on a premise that turned out to be false** — that
nobody on this project could run macOS or Windows. Both are available. The
CI-first ordering was the right answer to "how do you verify what you cannot
run"; it is the wrong answer to "how do you debug a segfault on a machine you
own".

What changed, concretely: the work remaining is mostly *debugging*, not writing.
A crash of unknown cause, a library whose filename nobody here knows, a driver
whose swap semantics have to be observed. Those are minutes at a terminal and
round trips through a batch job that only prints what you thought to ask for in
advance. And one of them — macOS key injection (B3) — needs a permission granted
through an interactive dialog, so **CI can never run it at all**.

So the loop is now: **develop and debug on the machine, let CI gate.** See
"Working on the machines directly" below. CI keeps two jobs, neither of which
this changes:

- **It is the regression guard.** Linux staying green is a fact rather than a
  hope only because something checks it on every push.
- **It builds on a clean machine.** A developer's Mac has whatever Homebrew has
  accumulated on it; the runner has nothing. That difference is precisely how
  "works on my machine" reaches a gemspec.

Nothing built for the CI-first loop is wasted by this. Survey mode and the
automatic backtrace make CI a better gate regardless, and the three findings it
produced — Homebrew's include path, the msys/mingw split, and the `CC ?= gcc`
no-op — are now permanently guarded rather than fixed once.

## Working on the machines directly

Everything needed to pick this up on a Mac or a Windows box with no other
context. **These instructions are written from documentation and from what the
CI runs establish, not from a machine** — nobody here has run them. The first
person to follow them should correct them in place; that is what this file is
for.

The branch is `windows-and-mac-support`. Clone or pull it on each machine; push
from whichever one the work happened on. CI runs on pull requests, so a PR is
what turns three local checkouts back into one answer.

### macOS setup

```sh
xcode-select --install                  # clang, lldb, make
brew install sdl2 check pkg-config
mise install                            # Ruby 4.0.5, per .ruby-version
bundle install
```

Two things differ from Linux and neither is a problem:

- **No Xvfb.** `HeadlessDisplay` returns `:native` off Linux, so `rake spec:core`
  opens real windows on your desktop and you will see them appear and vanish.
  That is intended — macOS and Windows have a window server, so there is nothing
  to fake.
- **Key-injection specs skip themselves** (B3), so a green `rake spec:core` on a
  Mac covers less than a green one on Linux. Read the skip count, not just the
  colour.

Homebrew's prefix is `/opt/homebrew` on Apple Silicon and `/usr/local` on Intel;
pkg-config finds SDL2 either way, and the first CI run proved
`<SDL2/SDL.h>` resolves against Homebrew's `sdl2.pc` without the A1 fix.

### Windows setup

Use **RubyInstaller with the DevKit** for Ruby 4.0.5 rather than mise — the
DevKit is what supplies MSYS2, and every native build here depends on it. After
installing, run `ridk install` and choose the MSYS2 and MINGW development
toolchain option.

Then the libraries. Note `make` is an **msys** package with no prefix, while
everything else is **ucrt64**-prefixed — that split is the whole Windows story:

```sh
ridk exec pacman -S --needed \
  mingw-w64-ucrt-x86_64-SDL2 \
  mingw-w64-ucrt-x86_64-check \
  mingw-w64-ucrt-x86_64-pkgconf \
  mingw-w64-ucrt-x86_64-gcc \
  mingw-w64-ucrt-x86_64-gdb \
  make
```

#### The environment trap — read this before the first build

MSYS2 is several environments in one installation. **UCRT64** builds native
Windows binaries, which is what RubyInstaller's Ruby can load. **msys** builds
against a Cygwin-like runtime, which it cannot. Both have a `gcc` and both have
a `pkg-config`, and picking the wrong one fails in a way that looks like missing
packages rather than a wrong environment. That is exactly what happened on the
first CI run: pacman succeeded, and `pkg-config` then reported both `sdl2` and
`check` missing.

Work either from the **"MSYS2 UCRT64"** shell in the Start menu, or run
`ridk enable ucrt64` before building. Verify before trusting anything:

```sh
which gcc                   # must be /ucrt64/bin/gcc — NOT /usr/bin/gcc
pkg-config --cflags sdl2    # must print a ucrt64 include path
```

If `gcc` comes back as `/usr/bin/gcc`, stop and fix the environment; nothing
below will mean anything.

One more Windows-only fact worth knowing before it confuses you: **Check has no
fork isolation there** (B5), so the first segfault kills the whole test binary
and the output stops mid-suite — and because Check prints its suite list up
front and buffered, the truncated list does not tell you where it died. Use the
debugger recipe below rather than reading the log.

### Running the tiers

Same four tiers as CLAUDE.md describes, same commands:

| Tier | Command | Off-Linux notes |
|---|---|---|
| C unit tests | `make test` | Windows: no fork isolation (B5) |
| Standalone binary | `make` then `make run` | opens a real window |
| Both extensions | `make ext` | lands `.bundle` on macOS, `.so` on Windows |
| Headless specs | `bundle exec rake spec` | fully portable, no display |
| Core specs | `bundle exec rake spec:core` | native display; key specs skip |

`make ext` is a prerequisite for both spec suites — the Rakefile does not build
the extensions.

### Debugging a crash

`CK_FORK=no` is the load-bearing flag on **every** platform. Check normally runs
each test in its own forked child, and a debugger follows the *parent* — so
without it the stack you get is from a process that did not crash. Running
in-process stops at the first crash, which is what a backtrace wants anyway.

macOS:

```sh
CK_FORK=no lldb ./build/test_rgame        # then: run, bt all, frame select N
CK_FORK=no lldb --batch -o run -o 'bt all' -- ./build/test_rgame   # one-shot
```

Windows, from the UCRT64 shell:

```sh
CK_FORK=no gdb --args ./build/test_rgame  # then: run, bt full, info threads
```

To run one suite rather than all of them, Check reads `CK_RUN_SUITE`:

```sh
CK_FORK=no CK_RUN_SUITE=audio ./build/test_rgame
```

### Run this experiment first

**Before any fix, run `make test` on the Mac and report whether the audio tests
crash.** One command, and it splits B7 in half — which no amount of reading can
do from here.

The reason it discriminates: **your Mac has a sound card and the CI runner does
not.** So

- **audio tests pass on your Mac** → the crash is specific to having no device.
  Hypothesis 2. The real defect is then "miniaudio crashes when no device can be
  opened", the null-device fallback that `create_audio`'s comment promises does
  not happen off Linux, and the fix is in how the engine is initialised — not in
  how it is linked.
- **audio tests crash on your Mac too** → a real macOS defect independent of
  hardware. Hypothesis 1 or something not yet considered, and the backtrace is
  the next thing needed.

Either way the follow-up is cheap. To test hypothesis 1 — miniaudio resolving
CoreAudio through `dlopen` rather than linking it — add one line to
`ext/rgame_core/vendor/miniaudio_impl.c` beside the other feature macros:

```c
#define MA_NO_RUNTIME_LINKING
```

and give the darwin arm of the root Makefile's `AUDIO_LIBS` the frameworks that
then have to be linked explicitly:

```make
AUDIO_LIBS := -lpthread -framework CoreFoundation -framework CoreAudio -framework AudioToolbox
```

`ext/rgame_core/extconf.rb` needs the same frameworks on darwin if this turns
out to be the fix — the two build systems have to agree, and only the Makefile
is exercised by `make test`. This is also C3 arriving early: the same change is
what miniaudio requires for Apple notarization.

### What to do with the results

Record findings in this file as you go — that is what the *(measured)* tags and
the "Landed" notes are for, and it is what let the first two CI runs reorder the
whole plan. When a platform's leg goes green end to end, flip its `ported` flag
in [`ci.yml`](../../.github/workflows/ci.yml) so CI starts gating it; see "Flip
`ported: true`" below for why leaving it is worse than it looks.

## Implementation order

Dependency shape, so the ordering rationale is visible:

```
0 CI matrix ─→ 1 root Makefile ─→ 2 extconf GL ─┬─→ 4 dlopen names ─→ 5 pixel read ─→ ported: true
   (landed)      (GL + DLEXT)       (gem build) │
                                                └─→ 3 /tmp fixture  [Windows only]

                       optional, unblocked once 1–2 land:  6 SDL.h   7 key injection   8 packaging
```

Steps 1–2 are the C and the gem building at all; 3–5 are the two suites going
green honestly; 6–8 are optional and can be dropped without blocking anything.

**In flight, ahead of all of these: B7, the audio device crash.** It blocks a
green leg on both platforms and needs a backtrace before anyone can say what
the fix is, so the measurement is pushed and the steps below carry on in
parallel. It is not numbered because it is not sequenced — nothing below waits
on it, now that the unported legs run in survey mode.

**This ordering is the first run's, not the sketch's.** The sketch put the SDL
includes first and the root Makefile last; both were wrong, because `make test`
runs before everything and reads the root Makefile. Ordering a port by "which
file looks most fundamental" is guessing — ordering it by which command CI runs
first is not.

Each step should land with a **"Landed" note** recording how the result differed
from the sketch, the way `docs/plans/gosu-replacement/03-roadmap.md` does —
those notes are the useful part to read before starting the next step, because
most of them are decisions the sketch got wrong.

### Step 0 — CI matrix (do this first)

`ubuntu-latest`, `macos-14`, `windows-latest`, each running `make test`,
`rake spec`, `rake spec:core`. Expect macOS and Windows to fail immediately, at
step 1's include. **That is the deliverable**: a red run whose message is
specific is the feedback loop the rest of this depends on.

Ubuntu goes green from day one, so the matrix also earns its keep as the first
regression guard this project has had.

**Landed** as [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml). Four
things came out differently from the sketch:

- **Five steps, not three.** The sketch listed the three test tasks and forgot
  that neither spec suite builds its own extension — `make ext` is their
  prerequisite (CLAUDE.md, "Build"), so `rake spec` would have failed at load
  with a missing `rgame/util_ext` on a green Linux runner. `make` (the
  standalone binary) went in beside it, because it is the only tier that
  compiles `src/main.c` at all and it is free once the library is built.
- **`continue-on-error` on the unported legs, driven by a `ported` flag in the
  matrix.** Two permanently-red jobs would make the run red, and then Ubuntu
  stops being a usable regression guard — there would be no way to read
  "still unported, as predicted" apart from "somebody broke Linux". With the
  flag, the job shows red and the run stays green.
- **The Ruby pin is derived, not duplicated.** `.ruby-version` holds mise's
  `ruby 4.0.5`, which is not the bare string `ruby/setup-ruby` accepts, so a
  step `sed`s the prefix off and feeds the result in. Writing `4.0.5` into the
  workflow would have been a second home for the pin.
- **Three of the Linux packages are there only for `rake spec:core`**, and none
  of them is obvious from reading the Gemfile: `x11-utils` for the `xwininfo`
  that `HeadlessDisplay` polls, `libgl1-mesa-dri` for the llvmpipe without which
  `SDL_GL_CreateContext` fails under Xvfb, and `libxtst6` for the XTEST that
  `x_keys.rb` opens by soname rather than links.

Verified locally by running the Ubuntu leg's exact five commands in order:
318 Check assertions, 859 headless examples, 333 Core examples, all passing.
The macOS and Windows legs are unverified by construction — that is what the
first push is for.

**The Windows dependency step was a guess** (`ridk exec pacman …` with the
`ucrt64` package prefix), and it needed correcting — though not in the way
predicted. See below.

#### What the first run established

**Ubuntu went green**, which retires all three of the unknowns that local
verification could not cover:

- **Ruby 4.0.5 resolves in `ruby/setup-ruby`.** This was the highest-stakes
  binary fact in the whole plan — had it been missing, every leg would have died
  at the same step and the feedback loop would have been dead on arrival. All
  three legs got past it.
- **The audio suite passes with no sound device.** CLAUDE.md has claimed since
  the audio work landed that miniaudio's null-device fallback makes the same 26
  tests run "against PulseAudio on a desktop and against silence in CI". There
  was no CI, so the sentence had never been executed. It is now true rather than
  merely intended.
- **Xvfb + llvmpipe work on the runner's Mesa**, so `rake spec:core` — pixel
  readback included — is not tied to this one machine's graphics stack.

**macOS falsified A1 and promoted A3.** It compiled every SDL-including source
and died at `ld: library 'GL' not found`. Both sections are rewritten above.

**Windows was failing on the environment, not the packages.** pacman *succeeded*
— job-level `continue-on-error` does not skip past a failed step, so the job
reaching `make test` proves it exited 0 — yet `pkg-config` then found neither
`sdl2` nor `check`, and the compile came out as `cc`. Two symptoms, one cause:
the build was running in MSYS2's msys environment rather than ucrt64. The most
likely reason is that the dependency step ran *before* `ruby/setup-ruby`, so
`ridk` resolved against the Windows runner image's **preinstalled** Ruby and
configured that installation's MSYS2 instead of the one the build used.

Two fixes went in together, and either would be incomplete alone: the Windows
steps now run **after** setup-ruby, and `/ucrt64/bin` is prepended to
`GITHUB_PATH` so every tool resolves to the native-Windows environment. The
`CC ?= gcc` no-op in the root Makefile (see A3) was the second half of the `cc`
symptom and is fixed there rather than papered over with an env var here.

### Step 1 — root Makefile: GL and audio per platform (A3)

`-lGL` → `-framework OpenGL` / `-lopengl32`, and the `DLEXT` suffix for the
`make ext` copy targets. **This is what macOS is stuck on right now**, and
Windows will hit it immediately after its environment fix lands.

First because `make test` is the first thing CI runs and it reads this file —
the reordering the first run forced.

**Landed, and it worked on both platforms.** macOS linked with
`-framework OpenGL`, Windows with `-lopengl32`, and both then compiled all 25
engine translation units and ran the Check binary. Two things came out
differently from the sketch:

- **`CC ?= gcc` had to be fixed first** (recorded under A3) — it was a no-op,
  and on MSYS2 it silently selected the wrong ABI's compiler.
- **`DLEXT` is asked of the running Ruby**, with a fallback to `so` when no
  Ruby is installed, so `make test` does not acquire a Ruby dependency it never
  had. Verified by overriding both the platform detection and `DLEXT` on this
  machine: all five `uname -s` cases resolve correctly, and `DLEXT=bundle`
  propagates to `lib/rgame/core_ext.bundle`.

It also revealed the next wall, which is not a build problem at all: B7.

### Step 2 — `extconf.rb`: GL linking per platform (A2)

The same three-way branch, in the file `gem install` actually runs. Keep the
aborts and make them platform-specific: naming the package to install is worth
most on the platforms nobody here can debug.

macOS's next wall after step 1, since `have_library('GL', 'glClear')` is what
stands between it and a built extension.

**Landed, unverified off Linux.** Branches on `RbConfig::CONFIG['host_os']`:
`have_framework('OpenGL')` on darwin, `have_library('opengl32', 'glClear')` on
mingw/mswin/cygwin, `-lGL` elsewhere. Linux re-verified end to end — extconf
regenerated, extension rebuilt, 859 headless examples green — and the branch
selection checked against seven `host_os` spellings.

Two things to watch on the next run, both unverifiable from here:

- **`have_framework` may be the wrong probe.** mkmf implements it by compiling
  `#include <OpenGL/OpenGL.h>` with `-ObjC`, and this extension's `$CFLAGS`
  carry `-std=gnu17`. If those interact badly the probe fails on a Mac that can
  link OpenGL perfectly well, and the abort fires on a working machine — worse
  than no probe. If that happens, append `-framework OpenGL` to `$LDFLAGS`
  unconditionally on darwin and drop the check.
- **The header probe still asks for `SDL2/SDL_opengl.h`** (A1), which the first
  run proved Homebrew satisfies. It is the one place A1's spelling still has a
  gate in front of it, so if a Mac ever fails there, that is A1 arriving late
  rather than a new problem.

### Step 3 — the vorbis fixture's `/tmp` (B4)

Windows-only, but it blocks `make test` there, so it sits ahead of everything
Ruby-side. macOS is unaffected.

### Step 4 — dlopen names in the spec support (B1)

`rendered_frame.rb` and `virtual_gamepad.rb`. First step where `rake spec:core`
can get anywhere on either platform.

### Step 5 — read pixels before the swap (B2)

Do this *before* interpreting any macOS or Windows pixel-spec failure, so a
harness assumption cannot be mistaken for a renderer bug. Real GPU drivers are
free to page-flip; llvmpipe's copy-swap is what the current read relies on.

### Flip `ported: true` — per platform, when its leg is actually green

Not attached to a single step, because a leg goes green only once *all* of
1–5 that apply to it are done. The sketch pinned this to steps 2 and 3, which
was wrong: `rake spec:core` runs on every leg, so the spec scaffolding gates it
just as much as the compiler flags do.

Leaving a working platform marked unported is how it silently rots back out —
`continue-on-error` means nobody would notice it break again. See the flag's
comment in [`ci.yml`](../../.github/workflows/ci.yml).

### Step 6 — `"SDL.h"` robustness (A1, optional)

Demoted by the first run from "the thing that breaks first" to "insurance
against SDL2 installed somewhere Homebrew does not put it". Cheap, still
defensible, no longer urgent.

### Step 7 — Windows key injection (optional)

`SendInput` via Fiddle, per B3. macOS CGEvent is deliberately **not** scheduled:
it needs an accessibility permission no CI runner can grant, so it would be
exercised only by a human at a desk.

### Step 8 — the packaging decision (see C1)

## C. Decisions to make deliberately

### C1. Source gem or precompiled binary gems

Today the gem compiles on install, so a Windows user needs RubyInstaller+DevKit
and MSYS2's SDL2 package before `gem install rgame` works. That is a rough first
experience, and it decides whether "runs on Windows" means *runs for developers*
or *runs for users*.

The alternative is precompiled native gems via `rake-compiler-dock`. It is a
substantially larger project than this whole port and is worth deferring — but
it should be deferred **knowingly**, because it also changes what CI is for
(building release artifacts, not just checking).

### C2. Retina / high-DPI

Adding `SDL_WINDOW_ALLOW_HIGHDPI` makes text crisp on a Mac and immediately
splits window size (points) from drawable size (pixels). `glViewport` and every
clip rect are currently fed the window size, and they would need the drawable
size instead. That is a real change to the coordinate story, not a flag — and it
would want its own plan. **Out of scope here**; the port ships correct-but-soft.

### C3. Notarization, if a game is ever shipped as a `.app`

miniaudio runtime-links CoreAudio, which its own documentation warns may fail
Apple's notarization. The fix is `MA_NO_RUNTIME_LINKING` plus
`-framework CoreFoundation -framework CoreAudio -framework AudioToolbox`.
Irrelevant for a gem; relevant the first time somebody distributes a built game.

### C4. What CLAUDE.md should say afterwards

Its "Platform support" section currently describes the Linux-first state
accurately. When this lands, that section — and the `Requirements` part of
`README.md` — is where the result belongs, and this file goes away.
