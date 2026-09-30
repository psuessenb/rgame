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
   `test/suites.h`. `test/test_main.c` runs them all as one binary, so a new
   module adds a file and two lines rather than another `main()`. Logic also
   useful from Ruby on its own belongs in `ext/rgame_util/` instead.
2. **Fake/recording backend** — a function-pointer table between the pure logic
   and the real calls, so a test can link a fake that records what it was asked
   to draw. That makes "the right calls in the right order" checkable with no
   display. Add the seam *when* a subsystem starts producing real SDL or
   GL calls, not ahead of it.
3. **Thin real shim** — the `SDL_*` and `gl*` calls themselves, taking
   already-computed values from layer 1. Being this thin justifies not
   unit-testing it.

**Write layer 1 and its Check tests before touching SDL or GL at all.**

## Where a new file goes

**All engine C lives in `ext/rgame_core/`**, not a top-level `src/`. `gem install`
runs each `extconf.rb`, and an extension can build only sources within its own
directory. Keeping the C there lets one copy feed both the standalone binary and
the gem.

Inside it, sources are grouped by subsystem, and includes name the folder they
come from. `graphics/canvas.c` says `#include "graphics/clip.h"`, so a
dependency crossing a subsystem boundary shows in the source rather than hiding
in an include path. **A new engine source goes in the folder for its subsystem.**

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
`test/test_clip.c`. Layer 3 is the exception: it is verified by looking at
pixels. `graphics/gl_backend.c`, `graphics/image.c` and `text/font_atlas.c` are
the only files on the draw path that call `gl*`.

### What the build needs from it

mkmf compiles every `.c` in an extension's own directory and nothing deeper, so
`extconf.rb` lists these folders in `SOURCE_DIRS`, feeding `$srcs` and `$VPATH`.
Two things follow. Objects are named after the source's *basename*, so
**basenames must be unique across the whole tree**. mkmf aborts with `source
files duplication` rather than clobbering one, so that rule holds itself up. And
a **new folder** must be added to `SOURCE_DIRS`; forgetting fails loudly, as an
undefined symbol. Adding a file to a listed folder needs nothing.

`include/` is on the include path but not in `SOURCE_DIRS` — a header directory,
never a source one. `core.h` takes plain C types only, with no SDL or GL type in
a signature. That lets `ruby/core_ext.c` include it without pulling in `SDL.h`
conflicts.

### The placements that were decisions

- **`vendor/`** — beside each vendored library sits the single translation unit
  (`<name>_impl.c`) that instantiates it. **These are the only files compiled
  without `-Wall -Wextra`.** The `_impl.c` suffix selects them, from one list in
  both `extconf.rb` and the root `Makefile`. Feature macros live in the
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

`ruby/core_ext.c` holds `RGame::Core::App`. Every other Ruby-visible class gets
its own file, with one init function declared in `core_ext.h`, the same shape as
`ext/rgame_util/util_ext.h`. Adding a class then means adding a file rather than
growing an unrelated one. `audio_ext.c` is the one deliberate exception:
`Audio`, `Sample` and `Song` share a wrapping shape, and splitting them would
triplicate TypedData boilerplate to separate ninety lines.

`ext/rgame_util/`'s `extconf.rb` has no `pkg_config` and no `-lGL`, and that
enforces the Core/Util split. Its pure files (`color`, `solid_grid`,
`route_search`, `tile_sweep`) have no `ruby.h`, so the Check suite covers them
directly; the `*_ext.c` beside each is only the binding.

Both extensions build to a `.so` that `make ext` copies into `lib/rgame/`, where
`require "rgame/core_ext"` finds it.

### Adding an engine feature

Put the implementation in `ext/rgame_core/app/app.c` and extend `core.h`'s public
API rather than adding logic to `main.c`. That keeps the Ruby wrapper thin.
`docs/c_engine_feature_specs.md` holds the scope list this engine was built
against. Consult it when adding a subsystem rather than guessing, and amend it
when a decision contradicts it.

## Conventions

C17, `-Wall -Wextra`, keep it warning-clean. The extensions compile with
`-std=gnu17` instead — Ruby's headers lean on GNU extensions, and gnu17 is a
superset, so the same sources still satisfy C17.

