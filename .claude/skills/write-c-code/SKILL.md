---
name: write-c-code
description: Everything that governs C in this project — the three-layer split every subsystem gets, where a new source or class goes and what the extension build needs from it, the C conventions, and the portability traps (LLP64 `long`, `NUM2ULONG`, `/tmp`, GL back-buffer reads, a CI machine with no audio device, a C thread inside Ruby) that Linux and macOS cannot surface. Use whenever writing or editing C under `ext/` or `src/`, adding a Ruby C-extension binding, adding a Check test, adding a folder or file to an extension, or reading a CI failure that only happens off Linux.
---

# Writing C for rgame

**Every file's own top comment says what it is and why it is shaped that way** —
those comments are the reference. This is what a file cannot tell you about
itself: how to split the work, where the new file goes, what the build needs
from it, and which lines are valid C everywhere and correct only on Linux.

## Split every new subsystem into three layers

This is the standing rule, not advice for one feature.

1. **Pure logic** — state and arithmetic with no SDL, no GL, no I/O. This is most
   of what is hard to get right in a 2D engine, and none of it needs a window to
   test. Give it its own module (`ext/rgame_core/<area>/<name>.c` plus a header)
   and Check tests. Each test file exposes a Check `Suite` declared in
   `test/suites.h`, and `test/test_main.c` runs them as one binary, so a new
   module adds a file and two lines rather than another `main()`. Logic also
   useful from Ruby on its own belongs in `ext/rgame_util/` instead.
2. **Fake/recording backend** — a function-pointer table between the pure logic
   and the real calls, so a test can link a fake that records what it was asked
   to draw. That is what makes "the right calls in the right order" checkable
   with no display. Add the seam *when* a subsystem starts producing real SDL or
   GL calls, not ahead of it.
3. **Thin real shim** — the actual `SDL_*` and `gl*` calls, taking already-computed
   values from layer 1. Being this thin is what justifies not unit-testing it.

**Write layer 1 and its Check tests before touching SDL or GL at all.**

## Where a new file goes

**All engine C lives in `ext/rgame_core/`**, not a top-level `src/`. `gem install`
runs each `extconf.rb`, and an extension can only build sources within its own
directory, so keeping the C there means one copy feeds both the standalone binary
and the gem.

Inside it, sources are grouped by subsystem, and includes name the folder they
come from: `graphics/canvas.c` says `#include "graphics/clip.h"`, so a dependency
crossing a subsystem boundary is visible in the source rather than hidden in an
include path. **A new engine source goes in the folder for its subsystem.**

| | |
|---|---|
| `app/` | the SDL window, the GL context and the main loop |
| `graphics/` | transform and clip stacks, draw queue, textures, primitives, recordings, the GL backend |
| `text/` | font, glyph atlas and cache, the atlas pages |
| `input/` | the input snapshot, the button-id space, gamepads and their player slots |
| `audio/` | the sound device and the Ogg decoder, over miniaudio — no SDL, no GL |
| `ruby/` | the Ruby glue; the only C here that includes `ruby.h` |
| `vendor/` | third-party sources |
| `include/rgame/core.h` | the only public API |

A pure module's Check test mirrors its name: `graphics/clip.c` is covered by
`test/test_clip.c`. Layer 3 is the exception and is verified by looking at
pixels — `graphics/gl_backend.c`, `graphics/image.c` and `text/font_atlas.c` are
the only files on the draw path that call `gl*`.

### What the build needs from it

mkmf compiles every `.c` in an extension's own directory and nothing deeper, so
`extconf.rb` lists these folders in `SOURCE_DIRS`, feeding `$srcs` and `$VPATH`.
Two things follow. Objects are named after the source's *basename*, so
**basenames must be unique across the whole tree** — mkmf aborts with `source
files duplication` rather than clobbering one, so that rule holds itself up. And
a **new folder** must be added to `SOURCE_DIRS`; forgetting fails loudly, as an
undefined symbol. Adding a file to a listed folder needs nothing.

`include/` is on the include path but not in `SOURCE_DIRS` — a header directory,
never a source one. `core.h` takes plain C types only, no SDL or GL types in a
signature, which is what lets `ruby/core_ext.c` include it without pulling in
`SDL.h` conflicts.

### The placements that were decisions

