# Cross-platform support — macOS and Windows

**Status: step 0 landed; steps 1–7 outstanding.** Written 2026-08-21, from a
read of the build wiring, the engine C, and the spec scaffolding as they stand
on `main`. The CI matrix that the rest of this plan depends on is in place —
see "Implementation order", step 0.

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

| | Scope | Where it fails today |
|---|---|---|
| **A. Build wiring** | 3 items, small, mechanical | `gem install` on a Mac aborts on a missing header |
| **B. Test scaffolding** | 5 items, most of the effort | the suite goes green while covering less |
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

### A1. `#include <SDL2/SDL.h>` — fails on macOS, and fails first

This is the first thing that breaks and the least obvious. Look at what
pkg-config actually publishes:

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

### A3. The root Makefile hardcodes Linux twice

[`Makefile`](../../Makefile) is developer-only — `gem install` never reads it —
but developing *on* macOS or Windows needs it:

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

No action beyond knowing it: on Windows, a segfault in the C suite takes the
whole binary down and the output stops at the crashing test.

### B6. `no_graphics_spec` has no guard off Linux

[`spec/rgame/no_graphics_spec.rb`](../../spec/rgame/no_graphics_spec.rb) skips
itself without `/proc/self/maps`, and its own comment argues one platform
checking the property is enough. That reasoning holds — the property being
checked is about *what `lib/rgame.rb` requires*, which cannot differ per
platform. **Leave it alone.** Recorded here only so the skip is not mistaken for
an oversight during the port.

## Can this be done from Linux?

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

## Implementation order

Dependency shape, so the ordering rationale is visible:

```
0 CI matrix ─┬─→ 1 SDL includes ─→ 2 GL linking ─→ 3 Makefile ─┐
             └─→ 4 dlopen names ─→ 5 pixel read ───────────────┴→ 6 key injection
                                                                └→ 7 packaging decision
```

Steps 1–3 are the gem building at all; 4–5 are the Core suite going green
honestly; 6–7 are optional and can be dropped without blocking anything.

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

**The Windows dependency step is a guess** (`ridk exec pacman …` with the
`ucrt64` package prefix). Nobody here has a Windows machine; which invocation is
right is one of the things the first run settles, and it is expected to need a
correction before the job gets as far as the SDL include.

### Step 1 — `"SDL.h"` everywhere

Five includes plus the `extconf.rb` probe. Linux must stay green — that is the
only assertion available here.

### Step 2 — GL linking per platform

`extconf.rb`, per A2. Windows should now build and Ubuntu must not regress;
macOS may still need iteration on the framework probe.

**Done means `ported: true` for macOS in the CI matrix**, in the same commit.
Leaving it false keeps a working platform non-blocking, which is how a platform
silently rots back out; see the flag's comment in the workflow.

### Step 3 — Makefile

`DLEXT` and the GL/audio branch, per A3. This is what lets somebody develop *on*
a Mac rather than only install there. Lower priority than 1–2 if nobody is
doing that yet.

**Done means `ported: true` for Windows**, on the same terms as step 2 —
Windows needs this step as well as 1–2 before `make ext` works there at all.

### Step 4 — dlopen names in the spec support

`rendered_frame.rb` and `virtual_gamepad.rb`, per B1. Small, and unblocks
reading what the Core suite is actually doing on the other two platforms.

### Step 5 — read pixels before the swap

Per B2. Do this *before* interpreting any macOS/Windows pixel-spec failure, so a
harness assumption cannot be mistaken for a renderer bug.

### Step 6 — Windows key injection (optional)

`SendInput` via Fiddle, per B3. macOS CGEvent is deliberately **not** scheduled:
it cannot run on CI and would be exercised only by a human at a desk.

### Step 7 — the packaging decision (see C1)

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