**No OpenGL loader (GLAD/GLEW) yet.** The engine uses legacy,
compatibility-profile GL calls (`glBegin`/`glEnd`), because those need no extra
dependency. A move to core-profile modern GL needs a loader; flag that as a
deliberate decision, not a drive-by change.

## The traps Linux and macOS cannot surface

Every item below was found the hard way, on a real Windows machine, while
getting this project building and green there. Linux and macOS cannot surface
any of them. They show up only on a Windows machine, or under the sanitizer
setup in "How to actually catch these" below. Several are not Windows bugs at
all: they are C, Check or CRuby facts, true everywhere, which this project's
Linux-only development happened to hide.

### `long` is not "a type wider than `int`" — on Windows it is `int`'s width

This one lesson lay behind three separate bugs found in one session. It is the
one most likely to recur, because the code that trips it usually looks
portable.

**The fact**: Linux and macOS use the LP64 data model, where `long` is 64
bits. Windows uses LLP64, where `long` stays 32 bits — the same width as
`int` — even in a 64-bit process, even with a 64-bit `size_t` and 64-bit
pointers. Compiling for x86-64 does not change this. It is a Windows ABI
choice, shared by every C compiler that targets it: MSVC, and MinGW/UCRT gcc and
clang, which follow the platform's calling convention.

**What this breaks**: any code that reaches for `long` *because* it wants more
range than `int`, the classic idiom for avoiding a signed overflow before
narrowing back down. On Windows that idiom silently computes in the width it
was trying to escape. The overflow it was meant to prevent still happens, and it
is undefined behaviour, not only a wrong answer.

```c
// ext/rgame_core/graphics/clip.c, before the fix:
long a_right = (long)a.x + a.w;   // still 32 bits on Windows — same bug as int

// after:
int64_t a_right = (int64_t)a.x + a.w;   // 64 bits everywhere, unconditionally
```

**The rule**: never use bare `long`/`unsigned long` to mean "wider than
`int`". Use `<stdint.h>`'s fixed-width types instead,
`int32_t`/`int64_t`/`uint32_t`/`uint64_t`, which say what they mean on every
platform this project builds for. `long` is fine only for a value whose width
does not matter (and even then, prefer `int`), or where an external API's
signature requires it verbatim.

#### The Ruby-C-API version of the same bug

`NUM2ULONG`/`NUM2LONG`/`RB_NUM2LONG` convert through C `long`, so they inherit
the same 32-bit ceiling on Windows. Ruby's conversion macros raise `RangeError`
when the value does not fit, so this version of the bug corrupts nothing. It
rejects valid input on Windows that Linux accepts.

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
be wider than 32 bits, pull it in with `NUM2ULL`/`NUM2LL`, not the `LONG`
family. Those convert through `unsigned long long`/`long long`, 64 bits
everywhere. Then do the range check, then narrow.

#### The CRuby-internals version — only relevant if C code hands Ruby a big integer

Nothing to fix, only something to know. CRuby keeps a small integer as an
immediate value ("Fixnum"), with no heap allocation, up to a magnitude set by
the C `long` the interpreter was built with. LP64 Ruby gets roughly 2^62 of
headroom; Windows' LLP64 Ruby gets roughly 2^30. The gap is invisible from
`Integer#class`, which reports `Integer` either way in modern Ruby. If C code
computes and returns (via `LL2NUM`/`ULL2NUM`) a Hash or Set key or an array
index, keep it well under 2^30 in magnitude on every platform. Otherwise the
Windows build silently heap-allocates on every access where Linux stayed
allocation-free. This bit `RGame::Engine::SpatialHash`, which is pure Ruby, but
the same ceiling applies to anything a C extension hands back.

### A failed `ck_assert_*` skips everything after it in that function — including cleanup

True on every platform; Windows is only where it finally bit. A failing Check
assertion aborts the current test through a non-local jump. That is what makes
"one bad assertion fails one test" work. It also means **no code after a failed
`ck_assert_*` in the same function runs**, cleanup included.

