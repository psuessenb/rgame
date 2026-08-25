---
name: windows-portability
description: Pitfalls that make C code (ext/rgame_core, ext/rgame_util) or its Ruby-C bindings work on Linux/macOS and silently break or crash on Windows. Use whenever writing or editing C code in this project, writing a Ruby C-extension binding (NUM2*/rb_num2*), writing a Check test that opens a real device/handle, or touching anything that reads back GPU/back-buffer state. All of this project's C was authored and tested on Linux only, so none of these bugs are visible without deliberately checking for them.
---

# Windows portability pitfalls for this project's C

Every item below was found the hard way, on a real Windows machine, during the
Windows port (`docs/plans/cross-platform-support.md`, sections A4–A6 and B2/B4/B7).
Linux and macOS cannot surface any of them — they need a Windows machine, or the
specific sanitizer setup in "How to actually catch these" below, to show up at
all. Read this before writing new C, before writing a new Ruby C-extension
binding, and before writing a Check test that opens a real device or handle.

## 1. `long` is not "a type wider than `int`" — on Windows it is `int`'s width

This is the one lesson behind three separate bugs found in one session
(A4, A5, A6), and the one most likely to recur, because the code that trips it
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
// ext/rgame_core/graphics/clip.c, before the fix (A6):
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

### The Ruby-C-API version of the same bug

`NUM2ULONG`/`NUM2LONG`/`RB_NUM2LONG` convert through C `long`, so they inherit
the exact same 32-bit-on-Windows ceiling — and because Ruby's own conversion
macros raise `RangeError` when the value doesn't fit, this version of the bug
doesn't corrupt anything, it just rejects valid input on Windows that Linux
accepts.

```c
// ext/rgame_util/color_ext.c, before the fix (A4):
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

### The CRuby-internals version — only relevant if C code hands Ruby a big integer

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
see A5 — but the same ceiling applies to anything a C extension hands back.)

## 2. A failed `ck_assert_*` skips everything after it in that function — including cleanup

Check's assertion macros abort the current test via a non-local jump on
failure. That is exactly what makes "one bad assertion fails one test" work —
and it means **any code after a `ck_assert_*` in the same function never
runs if that assertion fails**, cleanup included.

For a test that only touches heap memory, a skipped `free` is a leak — bad,
but contained; the process still exits and the leak goes with it. For a test
that opens a **real device or spawns a real thread**, it is worse: the
resource keeps running in the background after the test function has
returned, reading and writing through local variables that, as far as the
call stack is concerned, no longer exist. Once *any* later test's stack frame
happens to reuse that memory — ordinary, unavoidable stack behaviour — the
still-running background thread corrupts it. The resulting crash can land
anywhere, on any later test, with no visible connection to the actual bug.

This is exactly what B7 turned out to be:
`test/test_vorbis_decoder.c`'s `the_engine_refuses_a_file_that_is_not_an_ogg`
opens a real `ma_engine` (spawning a mixer thread), then calls a helper whose
`ck_assert_int_ge(fd, 0)` failed on Windows (see item 3) — skipping the
`ma_engine_uninit` at the bottom of the function and leaking the thread. The
crash it eventually caused looked like it was in a completely unrelated
`audio` suite, dozens of lines away.

**The rule**: once a test has opened a real device, file handle, or thread,
treat every `ck_assert_*` between that point and its teardown as a potential
leak of that resource. Prefer doing anything that can fail — parsing,
comparisons, format checks — *before* the resource opens. Where that isn't
possible, use `tcase_add_checked_fixture`'s teardown callback, which Check
guarantees runs even after a failed assertion, rather than an inline
`ma_engine_uninit`/`fclose`/etc. at the end of the test body.

## 3. Never hardcode `/tmp` (or any other POSIX-only path)

Windows has no `/tmp`, and `mkstemp("/tmp/...")` fails outright there — not
because `mkstemp` itself is missing (MinGW/UCRT provides a working one), but
because the directory doesn't exist. This was B4, and it's also what fed
straight into item 2 above.

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

## 4. Don't assume anything about GL back-buffer contents after a swap

`SDL_GL_SwapWindow` gives no guarantee about what happens to the buffer that
was just displayed. Mesa's llvmpipe (what `rake spec:core` runs against under
Xvfb on Linux) happens to *copy* on swap, so the previous frame's image is
still readable at the start of the next one — a real Windows driver is free
to *page-flip* instead, which leaves that buffer's contents undefined the
moment the swap returns. Code (test or engine) that needs to read back what
was just drawn must do so **before** the swap, not after — see B2, and the
`frame_end` hook (`ext/rgame_core/include/rgame/core.h`) added specifically
to give exactly that moment a name. Never write new code that reads pixels
"at the start of the next frame" and calls it equivalent.

## 5. dlopen/soname differences, if new C touches a system library by name

Not this project's engine C itself (which links normally), but relevant to
any Fiddle-based Ruby helper or C code that opens a system library by soname
at runtime: the name differs on every platform, and none of them are
optional to handle if the code is meant to run on more than one.

| Library | Linux | macOS | Windows |
|---|---|---|---|
| OpenGL | `libGL.so.1` | `/System/Library/Frameworks/OpenGL.framework/OpenGL` | `opengl32.dll` |
| SDL2 | `libSDL2-2.0.so.0` | `libSDL2-2.0.0.dylib` | `SDL2.dll` |

Branch on `RbConfig::CONFIG['host_os']` from Ruby (see
`spec_core/support/rendered_frame.rb`, `virtual_gamepad.rb` for the pattern)
or the usual `#ifdef _WIN32`/`__APPLE__` from C. A dlopen must also find the
copy the process *already loaded* (SDL's own), not a second one — by-name
dlopen does that on all three platforms, but it's worth asserting rather than
assuming when adding a new one.

## How to actually catch these before they land

Linux CI cannot catch any of the above — that's the whole reason this file
exists. Two things can, and neither needs a Windows machine to be *fixed* on,
only to be *checked* on occasionally:

- **AddressSanitizer/UBSan, on a real Windows build.** This is what actually
  found B7's true mechanism and A6, after plain testing only showed symptoms.
  MinGW gcc's `ucrt64` MSYS2 package ships **no sanitizer runtime at all**
  (`ld: cannot find -lasan`) — install the separate `clang64` environment
  instead (`mingw-w64-clang-x86_64-clang`, `-compiler-rt`, and clang64-prefixed
  `-SDL2`/`-check`, since mixing `ucrt64` and `clang64` binaries isn't safe),
  then build with `CC=clang CFLAGS="-std=c17 -Wall -Wextra -g -fPIC -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"`.
  See `.claude/skills/verify/SKILL.md`'s "Leaks" section for the Linux/macOS
  version of this recipe — it's the same idea, different toolchain.
- **Reading this list before writing the code**, for everything that isn't a
  memory-safety bug ASan would catch — A4's `RangeError`, B4's missing
  directory, and B2's swap-timing assumption are all perfectly valid C, and
  none of them would make a sanitizer blink. They only show up by knowing to
  ask "does this still hold when `long` is 32 bits / there's no `/tmp` / the
  driver page-flips?" while writing the line, not after.