- **`vendor/`** — beside each vendored library sits the single translation unit
  (`<name>_impl.c`) that instantiates it. **The only files compiled without
  `-Wall -Wextra`**, and the `_impl.c` suffix is what selects that, from one list
  in both `extconf.rb` and the root `Makefile`. Feature macros live in the
  `_impl.c` rather than in build flags, so the binary and the gem cannot end up
  supporting different formats.
- **`lib/rgame/fonts/`** — the default font (Liberation Sans, SIL OFL 1.1) is
  runtime data, so it lives where a gem installs data rather than in `ext/`.
- **`input/virtual_gamepad.c`** — test-only, and in the extension on purpose: a
  spec helper reaching SDL through Fiddle opens a *second* SDL once the extension
  links SDL statically.
- **`src/main.c`** — stays outside `ext/` so mkmf does not compile its `main()`
  into the extension. It and `ext/rgame_core/example.rb` are parallel drivers of
  the same API, and an API change generally needs both.

### One class, one file, on both sides

`ruby/core_ext.c` holds `RGame::Core::App`; every other Ruby-visible class gets
its own file with one init function declared in `core_ext.h`, the same shape as
`ext/rgame_util/util_ext.h`. So adding a class means adding a file rather than
growing an unrelated one. `audio_ext.c` is the one deliberate exception —
`Audio`, `Sample` and `Song` share a wrapping shape, and splitting them would
triplicate TypedData boilerplate to separate ninety lines.

`ext/rgame_util/`'s `extconf.rb` has no `pkg_config` and no `-lGL`, which is what
enforces the Core/Util split. Its pure files (`color`, `solid_grid`,
`route_search`, `tile_sweep`) have no `ruby.h`, so the Check suite covers them
directly; the `*_ext.c` beside each is only the binding.

Both extensions build to a `.so` that `make ext` copies into `lib/rgame/`, where
`require "rgame/core_ext"` finds it.

### Adding an engine feature

Put the implementation in `ext/rgame_core/app/app.c` and extend `core.h`'s public
API rather than adding logic to `main.c`; that is what keeps the Ruby wrapper
thin. `docs/c_engine_feature_specs.md` holds the scope list this engine was built
against — consult it when adding a subsystem rather than guessing, and amend it
when a decision contradicts it.

## Conventions

C17, `-Wall -Wextra`, keep it warning-clean. The extensions compile with
`-std=gnu17` instead — Ruby's headers lean on GNU extensions, and gnu17 is a
superset, so the same sources still satisfy C17.

**No OpenGL loader (GLAD/GLEW) yet** — using legacy/compatibility-profile GL
calls (`glBegin`/`glEnd`) since that's what's available without extra
dependencies. If/when the project moves to core-profile modern GL, a loader will
need to be added — flag that as a deliberate decision, not a drive-by change.

## The traps Linux and macOS cannot surface

Every item below was found the hard way, on a real Windows machine, while
getting this project building and green there. Linux and macOS cannot surface
any of them — they need a Windows machine, or the specific sanitizer setup in
"How to actually catch these" below, to show up at all. Several are not Windows
bugs at all: they are C, Check or CRuby facts that are true everywhere, which
this project's Linux-only development happened to hide.

### `long` is not "a type wider than `int`" — on Windows it is `int`'s width

This is the one lesson behind three separate bugs found in one session, and
the one most likely to recur, because the code that trips it
usually reads as obviously portable.

**The fact**: Linux and macOS use the LP64 data model, where `long` is 64
bits. Windows uses LLP64, where `long` stays 32 bits — the same width as
`int` — even in a 64-bit process, even with a 64-bit `size_t` and 64-bit
pointers. Nothing about compiling for x86-64 changes this; it is purely a
Windows ABI choice, shared by every C compiler that targets it (MSVC, and
MinGW/UCRT gcc and clang, which just follow the platform's calling
convention).

**What this breaks**: any code that reaches for `long` specifically *because*
it wants more range than `int` — the classic idiom for avoiding a
signed-overflow before narrowing back down. On Windows that idiom silently
computes in exactly the width it was trying to escape, and the overflow it
was meant to prevent still happens (undefined behaviour, not merely a wrong
answer).

```c
// ext/rgame_core/graphics/clip.c, before the fix:
long a_right = (long)a.x + a.w;   // still 32 bits on Windows — same bug as int

// after:
int64_t a_right = (int64_t)a.x + a.w;   // 64 bits everywhere, unconditionally
```