For a test that touches only heap memory, a skipped `free` is a leak: bad, but
contained, since the process exits and takes the leak with it. A test that opens
a **real device or spawns a real thread** fares worse. The resource keeps
running after the test function has returned. It reads and writes through local
variables that, as far as the call stack is concerned, no longer exist. Once
*any* later test's stack frame reuses that memory, as stack frames do, the
still-running thread corrupts it. The crash can land on any later test, with no
visible connection to the real bug.

One long-hunted crash in this project turned out to be this.
`test/test_vorbis_decoder.c`'s `the_engine_refuses_a_file_that_is_not_an_ogg`
opens a real `ma_engine`, which spawns a mixer thread. It then calls a helper
whose `ck_assert_int_ge(fd, 0)` failed on Windows (see the temp-directory item
below). That skipped the `ma_engine_uninit` at the bottom of the function and
leaked the thread. The crash it eventually caused seemed to sit in an unrelated
`audio` suite, dozens of lines away.

**The rule**: once a test has opened a real device, file handle, or thread,
treat every `ck_assert_*` between that point and its teardown as a potential
leak of that resource. Do anything that can fail — parsing, comparisons, format
checks — *before* the resource opens. Where that is not possible, release it in
`tcase_add_checked_fixture`'s teardown callback, not inline at the end of the
test body (`ma_engine_uninit`, `fclose` and the like). Check guarantees the
teardown runs even after a failed assertion.

### Never hardcode `/tmp` (or any other POSIX-only path)

Windows has no `/tmp`, so `mkstemp("/tmp/...")` fails outright there. `mkstemp`
itself exists (MinGW/UCRT provides a working one); the directory does not. That
was a real bug here, and it fed straight into the skipped-cleanup item above.

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

**The rule**: build a scratch path from `TMPDIR`, `TEMP` or `TMP`, in that
order, never a literal `/tmp/...`. POSIX tools check `TMPDIR` first when it is
set; Windows sets `TEMP` and `TMP`. Size the buffer for a real Windows temp
path, not a short Linux one: `snprintf` into a few hundred bytes, not a `strcpy`
into a buffer sized for one literal string.

### Don't assume anything about GL back-buffer contents after a swap

`SDL_GL_SwapWindow` guarantees nothing, on any platform, about the buffer it
just displayed. Mesa's llvmpipe, which `rake spec:core` runs against under Xvfb
on Linux, happens to *copy* on swap, so the previous frame's image is still
readable at the start of the next one. A real driver is free to *page-flip*
instead, which leaves that buffer's contents undefined the moment the swap
returns. Test or engine code that reads back what was just drawn must do so
**before** the swap. The `frame_end` hook (`ext/rgame_core/include/rgame/core.h`)
exists for that: it gives that moment a name. Never write new code that reads
pixels "at the start of the next frame" and calls it equivalent.

### A machine with *zero* audio devices is a real, common case — CI hits it every run

`create_audio`'s comment always claimed that opening a device with no explicit
backend list "falls back to a null device when none of them can open". That was
verified on Linux, where a build server with no ALSA or PulseAudio enumerates
zero devices and the fallback lands cleanly on Null. GitHub Actions'
`windows-latest` runners, like most other Windows CI and cloud VMs, have **zero
audio devices** — not only no default device, but none at all:
`Get-CimInstance Win32_SoundDevice` returns nothing. That differs from "the
default device is unavailable". On Windows, WASAPI's own attempt to open a
device when there was none crashed the whole process, rather than failing in a
way `ma_engine_init`'s return code could report. The fallback the comment
described never got a chance to run, because nothing survived long enough to
try the next backend.

**The rule**: do not trust an auto-detect backend list to fail *gracefully*
into a null device on Windows. It may crash instead of failing. Where a real
device is wanted but the platform might have none, enumerate first with
`ma_context_get_devices`, which is read-only and opens nothing. Fall back
explicitly when the count is zero, rather than letting the real backend's own
open attempt discover it.

