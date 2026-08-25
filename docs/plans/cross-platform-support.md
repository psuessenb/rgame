# Cross-platform support — macOS and Windows

**Status: green on both dev machines. Two macOS bugs found and fixed on a real
Mac; one of them (B9's macOS twin) is unverified on the configuration that
actually fails.** `rake` passes end to end on this session's Mac — 325 C
checks, 905 headless examples, 350 Core examples, `rake` exiting 0 — and did
the same earlier on the Windows machine. Written 2026-08-21 from a read of the
build wiring, the engine C, and the spec scaffolding; revised after each CI run,
then from a real Windows machine, and now from a real Mac. Anything marked
*(sketch)* was never executed; anything marked *(measured)* came off a real
runner or a real machine.

**Read this before trusting a green macOS job: the macOS leg was never
passing on CI, and the job said it was.** While a platform is `ported: false`,
`continue-on-error` forces both the job's and every step's *conclusion* to
success, so `gh run view` reports `macos … success` for a run whose `make test`
reported 19 segfaults and whose `rake spec:core` collected 0 examples. This is
the same masking mechanism B10 documents, seen from the other side, and it is
why "the Mac step passes now" was believed for a while. The real outcomes live
in `steps.<id>.outcome`, not in any conclusion — and the tell is visible
without digging: the *backtrace* step's `if:` fires only on
`c_tests.outcome == 'failure'`, so a backtrace step that **ran** rather than
being skipped is proof the tests failed, whatever the job badge says. See
B12.

**2026-08-25: three sessions on an actual Windows machine.** The first
installed the toolchain and ran the build once to establish a baseline (see
"Windows setup" for what differed from the untested instructions). The second
— same day — worked the open items to a green `rake`. The third got a working
AddressSanitizer build going (`clang64`, not `ucrt64`'s `gcc`) specifically to
chase down B7, and it paid off completely: B7 turned out to be a real,
fully-diagnosed bug (a `ck_assert` failure skipping an audio engine's cleanup
and leaking its device thread — see B7's section) rather than a mystery that
merely stopped reproducing. Landed: A4 (the `Color` `NUM2ULONG` bug), A5 (a
new finding: `SpatialHash`'s cell-key packing overflows Windows' Fixnum range
and allocates on every query), A6 (a new finding: the same LLP64 `long`-is-32-
bits fact, this time in the engine's own `clip.c`, found by the same ASan run
that closed out B7), B1 (dlopen sonames), B2 (read pixels via a new
`frame_end` hook instead of relying on swap semantics — fixed 56 of 58
`spec:core` failures in one change), B4 (the vorbis fixture's `/tmp` — the
actual fix for B7, now proven rather than merely correlated), B7 itself, and a
new B8 (`File.expand_path` resolving a leading `/` against the current drive,
which broke `AssetManager`'s path specs). The Verdict below is amended for A5.

**2026-08-25, first session on an actual Mac.** The toolchain was almost
entirely already present (see "macOS setup" for the two corrections the
untested instructions needed); `make test`, `make`, `make ext`, `rake spec` and
`rake spec:core` were all run, and the manual tier was driven rather than just
booted. Result: **all four tiers green locally, and two real macOS bugs found**
— B1's macOS half (a by-name `dlopen` that cannot work on macOS, which was
blocking *every* `spec:core` example on the macOS runner) and B9's macOS twin
(19 audio segfaults on a device-less runner). Landed alongside them: a wrong
backend spelling in `audio_spec.rb` (B13), a macOS-only packaging leak that
`packaging_spec.rb` could not see (B11), the CI masking write-up (B12), and a
measured diagnostic hole in the macOS backtrace step (B12 too). C2 (retina) was
looked at directly and stays out of scope: the window renders correctly.

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

**Amended 2026-08-25**: one exception found by actually building on Windows —
`RGame::Util::Color.from_packed` is not portable, because it assumes `unsigned
long` is 64 bits. See A4. Small, and the only counterexample found so far, but
the verdict above is about the engine's *C*, and this is Util's, so it is a
real crack in "already portable" rather than build wiring.

That was not the expected answer. The risk going in was that the renderer would
need a modern-GL port before Windows could work at all, because Windows'
`opengl32.dll` exports only OpenGL 1.1 and everything after that needs a loader
(GLAD/GLEW). Measured rather than assumed, that risk is absent — see below.

So the work splits cleanly:

| | Scope | Where it stands *(measured)* |
|---|---|---|
| **A. Build wiring** | 6 items, small, mechanical | **all landed on Windows and macOS.** A3's darwin branch links `-framework OpenGL` and lands `.bundle`, both confirmed on a real Mac |
| **B. Test scaffolding** | 13 items | **all landed on Windows.** macOS: all landed except the macOS half of B3, which is deliberately dropped |
| **C. Deliberate decisions** | 4 open questions | not blocking. C2 now *looked at* on a real Mac and still deferred |

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

### A4. `unsigned long` is 32 bits on Windows — a real bug, not a build issue *(measured, new)*

Found by `bundle exec rake spec` on Windows, not predicted anywhere above.
[`ext/rgame_util/color_ext.c:68`](../../ext/rgame_util/color_ext.c) —

```c
static VALUE color_s_from_packed(VALUE klass, VALUE packed) {
    unsigned long value = NUM2ULONG(packed);
    if (value > 0xFFFFFFFFul) {
        rb_raise(rb_eArgError, "packed colour must fit in 32 bits");
    }
    return color_wrap(klass, (rgame_color)value);
}
```

reads as platform-neutral and is not: it relies on `unsigned long` being wide
enough to hold a value one bit past 32 bits so the explicit check can catch it.
That holds on Linux and macOS (LP64: `long` is 64 bits) and fails on Windows
(LLP64: `long` stays 32 bits even in a 64-bit build). So on Windows,
`NUM2ULONG(0x1_0000_0000)` itself raises — `RangeError`, from inside the Ruby/C
boundary — and the function's own `ArgumentError` is never reached.
`spec/rgame/util/color_spec.rb:35` ("rejects a packed value wider than 32
bits") is what caught it: 904 examples run, this was one of 3 failures. The
other two turned out to be A5, not a matcher or Ruby-build quirk — see below.

**Landed.** Pull the value with `NUM2ULL` (unsigned long long, 64 bits on
every platform this project builds for) instead of `NUM2ULONG`, do the
`> 0xFFFFFFFF` check against that, and only narrow to `rgame_color` after the
check passes. `spec/rgame/util/color_spec.rb` is green on both platforms.

### A5. `SpatialHash`'s cell keys overflow Windows' Fixnum range and allocate *(measured, new)*

Not predicted anywhere above — found by two `allocate_nothing` failures in the
same `rake spec` run that found A4, on components that have nothing to do with
audio or Color: `CollisionWorld#nearest` and `Targeting#target` both "allocated
32000 objects over 1000 calls" on Windows where Linux allocates zero.

The cause is the same shape as A4 — a C-integer-width assumption that only
Linux/macOS's LP64 model satisfies — but one level removed: this time it is
**CRuby's own Fixnum tagging**, not this project's code, that assumes it.
CRuby represents a small integer as an immediate value with no heap allocation
(a "Fixnum") up to a magnitude that comes from the C `long` the interpreter
itself was built with. LP64 Ruby gets roughly 62 bits of range; **Windows'
LLP64 Ruby gets roughly 30**, confirmed by measuring the allocation cost of
`3 + (1 << n)` for increasing `n` on this build: zero allocations through
`n = 29`, one full heap allocation per call from `n = 30` on. Nothing prints
this number — it has to be measured per build, and it is dramatically smaller
than the Linux figure everyone's mental model is calibrated on.

[`lib/rgame/engine/spatial_hash.rb`](../../lib/rgame/engine/spatial_hash.rb)
packed a cell's `(col, row)` into one key as `(col + OFFSET) * STRIDE + (row +
OFFSET)` with `OFFSET = 1 << 20` and `STRIDE = 1 << 21` — comfortably inside
Linux's ~2^62 ceiling (keys ran up to ~2^42), miles outside Windows' ~2^30 one.
Every key became a heap-allocated Bignum instead of an immediate value, once
per cell per query — silently, since `Integer#class` reports `Integer` either
way in modern Ruby and cannot be used to tell an Bignum from a Fixnum from pure
Ruby. Finding it took an allocation trace (`ObjectSpace.each_object` before and
after one call, diffed) — see the failing spec's stack for the method, but the
*mechanism* is invisible without instrumenting the allocator directly.

**Landed.** `OFFSET` and `STRIDE` are now `1 << 13` and `1 << 14`, keeping the
largest possible packed key under 2^28 — comfortable margin below Windows'
ceiling — while still supporting cell coordinates out to +/-8192 (a multi-
million-pixel world at any sane `cell_size`). The comment at the constants
spells out the mechanism, since "why is this smaller than it needs to be on
Linux" is exactly the question the next platform surprise will provoke.

**This is worth generalising as a warning, not just a fix in one file.** Any
future code that packs several small integers into one Ruby integer for a
Hash/Set key — the same trick this file used — inherits the same ~2^30 ceiling
on Windows no matter how generous it looks on the machine writing it. There is
no compiler flag or `RbConfig` check that surfaces this; it has to be
remembered, or measured again the way this was.

### A6. `long` is 32 bits on Windows in the C engine too, not just in Ruby *(measured, new)*

The third instance of the same LLP64 fact biting a third layer — A4 hit Ruby's
C API, A5 hit CRuby's Fixnum tagging, this one hits
[`ext/rgame_core/graphics/clip.c`](../../ext/rgame_core/graphics/clip.c)
directly, and was only found because getting a real AddressSanitizer/UBSan
build working (see B7) meant running the *whole* Check suite under UBSan on
Windows for the first time.

`rgame_rect_intersect` computes an edge sum in `long` specifically to survive
a caller passing a very large width — its own comment says so: `int` would
overflow, which is undefined behaviour, and the `long` intermediate was meant
to give headroom before narrowing back to `int` for the result. That reasoning
holds on Linux/macOS (`long` is 64 bits there) and silently does not hold on
Windows, where `long` is 32 bits — the same width as the `int` it was meant to
be wider than. The overflow the comment describes is real UB there too;
nothing before this session's UBSan run had ever compiled this function with
UBSan *and* a 32-bit `long` at the same time, so it went uncaught.

**Landed.** `long` → `int64_t` (`<stdint.h>`, genuinely 64 bits on every
platform this project builds for, unlike `long`). Verified: `make test` under
`clang64` with `-fsanitize=address,undefined` is clean through the full 325
Check assertions, where before the fix it aborted immediately in the `clip`
suite with `runtime error: signed integer overflow: 2147483637 + 100 cannot be
represented in type 'long'`.

**The pattern to watch for, stated plainly:** any C code in this project that
reaches for `long` as "a type wider than `int`" is reaching for a type that,
on Windows, is not wider than `int`. `int64_t`/`int32_t` say what they mean on
every platform; `long`/`int` do not. A4, A5 and A6 are the same lesson at three
different layers (Ruby C API, CRuby internals, this project's own C) and it is
worth grepping for `\blong\b` outside `vendor/` the next time this file is
picked up, rather than waiting for a fourth instance to surface one file at a
time.

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

**`rendered_frame.rb` and `virtual_gamepad.rb` landed** (both now branch on
`RbConfig::CONFIG['host_os']`); `x_keys.rb` is unstarted — its fix is B3's, not
this item's, because it needs a whole new backend rather than a different
string. Verified on Windows: `bundle exec rake spec:core` opens 350 real-window
examples using both files with no dlopen failures.

**The macOS half of that was wrong, and it was the single thing stopping the
macOS leg from running any Core spec at all** *(measured 2026-08-25)*. The
table above proposed `libSDL2-2.0.0.dylib` for macOS, which is the correct
*filename* — Homebrew installs exactly that — and still cannot be opened by
name:

```
Fiddle::DLError: dlopen(libSDL2-2.0.0.dylib, 0x0009): tried:
  'libSDL2-2.0.0.dylib' (no such file),
  '/System/Volumes/Preboot/Cryptexes/OSlibSDL2-2.0.0.dylib' (no such file),
  '/usr/lib/libSDL2-2.0.0.dylib' (no such file, not in dyld cache)
```

**macOS has no `ldconfig`.** Linux resolves a bare soname through a
system-wide cache that Debian's SDL2 package registers itself in; dyld has
nothing equivalent, so a bare name is looked for only in `/usr/lib` and the
dyld shared cache. Homebrew's prefix is in neither — and it is not even a
fixed string to hardcode, being `/opt/homebrew` on Apple Silicon and
`/usr/local` on Intel. This raised at *class-definition* time in
`virtual_gamepad.rb`, so it took out `core_spec_helper.rb` itself: the macOS
runner reported `0 examples, 0 failures, 1 error occurred outside of examples`,
which is why no macOS pixel or audio spec has ever actually run.

**Landed, and the fix is better than a filename.** macOS now uses
`Fiddle::Handle::DEFAULT`, which searches the images already loaded into the
process. That is a *stronger* guarantee than any name, and it is precisely
what this file's own comment always asked for ("deliberately opens the same
libSDL2 the extension already loaded"): the extension links SDL2, so the only
copy `DEFAULT` can resolve is the one the engine is already driving. There is
no prefix to guess and no second copy to open by construction. Confirmed by
dyld introspection that the resolved image is
`/opt/homebrew/Cellar/sdl2-compat/…/libSDL2-2.0.0.dylib`, the same one
`otool -L` shows the binary linking.

Linux and Windows keep by-name `dlopen`, deliberately: both are measured
working, and B9's lesson is that a platform-specific fix should change only
that platform. The one thing the macOS arm adds is an ordering requirement —
the extension must be loaded first — which `core_spec_helper.rb` already
satisfies (it requires `rgame/core` at line 26, support files at line 28) and
which fails loudly with an unknown-symbol `DLError` if that ever changes,
rather than quietly opening a second SDL.

`rendered_frame.rb` needed no change: its macOS arm is an absolute framework
path (`/System/Library/Frameworks/OpenGL.framework/OpenGL`), which exists and
which dyld resolves for the same reason the bare name fails — it is absolute.

**Homebrew's `sdl2` is now `sdl2-compat`, and it works.** Worth recording
because it changes what the whole plan has been reasoning about: `brew install
sdl2` installs the `sdl2-compat` formula, which is the SDL2 API reimplemented
on top of SDL3, and CI's macOS step therefore gets it too — so this session's
local runs are representative rather than a lucky configuration. Everything
passes through it, `SDL_JoystickAttachVirtual` included, so the virtual-gamepad
specs exercise the real SDL path on a shim. Nothing in the engine had to
change for that.

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

**Landed, and measured to matter: this was the single highest-impact fix in
the whole port.** Windows' real driver does *not* preserve the back buffer the
way llvmpipe does — confirmed by running `rake spec:core` before this fix: 58
of 350 examples failed, overwhelmingly with a captured frame reading back as
solid black (the *next* frame's clear colour) instead of what had actually
been drawn.

The durable fix needed a seam that did not exist: `App` had `frame_begin`
(before a frame's ticks) and `draw` (queues drawing, does not submit it) but
nothing between the queue being submitted to GL and the buffer swap — the one
point a driver is guaranteed to still be showing this frame's image. Added as
a new optional callback, `frame_end`, symmetric with `frame_begin`: threaded
through [`core.h`](../../ext/rgame_core/include/rgame/core.h) (a new
`rgame_frame_end_fn` in `rgame_app_callbacks`), called in
[`app.c`](../../ext/rgame_core/app/app.c) between `rgame_canvas_submit` and
`SDL_GL_SwapWindow`, and exposed on `RGame::Core::App` the same way every other
hook is (trampoline, default no-op, `rb_define_method`) in
[`core_ext.c`](../../ext/rgame_core/ruby/core_ext.c). `rendered_frame.rb` then
needs only one frame instead of two: `draw` queues the caller's block,
`frame_end` grabs the pixels and closes. Documented on `App` as "rarely needed
outside a test that reads pixels" — it is real public API surface, not a
test-only backdoor, but a game has no reason to reach for it.

Fixed 56 of the 58 failing examples in one change. The remaining 2
([`tile_map_renderer_spec.rb`](../../spec_core/rgame/core/tile_map_renderer_spec.rb))
were a second, smaller, unrelated finding: they compared a background pixel
with strict `eq` instead of the tolerant `about?` every other pixel spec in the
suite uses, and this GPU's rasteriser rounds the same clear colour to `[25, 25,
38]` where llvmpipe gives `[26, 26, 38]` — one unit off, and exactly what
`about?`'s documented tolerance exists for. Switched both to `about?`,
matching the established convention; `rake spec:core` is now 350 examples, 0
failures.

**A third driver, same lesson, found by CI itself.** The first real Windows
CI run past B9 turned up two more: `nine_slice_spec.rb`'s corner check and
`tile_map_renderer_spec.rb`'s *third* pixel test — `"draws at the world
origin..."` — which this session's own dev machine had left on strict `eq`
because it happened to render exactly `[255, 255, 255, 255]` here. CI's
runner (a different GPU/driver again — its own software or virtual
rasteriser, distinct from both llvmpipe and this dev machine's real one)
rounds the same white to `[252, 252, 252, 255]`. Switched to `about?`, same
treatment as before, and confirmed fixed on the next CI run.

**The pattern by now is not "the Windows port has a rendering bug" — it is
that llvmpipe (Linux CI), this dev machine's GPU, and the Windows CI runner's
own driver are three separate rasterisers that each round the same
arithmetic slightly differently**, and a pixel spec that hardcodes an exact
value is really only ever tested against whichever one machine wrote it.
`about?`'s tolerance exists for exactly this and should be the default for
any *new* pixel assertion in `spec_core` — a strict `eq` on a rendered pixel
should be treated as needing a specific reason, not the default.

**NineSlice's failure is not that pattern, and the first attempt to fix it
was wrong to assume it was.** `about?` already returns a bare boolean, so the
first CI report carried no information about what was actually sampled —
fixed by adding a small `expect_pixel` helper, local to that one spec, that
reports the actual pixel via `frame.at` on failure rather than a bare `false`.
The *next* CI run then reported it: the top-left corner came back
`[252, 252, 252, 255]` — near-white, and white is not a colour anywhere in
this test's 3x3 source fixture (red corners, green edges, blue centre; see
the fixture right above this test). That rules out driver rounding — nothing
rounds red into white — and matches instead the specific, already-documented
failure mode in
[`image_internal.h`](../../ext/rgame_core/graphics/image_internal.h) and
[`docs/api/drawing.md`](../../docs/api/drawing.md): drawing an image with no
texture actually bound reads as a plain white quad. What's still unknown is
*how much* of the panel is affected — a plain sequence of `expect`s stops at
the first failure, so whether the other four sample points are also white
(the whole texture never bound) or fine (something narrower, specific to this
one corner) has not been observed yet. Tagged the example
`:aggregate_failures` (built into RSpec, no extra config) so the next run
reports all five together — confirmed locally that the mechanism actually
reports multiple failures in one run rather than still stopping at the first,
by temporarily forcing two of the five to fail and checking both showed up.
Not a fix; the next CI run is what turns this from "know the symptom" into
"know the shape of the bug."

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

**The skip count, measured on macOS 2026-08-25, is 2.** `spec:core` reports
`350 examples, 0 failures` there against 352 on Linux; the two held back are
`input_spec.rb`'s "reports a held key while it is down and not after" and "does
not let a gamepad device answer for a keyboard key", both under the single
`:needs_key_injection` describe block. So the honest phrasing for a macOS run is
**350 of 352** — small enough that the macOS CGEvent backend stays the lowest-
value item in section B, and it does not touch the gamepad path, which is
covered on every platform through SDL's virtual joystick (B1).

### B4. `test_vorbis_decoder.c` hardcodes `/tmp` and `mkstemp`

[`test/test_vorbis_decoder.c`](../../test/test_vorbis_decoder.c) writes its
malformed-input fixtures through `mkstemp("/tmp/rgame_vorbis_testXXXXXX")`.
Fine on macOS; on Windows it needs `GetTempPath`/`tmpnam_s`. The file already
carries a comment explaining the `-std=c17`/POSIX feature-macro dance, so the
reasoning for whatever replaces it belongs in the same place.

**Landed — and `mkstemp` itself needed no replacement.** Measured: mingw-w64's
UCRT does provide a working `mkstemp`, so the only real problem was the
hardcoded `/tmp` — `C:\tmp` does not exist on a default Windows install, so
every `scratch_file` call was failing `ck_assert_int_ge(fd, 0)` (confirmed by
checking for the directory directly). The fix is `scratch_dir()`, which reads
`TMPDIR`/`TEMP`/`TMP` in that order and falls back to `/tmp`, plus a wider
stack buffer (some real Windows `TEMP` paths run past the old fixed 29-byte
one) built with `snprintf` instead of a literal `strcpy`. Verified: `vorbis_decoder`
suite alone, 14/14, repeatedly. See B7 for why this fix's side effects turned
out to matter beyond its own suite.

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

### B7. A failed assertion before an audio engine's cleanup leaks its device thread *(measured, resolved)*

**Filed as "opening a real audio device crashes on macOS and Windows"; that
title turned out to be wrong — see below for the real mechanism, found on
Windows via AddressSanitizer. Kept unedited above this point as the accurate
history of how it was chased down; skip to "Confirmed, not just believed"
partway through for the actual root cause.**

This was not predicted anywhere in the sketch — which had audio down as the one subsystem
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

**2026-08-25, first Windows session — neither hypothesis fits.** This machine
has actual audio hardware, which is exactly the condition hypothesis 2 says
should make the suite pass. It does not, cleanly:

- `CK_FORK=no CK_RUN_SUITE=audio gdb --batch -ex run -ex "bt full" -- ./build/test_rgame`
  — the audio suite run **by itself** passes clean: `26/26`, no crash, real
  device opened and closed 26 times over.
- `CK_FORK=no gdb --batch -ex run -- ./build/test_rgame` — the **full** suite,
  same binary, same machine, crashes reproducibly (twice, same signature) part
  way into the audio suite, after `vorbis_decoder`. The crash is inside
  `ntdll!RtlValidateHeap`, reached through `RtlRaiseException` /
  `RtlCaptureContext` — the signature of Windows detecting heap corruption at
  the *next* allocation after the actual damage, not a null-pointer/access
  violation at the point of the original bug. It happens on the audio suite's
  second device-open, not its first.

That rules out "no device" (hypothesis 2) outright — there is one, and audio
alone is fine — and doesn't obviously fit hypothesis 1 either (runtime-linked
CoreAudio is macOS-specific; Windows' equivalent would be WASAPI symbol
resolution, and a missing-symbol failure doesn't produce a *delayed* heap
corruption two tests later).

**2026-08-25, second Windows session — misdiagnosed from the start: this was
never about a real device at all.** Everything above, including this plan's
own framing ("Opening a *real* audio device crashes"), assumed the crash was
in `rgame_audio_create`/WASAPI because the backtrace's leaf frame —
`ma_device_audio_thread__default_read_write` — is the function name every real
backend's device thread runs. It is *also* the function the **null** backend's
device thread runs, because miniaudio's default engine is shared across every
non-asynchronous backend, WASAPI and null alike. Nothing in the earlier
sessions actually distinguished the two.

A `gdb` breakpoint on `rgame_audio_create` — our own wrapper, the only place
in the whole codebase that opens a *real* device — settles it: **zero hits**,
on a run that crashes with the identical signature every time. Confirmed
against a control case first (the same breakpoint, same binary, run against
just the audio suite where it is known to pass, fires 43 times as expected —
so the breakpoint mechanism itself is not the problem). Grepping the whole
`test/` tree for `ma_engine_init`/`ma_context_init` turns up exactly two call
sites outside `audio.c`, both in
[`test/test_vorbis_decoder.c`](../../test/test_vorbis_decoder.c):
`the_engine_can_read_an_ogg_too` and `the_engine_refuses_a_file_that_is_not_an_ogg`,
both explicitly `{ ma_backend_null }`. **The crash is in `vorbis_decoder`, not
`audio` — the buffered "Running suite(s)" list cutting off after
`vorbis_decoder` was never a coincidence, it was accurate the whole time**, and
every hypothesis above (WASAPI symbol resolution, no sound card) was answering
a question this bug does not ask.

That does not fully localise it either. Looping
`the_engine_can_read_an_ogg_too`'s entire body 20 times in one process (a
temporary edit, reverted) never crashes on its own; running just that one test
15/15 times never crashes. The corruption needs heap activity from *other*
suites first to become visible — consistent with genuine memory corruption
whose damage is silent until something else's allocation trips over it, which
is the least tractable kind to pin down by bisection alone.

**It also behaves like a heisenbug, twice over, which is itself evidence.**
Two unrelated changes made it stop reproducing:

1. Adding `fprintf(stderr, ...); fflush(stderr);` diagnostic prints to
   `create_audio`/`rgame_audio_destroy` — which, note, is code that gdb had
   just proven never runs before this crash — dropped a scenario that crashed
   2 of 3 times down to 4 of 4 clean runs. Removing the prints (confirmed via
   `git diff` showing zero change to `audio.c`) brought the crashes back.
2. B4's fix (below) — a larger stack buffer and an `snprintf` call added to
   `test_vorbis_decoder.c`, the exact file the crash is now known to be in —
   took the **full** suite from a deterministic 100% crash rate (5/5 runs
   before) to 100% clean (14/14 runs after, across both explicit `CK_FORK=no`
   and the plain documented `make test`).

Neither change touches the code path gdb proved is responsible in any way that
should matter to *correctness* — a diagnostic `fprintf` and a bigger unrelated
buffer do not fix a logic bug. Both changes alter heap layout and timing.
That a heap-layout change silences a crash whose own signature
(`RtlValidateHeap` firing on a *later*, unrelated allocation) already pointed
to corruption is close to a second confirmation, not a coincidence — and it is
exactly what turned out to be true, once a real sanitizer could actually run.

**Confirmed, not just believed: getting AddressSanitizer working proved the
exact mechanism.** GCC's `ucrt64` package ships no sanitizer runtime at all
(`ld: cannot find -lasan`/`-lubsan`; `pacman -Ss asan` finds nothing), but
MSYS2's separate `clang64` environment does —
`mingw-w64-clang-x86_64-clang` plus `mingw-w64-clang-x86_64-compiler-rt`, built
and installed the same way as `ucrt64`'s packages. Building the whole Check
suite there with `-fsanitize=address,undefined -fno-sanitize-recover=all`
against the code *as committed* (B4's fix included) passed clean — 325/325,
audio suite included, six consecutive runs. Reverting only B4's fix (`git show
<parent>:test/test_vorbis_decoder.c`, rebuilt under the same ASan binary,
restored afterward) reproduced the crash immediately and, this time, with a
real address and a real report:

```
==ERROR: AddressSanitizer: stack-buffer-overflow ... READ of size 4 ... thread T6
    #0 ma_node_get_output_bus_count            miniaudio.h:74755
    ... (the mixer graph, reached from the device's own audio thread) ...
    #9 ma_device_audio_thread__default_read_write miniaudio.h:20902

Address ... is located in stack of thread T0 at offset 892 in frame
    #0 opening_and_closing_repeatedly_leaks_nothing_fn  test_vorbis_decoder.c:393
...
Thread T6 created by T0 here:
    ...
    #4 ma_engine_init         miniaudio.h:77597
    #5 the_engine_refuses_a_file_that_is_not_an_ogg_fn  test_vorbis_decoder.c:296
```

Read backwards, that is the whole bug. `the_engine_refuses_a_file_that_is_not_an_ogg`
opens an engine (`ma_engine_init`), which spins up a real background device
thread (T6) — then, *before* its own `ma_engine_uninit`/cleanup at the bottom
of the function, calls `scratch_file()`, whose `mkstemp("/tmp/...")` fails on
Windows because `/tmp` does not exist there (B4's actual finding). That
failure trips `ck_assert_int_ge(fd, 0)`, and **a failed `ck_assert` does a
non-local jump out of the test function** — Check's whole mechanism for
"a failed assertion ends this test, not the process." The jump skips every
line after it, cleanup included. `ma_engine_uninit` never runs. Thread T6,
still fully alive, keeps mixing through an `engine`/mixer graph that lives on
a stack frame which — as far as the C call stack is concerned — no longer
exists. Once *any* later test's stack frame reuses that same memory (ordinary,
expected behaviour — nothing wrong with it in isolation), the zombie thread's
next mix pass reads through what is now someone else's local variables. Which
test's frame it happens to land on, and whether that read merely gets garbage
or corrupts something Windows' heap validator later trips over, is exactly as
unpredictable as the heisenbug behaviour above — because it *is* that
mechanism: a genuinely dangling background thread, not a fixed memory address,
racing against whatever the main thread does next.

That also explains every earlier observation cleanly:

- Why `rgame_audio_create`/`audio.c` were never in the backtrace: they were
  never the code that leaked the thread. The two `test_vorbis_decoder.c`
  functions that build a `ma_engine` directly (`the_engine_can_read_an_ogg_too`
  and `the_engine_refuses_a_file_that_is_not_an_ogg`) were always the whole
  story, and only the second one actually calls `scratch_file` before its own
  cleanup — the first one doesn't, so it was never the source, just
  collateral evidence pointing at the right file.
- Why 20 loops of `the_engine_can_read_an_ogg_too` alone never crashed: it
  never leaks its thread, because it has no failing assertion before its own
  `ma_engine_uninit`.
- Why B4 fixed it: B4 makes `mkstemp` succeed (a real `TEMP` directory instead
  of a nonexistent `/tmp`), so the assertion that was jumping past cleanup
  simply stops firing. Nothing about B4's buffer size or `snprintf` call was
  ever the mechanism — that was this session's own mistaken inference from
  watching a heisenbug's reproduction rate change. The real fix was always "make
  the assertion pass," which B4 did as a side effect of fixing what it actually
  set out to fix.
- Why it needed heap noise from other suites to manifest under plain `gcc`,
  and why ASan needed no such noise at all: ASan poisons the exact stack
  region on every function's exit specifically to catch a *later* access to it,
  so it does not need another test's frame to happen to collide — it catches
  the read immediately, against its own redzone, the first time the zombie
  thread's next mix pass fires. That is also why this is squarely a stack bug,
  not a heap bug, despite `RtlValidateHeap` being the symptom every earlier
  plain build showed: the corrupted memory *is* stack, but Windows' heap
  validator is what happened to notice something was wrong, on a machine with
  no ASan to notice it more precisely.

**Landed — via B4, and this time for a fully understood reason rather than an
observed correlation.** No new code change was needed beyond B4 itself; this
account replaces "believed fixed" with "fixed, and here is why." The general
hazard is worth stating for whoever writes the next test that opens a real
`ma_engine`/`ma_device` directly (bypassing `audio.c`'s own `rgame_audio_create`/
`rgame_audio_destroy`, which do not have this problem because nothing between
their open and close can `ck_assert`): **any `ck_assert_*` between opening a
device and tearing it down leaks that device's thread if it fails, on any
platform, silently, until something else's memory happens to collide with it.**
`test_vorbis_decoder.c`'s two engine tests still have this shape — no assertion
between their `ma_engine_init` and their `ma_engine_uninit` is expected to fail
in ordinary operation any more (B4 removed the one that could), so they are not
currently a live hazard, but a `tcase` teardown fixture (which Check guarantees
runs even after a failed assertion) would close the hazard structurally rather
than by removing today's only trigger. Not done here — recorded as the
principled follow-up rather than added speculatively.

Whether macOS's crash is the same root cause is now answerable in principle —
macOS's `/tmp` exists, so this exact trigger (a failed `mkstemp` assertion)
would not fire there, meaning macOS's crash, if it reproduces at all once the
macOS leg is picked up again, needs its own explanation.

**Answered 2026-08-25, and it is a different bug: see B9a.** macOS's 19
segfaults are the zero-device crash B9 found on Windows, not this leaked-thread
bug — the reasoning above was right that `/tmp` existing rules this trigger
out there. What did transfer is the general hazard stated below, and the habit
of not trusting a leaf frame: B7's own misdiagnosis came from reading
`ma_device_audio_thread__default_read_write` as proof of a real device, and
B9a's `CK_FORK=no` pass is the same shape of trap one level up. What transfers
directly is the general hazard above, and the diagnostic path that found it:
`ck_assert` failures before a real device's teardown are worth auditing
anywhere a `ma_engine`/`ma_device` is opened directly in a test, and a
`clang`+ASan build (macOS's `clang` already ships a working ASan/UBSan, no
separate toolchain needed there) is the fastest way to confirm or rule it out.

### B8. `File.expand_path` resolves a leading `/` against the current drive on Windows *(measured, new)*

Found alongside A4/A5 by the same `rake spec:core` run, in
[`spec_core/rgame/core/asset_manager_spec.rb`](../../spec_core/rgame/core/asset_manager_spec.rb) —
8 of that run's failures, none in `AssetManager` itself.

`AssetManager#resolve` is `File.expand_path(path, @root)`, and its own comment
already explains why: an **absolute** path is used as it stands, so a loader
handing one back (a tileset image found from a `.tsx` already on disk) does
not get `<root>/<root>/tiles.png`. The spec fixtures took "absolute path" at
face value and hardcoded literal strings like `/media/sprites/hero.png` as
both inputs and expected outputs — which is exactly what breaks, because
"absolute" is not one concept across platforms. POSIX has a drive-independent
root; Windows does not, so `File.expand_path('/media/x')` resolves against
the *current drive*, giving `C:/media/x` rather than `/media/x`. This is
correct, intentional Ruby behaviour on Windows, not a bug to work around — the
one-argument form of `File.expand_path` cannot mean anything else there.

The spec was asserting against a Linux-only reading of its own fixture, not
against `AssetManager`'s actual contract. Every hardcoded expectation and every
descriptor-hash key built from a bare `/...` literal now goes through
`File.expand_path(...)` itself — the same call `resolve` makes — rather than a
written-out string, so the assertion is "the caller received what `resolve`
was always going to produce here," which holds on every platform including the
one it was written on. **Landed**; `asset_manager_spec.rb` is 30/30 on
Windows.

### B9. A machine with zero audio devices crashes opening one on Windows — CI, not this session's dev machine *(measured, new)*

Found by the first real Windows CI run, after Windows flipped to `ported:
true`: `rake spec:core` died with no RSpec summary at all — no `Failures:`,
no `Finished in`, just the last example name printed
(`spec_core/rgame/core/asset_manager_spec.rb`'s "loads an image into the app
that owns it") and `Process completed with exit code 1`. That signature —
silence, not a reported failure — means the `ruby.exe` process itself died,
not an assertion. The next example in file order is "loads a sound through
the app device", the first thing in the whole `spec_core` run that opens a
*real* audio device via `RGame::Core::App#audio` → `rgame_audio_create`.

This is hypothesis 2 from B7's original investigation, and it was never
actually tested there — this session's dev machine has a real sound card, so
every local run exercised the "device present" path. GitHub's Windows
runners have none at all (confirmed:
[actions/runner-images#6983](https://github.com/actions/runner-images/issues/6983),
`Get-CimInstance Win32_SoundDevice` returns nothing), which is a different
case from "the default device is temporarily unavailable" — several
`mackron/miniaudio` issues describe WASAPI mishandling missing-endpoint cases
around `ma_engine_init`/device open. `create_audio`'s own comment claimed the
no-explicit-backend-list path "falls back to a null device when none of them
can open," and that was true and verified — on Linux, where the fallback is a
graceful failure return the auto-detect loop can act on. On Windows, WASAPI's
attempt to open a device that isn't there apparently doesn't fail gracefully
enough for that loop to ever reach Null.

**Landed, unverified on the actual failing configuration** — there is no
device-less Windows machine available to reproduce this on directly, so this
is a reasoned fix rather than a measured one, the first item in this document
that is. `ext/rgame_core/audio/audio.c`'s `create_audio` now enumerates
devices itself first (`ma_context_init(NULL, 0, ...)` then
`ma_context_get_devices`, both read-only — enumerating is not the same
operation as opening, and is not implicated in any of the crash reports
found) and explicitly builds a `{ ma_backend_null }`-only context when the
playback count comes back zero, rather than ever handing `ma_engine_init` an
auto-detect list that might attempt — and crash on — a real device with
nothing behind it. Verified on this machine (a real device, so the
device-present branch runs unchanged): `rake` end to end, 325 + 904 + 350,
still 0 failures, and `#backend` still reports the real WASAPI name. What
could not be verified locally is the zero-device branch itself.

**Landed narrower than the first attempt: `#ifdef _WIN32` only.** The first
version of this fix ran the enumerate-first logic on every platform, and the
very next push broke the *Linux* leg — a leg that was already proven working,
on a code path this session has no way to test outside Windows. Rather than
guess at the Linux failure blind, the fix was scoped to exactly the evidence
that motivated it: `_WIN32` only, so Linux and macOS run the exact `ma_engine_init`
call that has been correct all along, byte-for-byte unchanged. This is worth
stating as its own lesson, not just a revert: **a fix aimed at one platform's
crash should default to changing only that platform**, even when the new
logic looks harmless enough to "obviously" generalize — it is exactly the
kind of change this session's own `windows-portability` skill exists to warn
against making blind.

**Second round: the explicit-null-backend version of this fix was itself
wrong, and B10's backtrace is what proved it.** With B10's diagnostic step
actually running, the next CI push produced a real stack: a *background*
thread (not the main thread `create_audio` runs on) crashed inside
`ma_worker_thread`/`ma_device_audio_thread__default_read_write` — the same
device-polling machinery every earlier B7 backtrace on this machine had
already shown, this time reached through the explicit Null-backend device
this fix had just added. Crucially, `make test` — the plain-C Check suite,
same code, same CI runner, no Ruby involved — passed cleanly with that exact
code. The failure is specific to that background thread existing **inside a
Ruby process**; nothing about it could be pinned down further without a
device-less Windows machine to attach a live debugger to, which nothing
available here is.

Rather than keep guessing at *why* a backend thread inside Ruby crashes,
the fix sidesteps needing to know: swap the explicit `{ ma_backend_null }`
device for `noDevice = MA_TRUE` instead — the same mode the offline
constructor already uses everywhere, proven safe precisely because it spins
up **no background thread at all**. There is nothing left to crash. The one
externally-visible difference this trades away is that `#backend` no longer
finds a `ma_device` to name — patched with a `forced_no_device` flag that
makes it answer `"Null"` directly, matching what every other no-hardware case
already reports, so `audio_spec.rb`'s existing contract
(`/\A(PulseAudio|ALSA|CoreAudio|WASAPI|Null)\z/`) needed no change. Sanity
-checked on this machine by temporarily forcing the fallback branch
unconditionally (a real device is always found here, so the real trigger
condition is still unverified) — with it forced on, all 75 `audio_spec.rb`
examples still pass, including sample/song load and playback, confirming the
`noDevice` engine remains fully usable for everything a test (or a game not
reading device output) does with it.

Also landed: a CI diagnostic this class of failure was missing entirely.
`ci.yml`'s Check-suite crash gets an automatic `gdb` backtrace; the Ruby-level
crash that motivated this item got nothing but a bare exit code, because
nothing was wired up to catch it. A new step runs `gdb --args ruby -e
"RSpec::Core::Runner.run(...)"` directly (not through `bundle exec`/`rake`,
each of which spawns a *new* Windows process rather than POSIX-`exec`ing over
the current one, which would leave the debugger attached to the wrong
process) when the Core specs step fails on Windows, so if this fix is wrong or
incomplete, the next push explains why instead of repeating the same silence.

**That diagnostic step needed a fix of its own before it could run at all —
see B10.**

Recorded as its own item and cross-referenced from
`.claude/skills/windows-portability/SKILL.md` (item 5) rather than folded into
B7, because it is a different bug with a different mechanism — B7 was a
resource leak from a skipped cleanup path; this is a real backend crashing on
its very first, ordinary attempt to open when the hardware simply isn't
there. The only thing they share is that both only reproduce on Windows and
both involve `ma_engine_init`.

### B9a. The same zero-device crash on macOS — and it needs Check's `fork` too *(measured, new)*

**This is the answer to "Run this experiment first", and to the question B7
left open.** B7 asked whether macOS's 19 audio segfaults were the same root
cause as Windows'; B9 predicted a device-less machine as the trigger but could
only test it on Windows. Both are now settled, and B9's hypothesis 2 was right
for macOS.

The experiment the plan asks for — `make test` on a Mac with a sound card —
returns **325/325, 0 errors, audio suite included**. So there is no
macOS-specific defect in opening a device. Meanwhile the macOS *runner*, which
has no sound card, reports:

```
94%: Checks: 325, Failures: 0, Errors: 19
test/test_audio.c:82:E:core:a_device_opens_even_with_no_sound_card:0: … signal 11
```

The correspondence is exact and is the same one B7 tabulated: 19 tests open a
real device and all 19 segfault; the 4 offline (`noDevice`) tests and the 3
NULL-guard tests pass. Combined with the local pass, that isolates the trigger
to *having no playback device*, which is B9 on Windows exactly.

**One new fact, and it matters for diagnosis rather than for the fix: macOS
needs Check's `fork` as well.** The CI backtrace step re-ran the identical
binary on the identical runner with `CK_FORK=no` and it passed **325/325, 0
errors** — printing no stack at all, on a push whose `make test` had just
reported 19 crashes. So the macOS crash requires *both* conditions, no device
**and** a forked child, where Windows needed only the first. That fits macOS's
documented fork rules — CoreAudio reaches `coreaudiod` over Mach IPC and uses
libdispatch, none of which is safe to use in a forked child of a process that
has already initialised them, and this binary links Cocoa through SDL2. The
runner does reach CoreAudio: its log carries CoreAudio's
`AddInstanceForFactory: No factory registered for id …` line.

Chasing that interaction is unnecessary, though, because it is downstream of a
condition the engine can simply decline to create.

**Landed: B9's fallback now covers macOS.** `create_audio`'s guard goes from
`#ifdef _WIN32` to `#if defined(_WIN32) || defined(__APPLE__)` — enumerate
playback devices first (read-only; it opens nothing) and, when the count is
zero, build the engine with `noDevice = MA_TRUE` instead of handing
`ma_engine_init` an auto-detect list that will try to open hardware that is not
there. No real device-open attempt means no CoreAudio device thread, so the
fork interaction above has nothing to act on either.

**Linux stays excluded on purpose**, and that is now written into the comment
rather than left as a date-stamped note: generalising this fix is what broke
Linux's leg once already (see B9), Linux's own null-device fallback is proven,
and the rule going forward is that a platform opts into this branch on the
strength of a measured crash.

**Verified as far as this machine allows, which is not all the way.** With a
real device present the branch is not taken and nothing changes: `make test`
325/325, `rake` green end to end. Forcing the branch unconditionally — the
same sanity check B9 used, since no device-less Mac is available here —
gives the device-less path a real workout: the **whole C suite passes
325/325 including all 19 real-device tests**, `#backend` answers `"Null"`,
and `audio_spec.rb` is green. What remains unverified is the actual trigger,
because it needs a Mac with no audio hardware. Treat this as reasoned-and-
exercised rather than measured on the failing configuration, exactly as B9
itself is.

### B10. A GitHub Actions gotcha, not a project bug — the backtrace steps silently stopped running *(measured, new)*

Found immediately after B9's fix reached CI: the "Backtrace the Core specs
crash (Windows)" step, added specifically to diagnose exactly this kind of
failure, never ran — shown as skipped in the Actions UI, no output at all.
Worse, re-reading `ci.yml` at that point found the **pre-existing** "Backtrace
the C suite crash" step had the identical bug, undetected until now because
it happened to be masked.

The mechanism is a GitHub Actions rule that is easy to not know and easy to
verify once suspected: **an `if:` condition containing no explicit
status-check function (`success()`, `failure()`, `cancelled()`, `always()`)
gets `success()` silently prepended to it.** Both backtrace steps were written
as `if: steps.<id>.outcome == 'failure'` — no status function — so both were
really `if: success() && steps.<id>.outcome == 'failure'`, which can only ever
be true if a step failed *and* every step (including that one) still counts
as an overall success. That is a contradiction the two conditions could never
jointly satisfy — the steps were dead code from the day they were written.

**Why it stayed hidden until now**: both backtrace steps sit immediately after
a step whose `continue-on-error` is `${{ !matrix.ported }}`. While a platform
is `ported: false`, a failing step's *conclusion* is forced to `success` by
`continue-on-error` (even though its `outcome` correctly stays `failure`), so
the implicit `success()` check passed — masking the bug, not fixing it — for
exactly as long as macOS and Windows stayed unported. B7 was investigated
entirely through direct terminal `gdb` runs on this session's own machine
rather than through this CI step, so the bug had no chance to surface until
Windows flipped to `ported: true` (making `continue-on-error` `false`) and a
real failure needed the step for the first time.

**Landed**: `always() &&` prepended to both conditions. `always()` runs the
step regardless of prior outcomes (short of the job being cancelled), and the
existing `steps.<id>.outcome == 'failure'` half still scopes it to exactly the
one step it means to diagnose. Unverified by construction — the whole point is
a step that only matters when something else has already gone wrong — but the
mechanism is a documented GitHub Actions rule, not a guess, and the fix was
confirmed by re-reading both conditions against it rather than by a run that
exercises the failure path.
### B11. macOS debug symbols leak into the gem, and `packaging_spec.rb` could not see it *(measured, new)*

Building the extensions on a Mac leaves a `core_ext.bundle.dSYM` **directory**
beside each one. Neither `.gitignore` nor the gemspec caught it, and the
consequence is the exact failure mode CLAUDE.md's "Packaging" section warns
about — invisible locally, wrong in the shipped gem:

```
ext/rgame_core/core_ext.bundle.dSYM/Contents/Info.plist
ext/rgame_core/core_ext.bundle.dSYM/Contents/Resources/Relocations/aarch64/core_ext.bundle.yml
ext/rgame_util/util_ext.bundle.dSYM/Contents/Info.plist
ext/rgame_util/util_ext.bundle.dSYM/Contents/Resources/Relocations/aarch64/util_ext.bundle.yml
```

The cause is that every rule in play matches a **suffix** while a `.dSYM` is a
**path component**. `*.bundle` does not match `core_ext.bundle.dSYM`, whose name
ends in `.dSYM`; the gemspec's `\.(so|bundle|dylib|o|a|log)\z` catches the debug
*copy of the binary* inside the directory (it does end in `.bundle`) and misses
its `Info.plist` and relocation `.yml` beside it. So exactly the two files that
are not obviously build output are the two that shipped.

**Why the guard stayed silent is the more interesting half, and it is a real
weakness rather than an oversight.** CLAUDE.md describes `packaging_spec.rb` as
re-deriving what must ship and asserting it against the gemspec's derivation
"in both directions", so that a disagreement names the file. That works for a
mistake in *one* derivation. Here both sides filter with their own copy of the
same regex, and the hole is in the pattern itself — so the two derivations
agreed perfectly, about the wrong answer, and the suite was green with four
debug files in `spec.files`.

**Landed, in three places, and the third is the point.** `.gitignore` gets
`*.dSYM/`; the gemspec's `artifacts` regex gets a `\.dSYM/` clause (this is the
load-bearing one — `.gitignore` has no say in what `Dir.glob` finds, and the
gemspec globs the filesystem rather than asking git); and
`spec/packaging_spec.rb` gets an example stated **without reference to the
shared `artifacts` pattern**:

```ruby
it 'excludes macOS debug symbol bundles' do
  expect(files.grep(/dSYM/)).to be_empty
end
```

Mutation-checked rather than assumed: with the gemspec clause removed the
example fails and names all four files; with it restored it passes. The general
lesson for this file is worth keeping — **an assertion that filters with the
same pattern as the code it checks cannot catch a bug in the pattern.** Where a
guard exists to say what must never ship, at least one example should name the
thing directly.

### B12. The macOS job reported success while two of its steps failed, and the backtrace step was blind to why *(measured, new)*

Two separate problems, both about *reporting* rather than the port, and both
found by going to the raw CI logs rather than the job badge.

**First: an unported leg's green is not evidence of anything.** `ported: false`
puts `continue-on-error` on the job and on every test step, and
`continue-on-error` forces a *conclusion* to success while leaving the
*outcome* as failure. `gh run view --json jobs` reports conclusions, so the
macOS job — and every one of its steps — read `success` on a run where
`make test` had 19 errors and `rake spec:core` collected `0 examples`. This is
B10's mechanism seen from the other side: there it silently disabled a step,
here it silently launders a red leg green.

Nothing needs fixing in the workflow for this — `continue-on-error` is doing
the job the plan gave it, and B10 already documents the trap — but two things
are worth knowing when reading a run:

- The outcomes are in `steps.<id>.outcome`, never in a conclusion.
- **A backtrace step that ran rather than skipped is itself the signal.** Its
  `if:` is `always() && steps.c_tests.outcome == 'failure'`, so it fires only
  when the tests really failed, whatever the badge says. That is what exposed
  this: step 10 showed `success` where steps 3, 7, 8 and 15 showed `skipped`,
  and a step that *ran* at all could only mean the C suite had failed.

**Second: the macOS backtrace step could not have diagnosed this crash, and
that is measured, not suspected.** It runs `CK_FORK=no lldb …`, on the sound
reasoning (B5, and the "Debugging a crash" section) that a debugger follows the
parent and so needs fork off. On macOS that reasoning removes the bug: the
crash needs a forked child (B9a), so the step ran the same binary on the same
runner and printed `100%: Checks: 325, Failures: 0, Errors: 0` followed by
`error: Command requires a process which is currently stopped` — a confusing
clean pass, on a push that had just failed, which is worse than no output.

**Landed:** the macOS arm keeps the `CK_FORK=no` attempt (still right for a
crash that does reproduce without fork) and then re-runs with `CK_FORK=yes` and
prints any `test_rgame` crash reports from
`~/Library/Logs/DiagnosticReports` and `/Library/Logs/DiagnosticReports`. macOS
writes a full per-process report for a forked child that dies, so for this
class of failure the report is the honest source and the debugger is not.
Unverified by construction, like B10's fix — it only runs when something else
has already broken.

### B13. `audio_spec.rb` guessed the CoreAudio backend's name *(measured, new)*

One failure out of 350 in the first full macOS `spec:core` run, and a fixture
bug rather than a port bug:

```
expected "Core Audio" to match /\A(PulseAudio|ALSA|CoreAudio|WASAPI|Null)\z/
```

The spec wrote `CoreAudio`, matching the `MA_ENABLE_COREAUDIO` feature macro.
The string is not ours to choose: it comes from `gBackendInfo` in
`ext/rgame_core/vendor/miniaudio.h`, which spells it `"Core Audio"`, with a
space — the only entry in that table whose name differs from its macro that
way. **Landed**: the regex now says `Core Audio`, and the comment names
`gBackendInfo` as the source of truth so the next platform's spelling is looked
up rather than guessed.


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

**Measured 2026-08-25 on an Apple Silicon Mac. The instructions above are
right; four details are worth adding.**

- **`xcode-select --install` is enough — full Xcode is not.** This machine has
  only the Command Line Tools (`xcode-select -p` → `/Library/Developer/CommandLineTools`)
  and every tier builds and runs. Its `make` is Apple's GNU Make **3.81**, which
  the root Makefile is fine with.
- **`brew install sdl2` installs `sdl2-compat`** — the SDL2 API on top of SDL3 —
  because that is what the `sdl2` formula now resolves to. Everything works
  through it, virtual gamepads included; see B1. Nothing to do, but it is worth
  knowing that "SDL2" on a current Mac is a shim, and that CI gets the same one.
- **`brew install pkg-config` resolves to `pkgconf`.** Still installs and still
  provides `pkg-config`, so `ci.yml`'s macOS step needs no change; noted because
  the formula rename makes it look deprecated when it is not.
- **`check` is the one thing likely to be missing**, since nothing else pulls it
  in. `pkg-config --cflags check` failing is the symptom, and it is what
  `make test` needs.
- **Any version manager works, not just mise.** `.ruby-version` says
  `ruby 4.0.5`; this machine supplies it through asdf. Nothing in the build
  cares which manager it came from.

**Two things the plan expected to be problems and which are not**, both worth
striking off rather than re-investigating:

- **A3's darwin branch is correct as landed.** `make test` links
  `-framework OpenGL`, `make ext` produces `core_ext.bundle` and
  `util_ext.bundle` and copies both into `lib/rgame/` — the `DLEXT` question in
  A3 answered on a real Mac rather than by overriding a variable.
- **`have_framework` did not misfire.** Step 2 flagged it as possibly failing on
  a Mac that can link OpenGL perfectly well; `make ext` builds both extensions,
  so the `-std=gnu17`/`-ObjC` interaction it worried about does not happen here.

**The manual tier works, and C2 (retina) can be struck off the "needs a human"
list.** `./build/rgame` opens a real window and renders correctly: the two
overlapping alpha-blended rectangles, the triangle, the circle, the thick line,
the rotated square, and the UTF-8 string `rgame — Grüße, œuvre, 5 €` complete
with its non-ASCII glyphs. `tools/drive_example.rb` drives
`examples/16_hello_world` to `120 ticks, 120 frames` and 120 `text` draw calls.
C2's judgment call is unchanged — the window is created without
`SDL_WINDOW_ALLOW_HIGHDPI` and stays out of scope — but "correct but soft" is
now observed rather than predicted.

**One gap that is not macOS's fault**: `/media/` is in `.gitignore` and is in no
checkout, so `examples/14_asteroids` and `examples/15_tiled_world` cannot be
driven from a fresh clone on any platform — they abort loading `media/space.png`
and `media/ui/ui_atlas.json`. Only `16_hello_world` (which needs nothing beyond
the shipped font) runs. That limits the acceptance tier CLAUDE.md leans on for
wiring changes, and it is worth deciding deliberately — commit the assets,
generate them, or document where they come from — but it is pre-existing and
outside this port.

### Windows setup

Use **RubyInstaller with the DevKit** for Ruby 4.0.5 rather than mise — the
DevKit is what supplies MSYS2, and every native build here depends on it. After
installing, run `ridk install` and choose the MSYS2 and MINGW development
toolchain option.

**Measured 2026-08-25, and this part of the instructions was wrong: the
DevKit combo installer is not required, only a RubyInstaller-*built* Ruby
is.** The machine already had Ruby 4.0.5 `x64-mingw-ucrt` installed through
`vfox` (a version manager, not RubyInstaller's own installer) with no MSYS2
anywhere. `ridk` still worked, because it ships as an ordinary bundled library
(`ruby_installer/runtime`, under `lib/ruby/site_ruby`) in *any* official
RubyInstaller build — mise and vfox both fetch those same builds — and it
autodetects MSYS2 from several places
([`msys2_installation.rb`](https://github.com/oneclick/rubyinstaller2), read
directly off this machine): an `MSYS2_PATH` env var, a folder named `msys64`
next to the Ruby install, `C:\msys64`, the registry key MSYS2's own installer
writes, anything already on `PATH`, or `scoop prefix msys2`. So installing
**standalone MSYS2** and letting `ridk` find it works just as well as the
DevKit combo installer, and is the better instruction when Ruby is already
managed by something else:

```sh
winget install --id MSYS2.MSYS2 -e --accept-package-agreements --accept-source-agreements
```

installs to the default `C:\msys64`, which is the second place `ridk` looks
after `MSYS2_PATH` and before the registry — confirmed with `ridk version`,
which printed `msys2: path: c:\msys64` with no further configuration. First
run needs the standard two-pass MSYS2 core update before installing anything
else (the first pass replaces `msys2-runtime` itself and the shell needs to
reopen — `pacman -Syu` then `pacman -Su` from a fresh shell, or just run each
via `ridk exec pacman` as below and re-run if the first one stops short):

```sh
ridk exec pacman -Syu --noconfirm   # core update, may need a second invocation
ridk exec pacman -Su  --noconfirm   # rest of the base system
```

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

All of the above ran verbatim and succeeded. Confirmed working afterward:
`ridk exec which gcc` → `/ucrt64/bin/gcc`; `ridk exec pkg-config --cflags sdl2`
and `check` both resolved to `c:/msys64/ucrt64/include/...`; `bundle install`
completed including native gems (`json`, `zlib`, `prism`); `make test` compiled
and linked all 25 engine translation units plus the Check binary against
SDL2/opengl32/check with **no source changes** — confirming A1–A3 and A2/step-2
work as already landed; `make ext-util` and `bundle exec rake spec` ran, 904
examples with only the 3 failures noted at A4 and A5 above (this was before
either was fixed).

**One packaging-adjacent finding from this same first session, unrelated to
the build itself:** `make ext-util`/`make ext-core` each leave behind a
`*-x64-mingw-ucrt.def` file (mkmf's export list for the linker) next to the
extension's `.c` files, and one of them had already been committed by hand —
`.gitignore` had every other mkmf artifact (`Makefile`, `mkmf.log`, `*.o`,
`*.so`) but not `*.def`. A `NUL` file also turned up in `ext/rgame_util/`,
apparently from an mkmf-generated Makefile rule redirecting to a POSIX-style
null-device path that MSYS2 `make` creates literally on Windows instead of
discarding. Both patterns are now in `.gitignore`, and the wrongly-committed
`.def` is untracked — small, but exactly the kind of thing that only a real
Windows build surfaces.

**Second session, same day: A4, A5 and B1/B2/B4/B8 all landed — see their own
sections — and the full `rake` task (`make test` + `rake spec` + `rake
spec:core`) passes cleanly: 325 + 904 + 350 examples, 0 failures, repeatably.**
B7 is believed fixed as a side effect of B4 but not confirmed; see B7's own
account of why that belief is qualified rather than a clean "landed."

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

### Run this experiment first — *(done; answered)*

**Answered 2026-08-25: the audio tests pass on a Mac with a sound card
(325/325), and fail only on the device-less runner (19 errors). That is
hypothesis 2, and the fix is B9's, extended to macOS — see B9a.** The rest of
this section is kept because the reasoning is what made the one-command
experiment decisive, and the `MA_NO_RUNTIME_LINKING` follow-up below is still
the right move if C3 is ever picked up.

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

**Landed on Windows** — see B4. Its side effect on B7 is the reason this step
turned out to matter more than its own suite.

### Step 4 — dlopen names in the spec support (B1)

`rendered_frame.rb` and `virtual_gamepad.rb`. First step where `rake spec:core`
can get anywhere on either platform.

**Landed on Windows** — see B1.

### Step 5 — read pixels before the swap (B2)

Do this *before* interpreting any macOS or Windows pixel-spec failure, so a
harness assumption cannot be mistaken for a renderer bug. Real GPU drivers are
free to page-flip; llvmpipe's copy-swap is what the current read relies on.

**Landed on Windows, and the prediction here was exactly right** — see B2. A
real Windows driver does page-flip; this was the single highest-impact fix in
the whole port (56 of 58 `spec:core` failures on Windows).

### Flip `ported: true` — per platform, when its leg is actually green

Not attached to a single step, because a leg goes green only once *all* of
1–5 that apply to it are done. The sketch pinned this to steps 2 and 3, which
was wrong: `rake spec:core` runs on every leg, so the spec scaffolding gates it
just as much as the compiler flags do.

Leaving a working platform marked unported is how it silently rots back out —
`continue-on-error` means nobody would notice it break again. See the flag's
comment in [`ci.yml`](../../.github/workflows/ci.yml).

**Windows qualifies as of 2026-08-25** — every item that applies to it (A4–A6,
B1, B2, B4, B7, B8) is landed, `rake` is clean, and B7 specifically is now a
closed, understood bug rather than an open question (see its section). Nothing
is left gating the flip except CI actually proving it on a fresh runner, which
is what pushing with the flag flipped is for.

**macOS is one confirming run away, and should be flipped on that run rather
than before it.** Everything that applies to it is landed — A2/A3's darwin
branches, B1's macOS half, B9a, B11, B13 — and `rake` is clean end to end on a
real Mac (325 + 905 + 350, exit 0). What is *not* yet proven is the one thing
that cannot be proven here: B9a's zero-device branch, which needs a Mac with no
audio hardware, i.e. the runner itself.

So the sequence is: push with macOS still `ported: false`, then **read the step
outcomes rather than the job badge** (B12 — the badge will say `success` either
way, and a backtrace step that *ran* means the C suite failed). If `make test`
and `rake spec:core` both come back clean, flip the flag in the same breath and
push again; the flip is what stops it rotting back out, and while it stays
`false` a regression on macOS is indistinguishable from the unported state.

Do not flip it *before* that run: with `continue-on-error` gone, a leg that is
still red on the zero-device path would turn the whole workflow red and take
Linux's regression guard down with it, which is the failure the flag exists to
prevent.

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