**The rule**: never use bare `long`/`unsigned long` to mean "wider than
`int`". Use `<stdint.h>`'s fixed-width types instead —
`int32_t`/`int64_t`/`uint32_t`/`uint64_t` — which say what they mean on every
platform this project builds for. `long` is fine only for a value whose width
genuinely doesn't matter (and even then, prefer `int`), or when an external
API's signature requires it verbatim.

#### The Ruby-C-API version of the same bug

`NUM2ULONG`/`NUM2LONG`/`RB_NUM2LONG` convert through C `long`, so they inherit
the exact same 32-bit-on-Windows ceiling — and because Ruby's own conversion
macros raise `RangeError` when the value doesn't fit, this version of the bug
doesn't corrupt anything, it just rejects valid input on Windows that Linux
accepts.

```c
// ext/rgame_util/color_ext.c, before the fix:
unsigned long value = NUM2ULONG(packed);      // raises RangeError on Windows
                                               // for a value Linux converts fine
if (value > 0xFFFFFFFFul) { ... }             // this check never gets a chance to run

// after:
unsigned long long value = NUM2ULL(packed);   // 64 bits everywhere
if (value > 0xFFFFFFFFull) { ... }
```

**The rule**: when a Ruby-facing bounds check needs to see a value that might
be wider than 32 bits, pull it in with `NUM2ULL`/`NUM2LL` (`unsigned long
long`/`long long`, unconditionally 64-bit), not the `LONG` family, then do the
range check, then narrow.

#### The CRuby-internals version — only relevant if C code hands Ruby a big integer

Not something to fix, just something to know: CRuby represents a small
integer as an immediate value ("Fixnum") with no heap allocation, up to a
magnitude derived from the C `long` the interpreter itself was built with.
LP64 Ruby gets roughly 2^62 of headroom; Windows' LLP64 Ruby gets roughly
2^30 — dramatically smaller, and invisible from `Integer#class`, which
reports `Integer` either way in modern Ruby. If C code computes and returns
(via `LL2NUM`/`ULL2NUM`) a value meant to be used as a Ruby Hash/Set key or
array index, keep it well under 2^30 in magnitude on every platform, or the
Windows build silently starts heap-allocating on every access where Linux
stayed allocation-free. (This bit `RGame::Engine::SpatialHash`, pure Ruby —
but the same ceiling applies to anything a C extension hands back.)

### A failed `ck_assert_*` skips everything after it in that function — including cleanup

True on every platform; Windows is only where it finally bit. Check's assertion
macros abort the current test via a non-local jump on failure. That is exactly
what makes "one bad assertion fails one test" work — and it means **any code
after a `ck_assert_*` in the same function never runs if that assertion fails**,
cleanup included.

For a test that only touches heap memory, a skipped `free` is a leak — bad,
but contained; the process still exits and the leak goes with it. For a test
that opens a **real device or spawns a real thread**, it is worse: the
resource keeps running in the background after the test function has
returned, reading and writing through local variables that, as far as the
call stack is concerned, no longer exist. Once *any* later test's stack frame
happens to reuse that memory — ordinary, unavoidable stack behaviour — the
still-running background thread corrupts it. The resulting crash can land
anywhere, on any later test, with no visible connection to the actual bug.

This is exactly what one long-hunted crash in this project turned out to be:
`test/test_vorbis_decoder.c`'s `the_engine_refuses_a_file_that_is_not_an_ogg`
opens a real `ma_engine` (spawning a mixer thread), then calls a helper whose
`ck_assert_int_ge(fd, 0)` failed on Windows (see the temp-directory item below)
— skipping the `ma_engine_uninit` at the bottom of the function and leaking the
thread. The crash it eventually caused looked like it was in a completely
unrelated `audio` suite, dozens of lines away.

**The rule**: once a test has opened a real device, file handle, or thread,
treat every `ck_assert_*` between that point and its teardown as a potential
leak of that resource. Prefer doing anything that can fail — parsing,
comparisons, format checks — *before* the resource opens. Where that isn't
possible, use `tcase_add_checked_fixture`'s teardown callback, which Check
guarantees runs even after a failed assertion, rather than an inline
`ma_engine_uninit`/`fclose`/etc. at the end of the test body.