**And when you fall back, prefer no device over an explicit Null one, if the
caller can tolerate it.** The first version of this fix chose an explicit
`{ ma_backend_null }` context. That still opens a real `ma_device` and spins up
a real background polling thread, like any other backend. The thread crashed on
Windows CI too, but only **inside a Ruby process**: the identical C code passed
`make test`'s plain-C Check suite on the same runner. The cause was never pinned
down, for lack of a device-less machine to debug on, and did not need to be.
`ma_engine_init` with `noDevice = MA_TRUE` spins up no device and no background
thread, so nothing is left to crash the way a thread can.
`ext/rgame_core/audio/audio.c`'s offline constructor already uses it for tests.
Prefer it over an explicit Null backend when the caller needs only an engine
that exists without error, not automatic device-driven callbacks.
`create_audio`'s Windows branch has the final shape: enumerate, and reach for
`noDevice` only when the count is zero.

This generalises past audio: **assume a CI runner has no hardware of a given
kind unless something upstream, such as a display server for a window, is known
to provide it.** Audio is the one measured here. A webcam, a printer, or any
other device class a future feature reaches for gets the same "enumerate before
you open" treatment, rather than a graceful-failure assumption only ever tested
on Linux.

### A background thread can crash inside Ruby in ways the identical code never does in plain C

`make test`, the Check suite with no Ruby in the process, passed with the
explicit-Null-backend version of the fix above. On the same CI runner,
`rake spec:core` crashed running the identical `create_audio` code inside
`ruby.exe`. This project's own C spawned the failing thread, through
miniaudio's `ma_thread_create__win32` rather than `rb_thread_create` or anything
Ruby-aware. It was a raw OS thread that Ruby never created and knows nothing
about, in a process where Ruby otherwise assumes it knows every thread.

**The rule**: passing the Check suite does not prove a background OS thread safe
when a C extension spawns it directly. That covers audio, and any future
subsystem that polls, streams or watches something on its own thread. Check runs
the thread in a plain C process, and `make test` cannot represent what Ruby's
runtime expects of the threads in its process. When new C code needs a
background thread and will be called from Ruby, verify it there too —
`rake spec:core`, or a live Windows CI run, not only `make test` — before
trusting it. Where the library's own no-op or synchronous mode avoids the
thread, as `noDevice` did here, prefer that mode when it meets the need. The
Check suite alone can appear to bless a thread that crashes under Ruby.

### dlopen/soname differences, if new C touches a system library by name

This does not concern the engine C itself, which links normally. It concerns
any Fiddle-based Ruby helper or C code that opens a system library by soname at
runtime. The name differs on every platform, and code meant to run on more than
one must handle each.

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
unrelated SDL. On Linux that is the system one. On Windows it is RubyInstaller's
MSYS2 `SDL2.dll`, which Ruby's own DLL-directory mechanism reaches even with no
`msys64` on `PATH`. Calls then succeed against state the engine never sees. The
spec harness's virtual gamepad hit this, which is why it now lives in the
extension as `RGame::Core::VirtualGamepad` (`input/virtual_gamepad.c`). SDL
functionality a spec needs goes into the extension the same way.

## How to actually catch these before they land

Linux CI cannot catch any of the above; that is why this section exists. Two
things can, and neither needs a Windows machine to be *fixed* on, only to be
*checked* on occasionally:

- **AddressSanitizer/UBSan, on a real Windows build.** This found the real
  mechanism behind two of the bugs above, after plain testing had shown only
  symptoms.
  MinGW gcc's `ucrt64` MSYS2 package ships **no sanitizer runtime at all**
  (`ld: cannot find -lasan`). Install the separate `clang64` environment
  instead: `mingw-w64-clang-x86_64-clang`, `-compiler-rt`, and clang64-prefixed
  `-SDL2`/`-check`, since mixing `ucrt64` and `clang64` binaries is not safe.
  Then build with `CC=clang CFLAGS="-std=c17 -Wall -Wextra -g -fPIC -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"`.
  [verify](../verify/SKILL.md)'s "Leaks" section has the Linux/macOS version of
  this recipe: the same idea, a different toolchain.
- **Reading this list before writing the code**, for everything that is not a
  memory-safety bug ASan would catch. The `NUM2ULONG` `RangeError`, the missing
  temp directory and the swap-timing assumption are all valid C, and none of
  them would make a sanitizer blink. They show up only if you ask "does this
  still hold when `long` is 32 bits / there is no `/tmp` / the driver
  page-flips?" while writing the line, not after.