### Never hardcode `/tmp` (or any other POSIX-only path)

Windows has no `/tmp`, and `mkstemp("/tmp/...")` fails outright there — not
because `mkstemp` itself is missing (MinGW/UCRT provides a working one), but
because the directory doesn't exist. That was a real bug here, and it also fed
straight into the skipped-cleanup item above.

```c
// test/test_vorbis_decoder.c, before the fix:
static char path[] = "/tmp/rgame_vorbis_testXXXXXX";   // C:\tmp doesn't exist

// after: read the actual platform temp dir
static const char *scratch_dir(void) {
    const char *candidates[] = { "TMPDIR", "TEMP", "TMP" };
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        const char *dir = getenv(candidates[i]);
        if (dir && *dir) { return dir; }
    }
    return "/tmp";
}
```

**The rule**: build a scratch path from `TMPDIR`/`TEMP`/`TMP` (in that order —
`TMPDIR` is what POSIX tools check first when it's set; `TEMP`/`TMP` are what
Windows actually sets), never a literal `/tmp/...`. Size the buffer for a real
Windows temp path, not a short Linux one — `snprintf` into a few hundred
bytes, not a `strcpy` into a buffer sized for one literal string.

### Don't assume anything about GL back-buffer contents after a swap

`SDL_GL_SwapWindow` gives no guarantee about what happens to the buffer that
was just displayed — on any platform. Mesa's llvmpipe (what `rake spec:core`
runs against under Xvfb on Linux) happens to *copy* on swap, so the previous
frame's image is still readable at the start of the next one; a real driver is
free to *page-flip* instead, which leaves that buffer's contents undefined the
moment the swap returns. Code (test or engine) that needs to read back what
was just drawn must do so **before** the swap, not after — which is what the
`frame_end` hook (`ext/rgame_core/include/rgame/core.h`) exists for: it gives
exactly that moment a name. Never write new code that reads pixels
"at the start of the next frame" and calls it equivalent.

### A machine with *zero* audio devices is a real, common case — CI hits it every run

`create_audio`'s comment always claimed that opening a device with no
explicit backend list "falls back to a null device when none of them can
open," and that was verified — on Linux, where a build server with no ALSA or
PulseAudio enumerates zero devices and the fallback lands cleanly on Null.
GitHub Actions' `windows-latest` runners (and most other Windows CI/cloud VMs)
have **zero audio devices, full stop** — not merely no default, actually none
(`Get-CimInstance Win32_SoundDevice` returns nothing) — and that is a
different case from "the default device is unavailable": on Windows, WASAPI's
own attempt to open a device when there is nothing to open there crashed the
whole process, rather than failing in a way `ma_engine_init`'s return code
could report. The automatic same-call fallback this project's comment
described never got a chance to run, because nothing survived long enough to
try the next backend.

**The rule**: don't trust an auto-detect backend list to fail *gracefully*
into a null device on Windows — it may not fail at all, it may crash. Where a
real device is wanted but the platform might have none, enumerate first
(`ma_context_get_devices`, read-only, does not attempt to open anything) and
fall back explicitly when the count is zero, rather than letting the real
backend's own open attempt discover that for you.

**And when you do fall back, prefer no device over an explicit Null one, if
the caller can tolerate it.** The first version of this fix chose an explicit
`{ ma_backend_null }` context — which still opens a real `ma_device` and
spins up a real background polling thread, same as any other backend. That
thread crashed on Windows CI too, but only when it existed **inside a Ruby
process** — the identical C code passed cleanly through `make test`'s
plain-C Check suite on the same runner. The cause was never pinned down (no
device-less machine to debug it on), and didn't need to be: `ma_engine_init`
with `noDevice = MA_TRUE` (`ext/rgame_core/audio/audio.c`'s offline
constructor already uses this for tests) spins up no device and no background
thread at all, so there was nothing left that could crash the way a thread
can. If the caller only needs the engine to exist and not error out — not to
actually receive automatic device-driven callbacks — prefer this over an
explicit Null backend. See `create_audio`'s Windows branch for the final
shape: enumerate, and only reach for `noDevice` when the count is zero.

This generalises past audio: **any CI runner should be assumed to
have no hardware of a given kind unless something upstream (like a display
server for a window) is known to provide one.** Audio is the one measured
here; a webcam, a printer, or any other device class a future feature reaches
for should get the same "enumerate before you open" treatment rather than
trusting a graceful-failure assumption that was really only ever tested on
Linux.

### A background thread can crash inside Ruby in ways the identical code never does in plain C

`make test` (the Check suite — plain C, no Ruby in the process at all) passed
with the explicit-Null-backend version of the fix above, on the exact same
CI runner where `rake spec:core` crashed running the identical
`create_audio` code from inside `ruby.exe`. The failing thread was one this
project's own C spawned (via miniaudio's `ma_thread_create__win32`, not
`rb_thread_create` or anything Ruby-aware) — a raw OS thread Ruby never
created and knows nothing about, existing inside a process Ruby otherwise
assumes it has full knowledge of every thread in.

**The rule**: a background OS thread that a C extension spawns directly
(audio, or any future subsystem that polls, streams, or watches something on
its own thread) is not proven safe just because it passes the Check suite —
Check runs it in a plain C process, and Ruby's own runtime expectations about
its process's threads are a different environment `make test` cannot
represent. If new C code needs a background thread and targets being called
from Ruby, verify it there too (`rake spec:core`, or a live Windows CI run,
not just `make test`) before trusting it — and where the thread's job can be
avoided by using the library's own no-op/synchronous mode (as `noDevice` was
here), that is a safer default when it satisfies the use case, over spawning
one that the Check suite alone can appear to bless.

### dlopen/soname differences, if new C touches a system library by name

Not this project's engine C itself (which links normally), but relevant to
any Fiddle-based Ruby helper or C code that opens a system library by soname
at runtime: the name differs on every platform, and none of them are
optional to handle if the code is meant to run on more than one.

| Library | Linux | macOS | Windows |
|---|---|---|---|
| OpenGL | `libGL.so.1` | `/System/Library/Frameworks/OpenGL.framework/OpenGL` | `opengl32.dll` |
| SDL2 | `libSDL2-2.0.so.0` | `libSDL2-2.0.0.dylib` | `SDL2.dll` |

Branch on `RbConfig::CONFIG['host_os']` from Ruby (see
`spec_core/support/rendered_frame.rb` for the pattern) or the usual
`#ifdef _WIN32`/`__APPLE__` from C.

**Never reach SDL by name from Ruby.** A by-name dlopen finds the copy of SDL
the extension loaded only while the extension links SDL as a shared library of
that name. Against a `core_ext` with SDL linked in statically, it opens a second,
unrelated SDL: the system one on Linux, and on Windows RubyInstaller's MSYS2
`SDL2.dll`, which Ruby's own DLL-directory mechanism reaches even with no `msys64`
on `PATH`. Calls then succeed against state the engine never sees. The spec
harness's virtual gamepad hit exactly this, and is why it now lives in the
extension as `RGame::Core::VirtualGamepad` (`input/virtual_gamepad.c`). SDL
functionality a spec needs goes into the extension the same way.

## How to actually catch these before they land

Linux CI cannot catch any of the above — that's the whole reason this section
exists. Two things can, and neither needs a Windows machine to be *fixed* on,
only to be *checked* on occasionally:

- **AddressSanitizer/UBSan, on a real Windows build.** This is what actually
  found the true mechanism behind two of the bugs above, after plain testing
  only ever showed symptoms.
  MinGW gcc's `ucrt64` MSYS2 package ships **no sanitizer runtime at all**
  (`ld: cannot find -lasan`) — install the separate `clang64` environment
  instead (`mingw-w64-clang-x86_64-clang`, `-compiler-rt`, and clang64-prefixed
  `-SDL2`/`-check`, since mixing `ucrt64` and `clang64` binaries isn't safe),
  then build with `CC=clang CFLAGS="-std=c17 -Wall -Wextra -g -fPIC -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"`.
  See [verify](../verify/SKILL.md)'s "Leaks" section for the Linux/macOS
  version of this recipe — it's the same idea, different toolchain.
- **Reading this list before writing the code**, for everything that isn't a
  memory-safety bug ASan would catch — the `NUM2ULONG` `RangeError`, the
  missing temp directory, and the swap-timing assumption are all valid C, and
  none of them would make a sanitizer blink. They only show up by knowing to
  ask "does this still hold when `long` is 32 bits / there's no `/tmp` / the
  driver page-flips?" while writing the line, not after.
