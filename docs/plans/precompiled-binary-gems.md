# Precompiled binary gems

**Status: steps 0–2 have landed.** Step 3 was re-planned against step 2's code.
Step 4 is detailed. Steps 5–7 are rough and get re-planned once step 4 has
landed.

Rewritten 2026-09-15 from the 2026-08-25 sketch. The sketch compared three
shapes and deferred the choice. This version takes it, records two decisions
made in conversation, and corrects two claims in the sketch: that
rake-compiler-dock has no macOS image, and that a DLL placed next to the
extension is enough on Windows.

## Goal

`gem install rgame` works on a current desktop or laptop **without a C compiler
and without SDL2 installed**. Every other machine keeps the source gem it gets
today.

## Verdict

**Ship three platform gems with SDL2 compiled statically into `core_ext`, and
keep the source gem as the fallback.**

- `arm64-darwin`, `x86_64-linux-gnu` and `x64-mingw-ucrt` each get a gem with
  both extensions precompiled for Ruby 4.0.
- SDL2 is built in CI from a pinned source release, as a static archive, and
  linked into `core_ext`. Nothing is left for the loader to find.
- OpenGL stays dynamic. It is part of the OS on all three platforms.
- Every other platform, and every Ruby other than 4.0, installs the source gem
  and compiles against a system SDL2, as now.

Static linking is not a new idea in this project. `ext/rgame_core/vendor/`
already compiles miniaudio, stb_image, stb_truetype and stb_vorbis into
`core_ext`. SDL2 is the one third-party library left outside it, and this plan
brings it in.

## Hard constraints

1. **The source gem does not change.** `gem build rgame.gemspec` produces the
   same file list as today, it still compiles against a system SDL2, and
   `spec/packaging_spec.rb` holds without edits to its expectations.
2. **`require "rgame"` loads no graphics library.** Static SDL2 goes into
   `core_ext` only. `util_ext` and `spec/rgame/no_graphics_spec.rb` stay as they
   are.
3. **The version has one home**, `lib/rgame/version.rb`. No platform gem, tag,
   job or script spells it a second time.
4. **`.github/workflows/ci.yml` keeps its name.** RubyGems trusted publishing is
   registered against it.
5. **No new runtime dependency.** `rake-compiler` is a development gem.
6. **Every action stays pinned to a commit SHA**, as `ci.yml` explains.
7. **A platform gem compiles nothing at install time.** It ships no `.c` and no
   `extconf.rb`, and declares no extensions.
8. **Nothing in a release depends on someone remembering a step.** The task
   that builds a platform gem also checks it; the job that publishes derives the
   platform list rather than reading it from a person.

## Decisions already taken

These are settled. Do not re-open them inside this plan.

1. **Shipping binaries that still need a system SDL2 is ruled out.** This was
   shape A in the sketch. It removes the compiler requirement and leaves the
   SDL2 hunt, which is the part a non-developer cannot do.
2. **Three platforms, chosen as "modern desktop computers and laptops"**:
   Apple Silicon Macs (`arm64-darwin`), and x86-64 machines running Linux
   (`x86_64-linux-gnu`) or Windows (`x64-mingw-ucrt`). Intel Macs, ARM Linux,
   musl Linux and Windows on ARM fall back to the source gem for now.
3. **SDL2 is linked statically, not bundled as a shared library.** Of the two
   shapes left after decision 1, this is the one that needs no loader
   configuration. See [Bundling a shared SDL2](#bundling-a-shared-sdl2-beside-the-extension)
   for the rejected one.
4. **SDL2 comes from a pinned upstream release, fetched and checksummed at build
   time.** It is not vendored into `ext/`. See
   [Vendoring the SDL2 source](#vendoring-the-sdl2-source-into-ext).
5. **SDL2, not SDL3.** The engine is written against SDL2. Porting to SDL3 is a
   separate decision with its own plan, and nothing here makes it harder.
6. **Ruby 4.0 only.** `required_ruby_version` is `>= 4.0` and 4.0 is the only
   released ABI that satisfies it. A platform gem declares an upper bound, so a
   Ruby 4.1 user gets the source gem instead of a binary that cannot load.
7. **The macOS binaries target macOS 11.0, the oldest macOS that runs Ruby 4.0
   on Apple Silicon.** A platform gem should never rule out a Mac that Ruby
   itself runs on. Ruby 4.0's `configure.ac` accepts any target from OS X 10.5,
   and Apple Silicon starts at 11.0. Without a target, the build machine sets the
   floor: setup-ruby's Ruby is built for 14.0, and `macos-latest` runs 26. Taken
   in conversation on 2026-09-15, when step 3 was re-planned.

## What this does not deliver

- Binaries for Intel Macs, ARM Linux, musl Linux or Windows on ARM.
- Binaries for Ruby 4.1. That waits on Ruby 4.1 existing (open question 2).
- A way to ship a *game* to players — an app bundle, an installer, a single
  executable. A platform gem removes the compiler from a developer's setup. It
  does not package anyone's game.
- A change to the engine's SDL usage, or a move to SDL3.
- Any change to how `rake spec` and `rake spec:core` run in the existing test
  matrix. They keep testing the source-gem path against system SDL2.

## What was measured before planning

Taken at `78f462e`, on this machine (Ubuntu 22.04, x86-64) unless the row says
otherwise.

| Measured | Result |
|---|---|
| Source gem size, `gem build rgame.gemspec` | 1.63 MB |
| `lib/rgame/core_ext.so` / `util_ext.so` | 2.37 MB / 0.19 MB |
| `ldd core_ext.so` | 61 lines, including `libSDL2-2.0.so.0` and, through it, X11, Wayland, libdecor, PulseAudio, ALSA, libsndfile, libFLAC, libvorbis, libsystemd |
| `ldd util_ext.so` | libruby, libm, libc and libruby's own dependencies — no graphics |
| glibc on this machine | 2.35 |
| SDL2 on this machine | 2.0.20 (`libsdl2-dev`; ships `libSDL2.a` too) |
| SDL2 on the macOS CI leg | sdl2-compat over SDL3 (see the comment in `ci.yml`) |
| SDL2 on the Windows CI leg | MSYS2 `mingw-w64-ucrt-x86_64-SDL2` |
| Latest SDL2 release | `release-2.32.10`, source tarball 7.6 MB |
| Distinct `SDL_*` functions called from `ext/rgame_core` | 34 |
| rake-compiler-dock 1.12.0 (2026-04-15) | images for `arm64-darwin`, `x86_64-darwin`, `x86_64-linux-gnu`, `x64-mingw-ucrt` and more; cross-compiles Ruby 4.0.2 |
| nokogiri 1.19.4, sqlite3 2.9.6 | both publish `x86_64-linux-gnu`, `arm64-darwin` and `x64-mingw-ucrt` gems, among others |
| `tools/drive_test_project.rb:514` | puts the checkout's `lib/` first on the load path |

Three findings shape the plan:

- **The three platforms run three different SDL implementations today.** A
  pinned static SDL2 makes the platform gems run the same one everywhere.
- **The distro's `libSDL2.a` does not solve Linux.** It has no non-PIC
  relocations, so it would link into a `.so`. But it is 2.0.20, built against
  this distribution's glibc, and Homebrew's `sdl2` is now a shim over SDL3. A
  pinned build of our own is the only source that is the same on all three.
- **The drive harness cannot test an installed gem yet.** It prepends the
  checkout's `lib/`, so a smoke test run through it would test the checkout.
  Step 4 has to change that.

## What already resembles this

**Reuse it:**

- The toolchain setup in `ci.yml`'s test job: Homebrew on macOS, `ridk` and the
  UCRT64 `PATH` fix on Windows, Mesa next to `ruby.exe`.
- `HeadlessDisplay`, and the drive harness's report, for proving an installed
  gem draws.
- The release job's changelog gate and trusted publishing.

**Extend or generalize it:**

- **`ext/rgame_core/vendor/`.** It already answers "how does a third-party
  library get into `core_ext`": compile it in. Static SDL2 is the same answer
  for a library too large for one translation unit. This is the reason for
  decision 3.
- **`spec/packaging_spec.rb`.** It answers "does the gem ship exactly what it
  must" for the source gem. A platform gem asks the same question about a
  different artifact, so its checker states rules in the same shape and reads
  the built `.gem` rather than the gemspec object.
- **The release job's "is this version published?" check.** Today it asks
  whether a version exists. It becomes a set difference over
  `(version, platform)` pairs.
- **The test matrix.** A build job needs the same per-platform setup steps. They
  move into a local composite action rather than being copied.
- **The drive harness.** It learns to load the gem as installed.

**Genuinely new:**

- **Building a third-party library with its own build system.** Everything in
  `vendor/` is a single file mkmf compiles. SDL2 needs CMake.
- **Producing a platform-specific artifact.** Nothing in the project builds a
  file whose correctness depends on which machine built it. That is why the
  checker and the clean-machine smoke test exist.

## Prior art

### Gosu

Gosu 1.4.6 (2023-05-20) ships **one source gem**. It compiles its C++ on every
install. Its last platform gems were 0.15.2 (2020-06), for `x64-mingw32` and
`x86-mingw32`.

Per platform, from its `ext/gosu/extconf.rb` and `lib/gosu.rb`:

- **Windows:** the gem carries a prebuilt `SDL2.dll` in `lib/` and `lib64/`,
  plus import libraries. `lib/gosu.rb` calls
  `RubyInstaller::Runtime.add_dll_directory` before requiring the extension,
  falling back to prepending `PATH`. Windows would not find the DLL next to the
  extension on its own.
- **macOS:** it links Homebrew's `libSDL2.a` statically when that file exists,
  at a hardcoded Homebrew path.
- **Linux:** system packages through pkg-config — SDL2, vorbisfile, sndfile,
  mpg123, fontconfig.
- Smaller libraries — SDL_sound, mojoAL, utf8proc — ship as source and compile
  into the extension, like our `vendor/`.

### Ruby2D

Ruby2D 1.0.0 (2026-08-07) also ships **one source gem**, of 34 MB. It moved to
SDL3 in that release.

- The gem carries **prebuilt static archives** — `libSDL3.a`, `_image`,
  `_mixer`, `_ttf` and `libmruby.a` — for `macos-arm64`,
  `windows-x86_64-mingw-ucrt` and `windows-arm64-mingw-ucrt`. `extconf.rb`
  links them into the extension at install time.
- No Linux archives and no Intel Mac archives. Linux uses system SDL3.
- With no SDL3 anywhere, `extconf.rb` writes an empty `Makefile`, installs
  without the extension, and tells the user to run `ruby2d setup`, which builds
  the libraries into a user cache.
- `assets/deps.yaml` pins each SDL library to an upstream tag.
- The macOS link line names thirteen frameworks by hand, under a comment saying
  the list must match another file. That is a remembered rule, and step 2
  avoids it by reading the link flags from SDL's own `sdl2.pc`.

Ruby2D 0.12.1 (2023) did the same with SDL2 and a universal macOS build, in a
51 MB gem.

### nokogiri and sqlite3

These two are prior art for the mechanism, not the domain. Both publish platform
gems for all three of our targets, built with rake-compiler-dock. Both compile a
vendored C library statically into the extension and keep a source gem as the
fallback. That is decision 3 applied to libxml2 and SQLite.

### What none of the game engines gives us

**Neither Gosu nor Ruby2D installs without a compiler.** Both reduce the SDL
problem — a bundled DLL, prebuilt static archives — and then compile their own
extension on the user's machine. On Windows that still means a RubyInstaller
with the MSYS2 DevKit. Ruby2D's platform choice matches ours at the top — Apple
Silicon and x64 Windows first — and stops short of Linux.

## Considered and rejected

### Binaries that link a system SDL2

Ruled out by decision 1. It removes the compiler and keeps the SDL2 install.
On macOS the binary would also record Homebrew's absolute path to
`libSDL2-2.0.0.dylib`, so it would break on any Mac without Homebrew at that
prefix.

### Bundling a shared SDL2 beside the extension

*Attractions:* SDL2 stays a separate file that could be swapped. Gosu does this
on Windows today.

*Why not:* it needs a different loader mechanism on each platform, and each one
fails only on someone else's machine.

- **macOS:** rewrite the install name to `@loader_path`, then re-sign, because
  `install_name_tool` invalidates the signature arm64 requires.
- **Linux:** set an `$ORIGIN` rpath.
- **Windows:** the sketch said placing `SDL2.dll` next to the extension is
  enough. Gosu does not rely on that. It calls
  `RubyInstaller::Runtime.add_dll_directory` first, the call RubyInstaller
  documents for gems that bundle DLLs, and falls back to editing `PATH`.

A static SDL2 has none of these steps, and matches how `vendor/` already works.

### Ruby2D's shape: static archives inside the source gem

*Attractions:* one gem file, no platform matrix on RubyGems, and the extension
is still built against the user's exact Ruby.

*Why not:* it keeps the compiler requirement, which is the harshest part on
Windows. The gem also grows by the archives of every platform, for every user.

### Vendoring the SDL2 source into `ext/`

*Attractions:* it follows the `vendor/` convention, and builds need no network.

*Why not:* `spec.files` globs `ext/**/*`, so the source gem would ship SDL2's
source to users who compile against a system SDL2 and never read it. Excluding
it would add a special case to the glob that constraint 1 and the packaging
spec exist to prevent. A pinned tarball with a checksum is reproducible without
living in the tree.

### rake-compiler-dock for all three platforms

*Attractions:* one Linux job builds everything, it is what nokogiri and sqlite3
use, and its Linux image targets an old glibc. The sketch's claim that it has no
macOS image is wrong: 1.12.0 has `arm64-darwin`.

*Why not, for macOS and Windows:* the smoke test needs native runners anyway,
`ci.yml` has already proven the native toolchains, and cross-compiling SDL2
against a redistributed macOS SDK puts one more layer between us and the
frameworks. **For Linux it is the right answer**, because of the glibc floor;
see [Linux build environments](#linux-build-environments).

## Roadmap

```
0 measure ─→ 1 virtual gamepad ─→ 2 static SDL2 ─→ 3 platform gem ─→ 4 smoke test ─→ 5 release ─→ 6 install docs ─→ 7 fold back
```

Two steps are worth landing even if the plan stops after them:

| Step | Defect it closes |
|---|---|
| 1 | The Core specs reach SDL by filename, so they can drive a different SDL from the engine's without failing loudly |
| 2 | The three CI legs run three different SDL implementations |

> **A platform gem installs and draws on a machine with no compiler and no
> SDL2, and its `core_ext` names no SDL library among its dynamic
> dependencies.**

Step 2 establishes the second half with a linkage check. Step 4 establishes
the first half with a smoke test. Every later step keeps both green.

### Step 0 — Measurements: static SDL2 on each platform *(measurement only)*

**Why first:** the shape of steps 2 and 3 rests on facts that reading cannot
settle. This step changes no code. It lands as an update to this
plan.

Build SDL2 2.32.10 by hand, statically and position-independent, then build
`core_ext` against it on each of the three machines:

```
cmake -S SDL2-2.32.10 -B build/sdl2-build -DCMAKE_BUILD_TYPE=Release \
      -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_STATIC_PIC=ON -DSDL_TEST=OFF \
      -DCMAKE_INSTALL_PREFIX=build/sdl2
cmake --build build/sdl2-build && cmake --install build/sdl2-build
PKG_CONFIG_PATH=build/sdl2/lib/pkgconfig pkg-config --static --libs sdl2
```

Record, per platform:

1. **The dynamic dependency list** of the resulting `core_ext` (`ldd`,
   `otool -L`, `objdump -p`), and whether any SDL library is in it.
2. **Whether `rake spec:core` passes** against the static SDL2, and the skip
   count against the source-gem leg.
3. **Whether SDL symbols are exported** from `core_ext` (`nm -D --defined-only`,
   `nm -gU`, the PE export table). An exported `SDL_Init` could collide with
   another SDL loaded into the same process by some other gem.
4. **Linux only: the glibc floor.** Build once on `ubuntu-latest` and once in
   the rake-compiler-dock `x86_64-linux-gnu` image. Record the highest
   `GLIBC_` version each binary requires (`objdump -T | grep GLIBC_`), and
   whether SDL's X11 and Wayland backends build in the image — SDL needs their
   headers at build time even though it `dlopen`s them at runtime.
5. **Linux only: whether audio and display still work** with nothing but the
   runtime libraries a desktop has — run an example under X11 and under Wayland
   on this laptop with `libsdl2-2.0-0` removed from the loader's reach.
6. **Windows only: the CMake generator** that builds SDL2 with the UCRT64 gcc
   `ci.yml` puts on `PATH`.
7. **The `Gem::Platform.local` string** each Ruby 4.0 reports, compared to the
   three names in decision 2.

**Verify:** this plan's step 0 section holds a table with one column per
platform and a row per item above, and steps 2 and 3 are rewritten to match it.

**Landed.** All three platforms measured on 2026-09-15, each on its own
machine. Two things came out differently from the sketch. Item 4 needed Docker
on the Linux laptop, because `ubuntu-latest` and the rake-compiler-dock image
cannot be compared by reading. And the results overturned more than link flags:
the `extconf.rb` sketch called `pkg_config` in a form that sets no flags, and no
single lookup let the spec harness find the engine's SDL on every platform. The
second became a step of its own, step 1.

#### Results

| | Linux (x86-64) | macOS (Apple Silicon) | Windows (x64-mingw-ucrt) |
|---|---|---|---|
| Machine | Ubuntu 22.04, glibc 2.35, Intel Xe, Wayland session; Ruby 4.0.5 from mise, shared libruby; RubyGems 4.0.19 | macOS 27.0 (26A428), Apple clang 21.0.0, Ruby 4.0.5 | RubyInstaller Ruby with MSYS2 UCRT64 |
| Toolchain | gcc 11; CMake 4.4.3 from Kitware's release tarball, since the machine had none | `brew install cmake`, nothing else | gcc 16.2.0, cmake 4.4.2, ninja 1.13, mingw32-make 4.4.1. `ci.yml` installs none of cmake, ninja or make today |
| SDL2 tarball SHA-256 | `5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165` on all three | same | same |
| SDL2 build | 24 s on 8 cores | — | — |
| 1. `core_ext`'s dynamic dependencies | libruby.so.4.0, libm, libGL, libc, ld-linux. **No SDL.** `ldd` lists 17 lines, against 61 for the source build | OS frameworks only (CoreVideo, Cocoa, IOKit, ForceFeedback, Carbon, CoreAudio, AudioToolbox, AVFoundation, Foundation, OpenGL, AppKit, CoreFoundation, CoreGraphics, CoreServices; GameController, Metal, QuartzCore and CoreHaptics weak), plus libruby, libobjc and libSystem. **No SDL.** The system-SDL2 build links Homebrew's `sdl2-compat` dylib | ADVAPI32, GDI32, IMM32, KERNEL32, nine `api-ms-win-crt-*` forwarders, ole32, OLEAUT32, OPENGL32, SETUPAPI, SHELL32, USER32, VERSION, WINMM, `x64-ucrt-ruby400.dll`. **No SDL.** The dynamic build imported most of these through `SDL2.dll`; all ship with Windows |
| 2. `rake spec:core`, static build | 405 examples, **3 failures**, 2 excluded. With the harness pointed at `DEFAULT`: **407, 0 failures**. `rake spec`: 2313, 0 | **396, 0 failures, 0 pending** — see open question 7 | 396 examples, **4 failures**: 3 virtual gamepad, 1 `docs/api` reference failure unrelated to SDL. Reproduced twice |
| 2. `rake spec:core`, source build | 407, 0 failures | 396, 0 failures, 0 pending | 398, 1 failure — the same `docs/api` failure |
| 3. Exported `SDL_*` symbols | **839**, plus the 1394 others the source build already exports, mostly miniaudio's `ma_*`. `-Wl,--exclude-libs,ALL` hides all 839 | **0** reported by `nm -gU core_ext.bundle \| grep SDL_` — contradicted by item 2; see open question 7 | **0** in either build. mkmf's `core_ext-x64-mingw-ucrt.def` exports only `Init_core_ext` |
| 4. glibc floor | **GLIBC_2.29** from the rake-compiler-dock image, 2.34 from this laptop, 2.38 from `ubuntu-latest`; see [Linux build environments](#linux-build-environments) | n/a | n/a |
| 4. Display backends in the build | X11, Wayland, libdecor, KMSDRM and udev, all `*_SHARED=ON`, so `dlopen`ed. `SDL_STATIC_PIC` works: 0 `R_X86_64_32`/`32S` relocations in the archive | n/a | n/a |
| 5. A real window, no system SDL | 60 frames under each driver, Mesa Intel hardware GL, no `libSDL2` mapped into the process. Default and `x11`: X11 through XWayland. `wayland`: Wayland with libdecor. Audio: miniaudio on PulseAudio | Not run separately. `rake spec:core` opens real windows on the native display against the static bundle | — |
| 6. CMake generator | n/a | n/a | With `ninja.exe` on `PATH`, CMake picks **Ninja** without `-G`. `-G "MinGW Makefiles"` also builds, despite `sh.exe` on `PATH` |
| 7. `Gem::Platform.local` | `x86_64-linux`; a gem tagged `x86_64-linux-gnu` matches it (`Gem::Platform.match_gem?`), `-musl` does not | `arm64-darwin-25`; the trailing digit is Darwin's kernel major, and RubyGems groups it under `arm64-darwin` | `x64-mingw-ucrt`, exactly decision 2's name |
| `sdl2.pc` link flags | `-lSDL2 -pthread -lm`, all in `Libs`; no `Libs.private`, because SDL `dlopen`s every system library | `Libs` holds `-lSDL2 -lm`; `Libs.private` holds the frameworks | Everything in `Libs`; `Libs.private` empty |
| `pkg_config('sdl2', 'static')` in mkmf | — | **Sets no flags.** With options, `pkg_config` returns a string and changes no globals, as its doc comment in `mkmf.rb` says | Plain `pkg_config('sdl2')` already returns the full link line |
| `core_ext` size | 4.89 MB, 3.09 MB stripped, 1.24 MB gzipped; source build 0.90 MB stripped | — | 849 KB dynamic → 3.14 MB static |
| `-DSDL_AUDIO=OFF -DSDL_RENDER=OFF` | `libSDL2.a` 4.11 → 3.67 MB, `core_ext` 4.89 → 4.59 MB; 407, 0 failures; window probe unchanged | — | — |

**Finding A — the virtual gamepad drives a second SDL.**
`spec_core/support/virtual_gamepad.rb` reaches SDL through Fiddle by filename:
`libSDL2-2.0.so.0` on Linux, `SDL2.dll` on Windows. Against a static build, both
names still open *something*. On Linux it is the system SDL. On Windows it is
RubyInstaller's MSYS2 copy, `C:\msys64\ucrt64\bin\SDL2.dll`, which Ruby's own
DLL-directory mechanism reaches even with no `msys64` on `PATH`
(`GetModuleFileNameW`). Either way the virtual pad plugs into a copy the engine
never sees, and hot-plug examples fail with `expected 1, got 0` rather than an
error. On Linux `button_state_supported?` probes the same wrong copy, which is
why two examples are excluded rather than failing.

`Fiddle::Handle::DEFAULT`, which macOS already uses, fixes Linux for both builds
(407, 0 failures) — but only because Linux exports SDL's symbols. It cannot fix
Windows, where a static `core_ext` exports none. No lookup works everywhere, so
[step 1](#step-1--rgamecorevirtualgamepad-moves-into-the-extension) moves the
harness into the extension.

**Finding B — a native build links the building machine's libruby.** Built on a
Ruby with a shared libruby, *both* extensions record `NEEDED libruby.so.4.0` and
a `RUNPATH` of `/home/paul/.local/share/mise/installs/ruby/4.0.5/lib`. That is
mkmf's `LIBRUBYARG_SHARED` and `LIBPATH`. A gem shipped like this points at a
path on the build machine, and fails to load on a Ruby with no `libruby.so.4.0`
by that name. nokogiri's binary has neither entry. Relinking with both variables
emptied leaves libm, libGL and libc, Ruby's symbols resolve from the running
process, and both suites still pass. The macOS bundle lists libruby too. Step 3
handles it.

**Finding C — SDL's audio and 2D renderer are dead weight.** `app.c:103`
initialises `SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER` only. Audio is
miniaudio, and drawing is our own GL. Turning both off saves 0.3 MB, 6% of
`core_ext`, breaks nothing, and drops SDL's PulseAudio, ALSA and sndio backends.
Step 2a does it.

#### Linux build environments

**Build Linux in the rake-compiler-dock image.** Measured 2026-09-15 at
`fa89336`. The same SDL2 2.32.10 (audio and renderer off) and both extensions
were built three ways, and the binaries were loaded into this laptop's Ruby
4.0.5:

| | This laptop | `ubuntu-latest` | rake-compiler-dock |
|---|---|---|---|
| How it was built | `make ext` | `ubuntu:24.04` container with setup-ruby's own `ruby-4.0.5-ubuntu-24.04-x64` tarball at `/opt/hostedtoolcache` | `rake compile:x86_64-linux-gnu` in `1.12.0-mri-x86_64-linux-gnu` |
| OS, glibc, compiler | Ubuntu 22.04, 2.35, gcc 11 | Ubuntu 24.04.4, 2.39, gcc 13.3, cmake 3.28 | Ubuntu 20.04.6, 2.31, gcc 9.4, cmake 3.16, cross Ruby 4.0.2 |
| `core_ext` needs | **GLIBC_2.34** | **GLIBC_2.38**: `__isoc23_strtol` and six other `__isoc23_*`, `strlcpy`, `strlcat`, `wcslcpy`, `wcslcat`, `fmod`, `fmodf` | **GLIBC_2.29**: `exp`, `log`, `pow` |
| libruby and runpath | `NEEDED libruby.so.4.0`, runpath into mise | `NEEDED libruby.so.4.0`, runpath `/opt/hostedtoolcache/Ruby/4.0.5/x64/lib` | **neither** |
| Other `NEEDED` | libm, libGL, libc, ld-linux | libm, libGL, libc, ld-linux | libdl, libpthread, libm, libGL, libc, ld-linux — pre-2.34 names, which newer glibc keeps as stubs |
| `core_ext` size | 4.59 MB | 4.80 MB | 2.61 MB, stripped by the cross Ruby's `LDFLAGS` |
| SDL's libdecor support | on | on | **off**: Ubuntu 20.04 has no `libdecor-0-dev` |
| Loads on this laptop | yes | **no**: ``version `GLIBC_2.38' not found`` | yes |
| `rake spec` / `rake spec:core` here | 2313, 0 / 407, 0 | — | 2313, 0 / 407, **1 failure** (finding D) |
| Window probe, X11 and Wayland | both, 60 frames | — | both, 60 frames, no system SDL mapped |

`ubuntu-latest` is out: its binary does not load on Ubuntu 22.04 or Debian 12.
The rake-compiler-dock image gives the lowest floor and avoids finding B. It
runs rake-compiler's own cross tasks, which step 3 uses anyway. A plain
Ubuntu 20.04 container would give the same glibc, but neither the static-libruby
cross Ruby nor the tasks.

GLIBC_2.29 admits Ubuntu 20.04+, Debian 11+ and Fedora 30+. The kit that ran
these builds is not in the repo. Step 2e rebuilds it as a CI job.

**Finding D — `audio_spec.rb:112` fails against the rake-compiler-dock
binary, and it is not a leak.** "`debug_live_sounds` returns to its baseline"
expects 0 and gets 1, in 10 of 10 runs; the local build passes 10 of 10. Outside
RSpec the same binary returns to 0 after 10, 100 and 500 sample and song pairs,
from the same frame and from 50 frames deeper. So one sound stays reachable only
from a stale reference on the C stack, which Ruby's conservative GC honours. The
image compiles with gcc 9.4 against the local gcc 11, and its cross Ruby was
itself built with `-O1`. Either can change what stays on the stack. Which one it
is was not measured, because the container's make ran without `V=1`. The spec's
question is whether sounds leak, so it should assert the count does not *grow*
across many allocations. Step 2c fixes the spec.

**Finding E — no libdecor from the image.** Under native Wayland on GNOME,
which draws no server-side decorations, a window without libdecor has no title
bar. SDL2 picks X11 by default, through XWayland, so this is only visible with
`SDL_VIDEODRIVER=wayland`. The probe window under Wayland opened and ran either
way. Building libdecor from source in the image is possible. It is not worth
doing until someone asks for native Wayland.

### Step 1 — `RGame::Core::VirtualGamepad` moves into the extension

**Why here:** step 2's CI job runs `rake spec:core` against a static build, and
the gamepad specs cannot pass there while the harness finds SDL by filename
(finding A). It is also worth landing on its own: today the harness only works
because a filename happens to name the right copy of SDL.

**The spec harness stops reaching SDL through Fiddle.** Step 0 found no filename
or lookup that finds the engine's own SDL everywhere:

| | Static build | Source build |
|---|---|---|
| Linux | `DEFAULT` finds it, because static SDL's symbols are exported | `DEFAULT` finds it |
| Windows | Nothing finds it. Only `Init_core_ext` is exported, and `dlopen('SDL2.dll')` opens RubyInstaller's MSYS2 copy | `SDL2.dll` |
| macOS | Contradictory; see open question 7 | `DEFAULT` finds it |

So the 13 SDL calls the harness makes go into C, where they can only reach the
SDL that `core_ext` itself links:

```c
/* ext/rgame_core/ruby/virtual_gamepad_ext.c
 *
 * RGame::Core::VirtualGamepad — a synthetic controller, for specs. Test-only
 * and named so, like Audio.debug_live_sounds. It lives in the extension because
 * that is the only place guaranteed to call the SDL the engine runs on, whether
 * SDL is linked statically or dynamically. */
void rgame_init_virtual_gamepad(VALUE mCore);
```

The Ruby surface keeps what the harness offers today — `new`, `press`,
`release`, `move_axis`, `raw_down?`, `game_controller?`, `attached?`,
`detach` and `button_state_supported?` — so the gamepad and input specs change
only their `require`. `spec_core/support/virtual_gamepad.rb` and its Fiddle
table are deleted. The class is tagged `@api private` for the documentation
coverage spec.

This costs a test-only class in the shipped gem. Every alternative is
per-platform: a `.def` file exporting SDL functions on Windows, `DEFAULT`
elsewhere, and a list of names that has to match the harness by hand.

**Rules the tests pin:**

1. A virtual pad attached through the class raises the engine's own hot-plug
   callbacks, whether SDL is linked statically or dynamically.
2. `button_state_supported?` probes the same SDL the engine runs on.
3. Nothing under `spec_core/` calls `Fiddle` to reach SDL.

**Tests:** the existing `spec_core/rgame/core/gamepad_spec.rb` and
`input_spec.rb` hot-plug and pad-press examples, unchanged apart from their
`require`.

**Verify:** the `test` job is green on all three platforms, with the same
example and skip counts as before the change. On the Linux laptop, the same
examples also pass against a static build — the case that fails today.

**Landed.** `RGame::Core::VirtualGamepad` is C: `input/virtual_gamepad.c` makes
the SDL calls, `ruby/virtual_gamepad_ext.c` binds them, and `core.h` declares
the handle. Its Ruby surface is the device only — `new`, `set_button`,
`set_axis`, `button_down?`, `game_controller?`, `attached?`, `detach`, and the
class methods `pump` and `sdl_error`. `docs/api/input.md` documents it.

Measured on the Linux laptop:

| | Result |
|---|---|
| `make test` | 363 checks, 0 failures |
| `rake spec` | 2313 examples, 0 failures |
| `rake spec:core`, source build | 410 examples, 0 failures, nothing excluded — the 407 from before plus 3 new |
| `rake spec:core`, static SDL2 build | 410 examples, 0 failures, nothing excluded, no `libSDL2` mapped. Step 0 measured 405, 3 failures, 2 excluded on the same build |
| `rake docs:coverage` | 0 of 132 modules and classes undocumented |
| `drive_test_project.rb examples/radial_menu/main.rb --gamepad --script …/radial_menu_pad.rb --ticks 240 --seed 1 --texts` | byte-identical report before and after |

What the sketch got wrong:

- **`spec_core/support/virtual_gamepad.rb` stayed.** The sketch deleted it and
  gave the C class the harness's whole surface. But the harness also waits for a
  press to land and probes, in a child process, whether presses land on this
  machine — spec machinery the gem has no reason to ship. So the C class is the
  device, and the support file keeps its public surface and calls the C class
  instead of Fiddle. The specs did not change at all, not even their `require`.
- **A third user.** `tools/drive_test_project.rb --gamepad` drives the same
  harness. Keeping the harness's surface is what left it untouched.
- **SDL can shut down under a pad.** `app.c` calls `SDL_Quit` when the last App
  is destroyed, which frees every joystick, so a pad that outlives every App held
  a dangling pointer. `app/sdl_session.h` numbers each run of SDL. A pad records
  its run, raises `RuntimeError` once SDL has shut down, and its `detach` does
  nothing then. Collecting a pad does not unplug it, because a GC-time unplug
  would raise a hot-plug event at an arbitrary frame. The Fiddle harness never
  unplugged on collection either.
- **`@api private` cannot tag a C-defined class.** The coverage spec reads the
  comment above a definition, and a C class reports its location as
  `core_ext.so`, line 0. So it is documented instead, the way
  `Audio.debug_live_sounds` is.
- **A press is not always readable straight away.** Outside an App's frame loop,
  a press set and updated read back only after one `pump`, measured. The
  harness's retry loop stays for that reason.
- **The device index is looked up, not stored.** SDL renumbers device indices
  when any device comes or goes, so `detach` and `game_controller?` find the
  current index from the joystick's instance id. The Fiddle harness kept the
  index from attach time.

Two documents stated things this made false, and were corrected: CLAUDE.md
called `gamepad.c` the one place `SDL_GameController` appears, and the
windows-portability skill held up by-name dlopen of SDL as finding the copy
already loaded.

Only the source build ran on macOS and Windows, through the pull request's CI.
The static build on those platforms waits for step 2's CI job.

### Step 2 — A static SDL2 build path for `core_ext`

**Why here:** everything after it packages this build, so it must be proven
first. It needs step 1, because its CI job runs the gamepad specs against a
static build. And it is worth landing on its own: it gives CI one pinned SDL2
on all three platforms, where today each runs a different one.

#### 2a. `rake sdl2` builds the pinned release

```ruby
# rakelib/sdl2.rake
SDL2_RELEASE = {
  version: '2.32.10',
  sha256: '5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165'
}.freeze

SDL2_PREFIX = File.expand_path('build/sdl2', __dir__)

desc 'Build the pinned SDL2 as a static, position-independent library'
task sdl2: "#{SDL2_PREFIX}/lib/pkgconfig/sdl2.pc"
```

It downloads the release tarball, refuses it on a checksum mismatch, and runs
the CMake invocation step 0 settled, adding `-DSDL_AUDIO=OFF -DSDL_RENDER=OFF`
(finding C). On Windows it passes `-G Ninja` rather than relying on CMake's
autodetection, which picked Ninja there only because `ninja.exe` happened to be
on `PATH`. The prefix sits under `build/`, which is already ignored and already
outside the gem.

#### 2b. `extconf.rb` links a static SDL2 when given one

```ruby
static_sdl2 = with_config('sdl2-static') # a prefix built by `rake sdl2`

if static_sdl2
  pc_dir = File.join(static_sdl2, 'lib/pkgconfig')
  abort "No SDL2 under #{static_sdl2}. Run: rake sdl2" unless File.exist?(File.join(pc_dir, 'sdl2.pc'))

  ENV['PKG_CONFIG_LIBDIR'] = pc_dir
  pkg_config('sdl2') or abort "pkg-config could not read #{pc_dir}/sdl2.pc"

  static_only = Shellwords.shellwords(pkg_config('sdl2', 'libs', 'static').to_s) - Shellwords.shellwords($libs)
  $libs += " #{static_only.shelljoin}" unless static_only.empty?
else
  abort 'SDL2 not found (pkg-config --exists sdl2 failed). Install libsdl2-dev.' unless pkg_config('sdl2')
end
```

Each line of the static branch answers something step 0 measured. The Linux
build ran this exact shape: 5 `NEEDED` entries, no SDL, and the source build
unchanged at 6.

- **`pkg_config` runs twice.** Called with options, mkmf's `pkg_config` returns
  a string and sets no flags (the macOS result, confirmed in `mkmf.rb`). So the
  first call sets the flags, and the second adds whatever `Libs.private` holds
  beyond them. On macOS that is the framework list — the one Ruby2D keeps by
  hand. On Linux and Windows it adds nothing, because a static-only build puts
  everything in `Libs`.
- **The second call stays inside the static branch.** Run against a system
  SDL2, `--static` asks for every library SDL could link. The source build then
  went from 6 `NEEDED` entries to 25 — X11, PulseAudio, Wayland, libdecor —
  which breaks constraint 1.
- **The prefix is checked by file before pkg-config runs.** When pkg-config
  finds no `sdl2`, mkmf quietly falls back to running `sdl2-config`. With
  `--with-sdl2-static=/nonexistent`, that found `/usr/bin/sdl2-config` and
  linked the *system* SDL dynamically, with no error.
- **`PKG_CONFIG_LIBDIR`, not `PKG_CONFIG_PATH`.** `LIBDIR` replaces the default
  search path rather than going in front of it, so no system `sdl2.pc` can
  answer instead.
- **Not mkmf's own `--with-sdl2-dir`.** It does point pkg-config at the prefix,
  but it also writes the prefix into the binary's `RUNPATH`, which would put
  another build-machine path in the gem (finding B, and step 3's rule 8).

Because the prefix holds only `libSDL2.a`, `-lSDL2` resolves to the archive,
and the system's `libSDL2.so` is never reached. That ordering is invisible in
the build output, which is why rule 1's linkage check exists.

#### 2c. The audio leak spec asserts no growth

`audio_spec.rb`'s "returns to its baseline" example allocates many sounds and
asserts the live count does not grow, rather than returning to exactly its
baseline from one frame. It fails against the rake-compiler-dock binary as it
stands (finding D).

#### 2d. The toolchain setup moves into a composite action

`.github/actions/toolchain/action.yml` takes the per-OS install, `ridk`, `PATH`
and Mesa steps out of the test job. The test job calls it unchanged. The new
job in 2e calls it too, so the Windows `PATH` fix exists once. It adds what
building SDL2 needs: `brew install cmake` on macOS, and
`mingw-w64-ucrt-x86_64-cmake` and `mingw-w64-ucrt-x86_64-ninja` on Windows,
neither of which `ci.yml` installs today.

#### 2e. A `static-sdl2` CI job

A matrix over the three runners, beside the existing `test` job:

```
rake sdl2 → make ext with --with-sdl2-static → rake spec:core → ruby tools/check_linkage.rb
```

`tools/check_linkage.rb` reads the platform's own dependency and export
listings for both extensions, and exits non-zero on a rule below. On Linux the
job builds SDL2 and the extensions inside the rake-compiler-dock
`x86_64-linux-gnu` image, through `rake compile:x86_64-linux-gnu`. It then runs
`rake spec:core` on the plain runner against the binaries it produced, because
the image has no display. That means the rake-compiler `ExtensionTask` from 3a
moves forward into this step on Linux.

**Rules the checks pin:**

1. `core_ext`'s dynamic dependencies name no SDL library.
2. `core_ext` exports no `SDL_` symbol. Windows meets this with no flag, because
   mkmf's `.def` file exports only `Init_core_ext`. Linux needs
   `-Wl,--exclude-libs,ALL`, which step 0 measured hiding all 839. macOS waits
   on open question 7. Hiding the symbols breaks nothing once step 1 has
   removed the Fiddle harness.
3. `util_ext`'s dynamic dependencies name no SDL and no GL library.
4. Without `--with-sdl2-static`, `extconf.rb` behaves exactly as before — the
   existing `test` job is the check.
5. A tarball whose checksum differs from `SDL2_RELEASE` fails `rake sdl2`
   before CMake runs.

**Tests:**

- `static-sdl2` job, all three platforms: `rake spec:core` green, skip count
  equal to the `test` job's on the same platform.
- `tools/check_linkage.rb` against the source-gem build on this machine: fails
  on rule 1, since that build links `libSDL2-2.0.so.0`. This proves the check
  can fail.

**Verify:** the `static-sdl2` job is green on all three platforms and the
`test` job is unchanged in what it runs.

**Landed.** `rake sdl2` builds the pinned release into `build/sdl2`. `extconf.rb
--with-sdl2-static=<prefix>` links it, and `make ext SDL2_STATIC=build/sdl2`
passes the option through. The `static-sdl2` job builds against it on all three
platforms, runs `rake spec:core` on a runner with no system SDL2, and runs
`tools/check_linkage.rb`. `ext/README.md` documents the two commands.

Measured in the pull request's CI, against the `test` job in the same run and
on `main`:

| | `test`, `main` | `test`, this branch | `static-sdl2` |
|---|---|---|---|
| Linux | 410, 0 failures, nothing excluded | the same | 410, 0 failures, nothing excluded |
| macOS | 399, 0 failures, 3 tags excluded | the same | 399, 0 failures, the same 3 tags |
| Windows | 401, 0 failures, 2 tags excluded | the same | 401, 0 failures, the same 2 tags |

`rake spec` went from 2313 to 2314 examples, the one new example being the
checksum refusal. On the Linux laptop: `make test` 363 checks, 0 failures;
`rake spec:core` 410, 0 failures against both builds; `rake docs:coverage` 0 of
132 undocumented.

What `tools/check_linkage.rb` reported:

| | `core_ext` needs | `SDL_` exports | `util_ext` needs |
|---|---|---|---|
| Linux, from the image | libdl, libpthread, libm, libGL, libc, ld-linux; **GLIBC_2.29** | 0 of 1407 | libpthread, libm, libc |
| macOS | 18 frameworks and libraries, no SDL; libruby from the runner's toolcache (finding B) | 0 of 1 | libruby, libSystem |
| Windows | 23 DLLs, each part of Windows or the Ruby DLL, no SDL | 0 of 1 | the Ruby DLL, KERNEL32 and CRT forwarders |

The check fails, as rule 1 requires, against this laptop's source build
(`libSDL2-2.0.so.0`), against step 0's image binary built without
`--exclude-libs` (839 `SDL_` exports), and with its two arguments swapped
(`util_ext` given a `libGL.so.1`). `rake sdl2` refuses a tarball with one byte
appended before anything unpacks it, and a spec pins the refusal. Finding D's spec
passes against the image's binary.

What the sketch got wrong:

- **macOS exports SDL.** Open question 7 is settled: the first CI run reported
  837 `SDL_` symbols in the static bundle. The static branch now links with
  `-Wl,-exported_symbol,_Init_core_ext` on macOS, and both platforms' flags go
  in *after* mkmf's checks. Added before them, every test program mkmf links
  lacks `Init_core_ext` and fails, so `have_framework('OpenGL')` reported the
  framework missing.
- **The rake-compiler tasks are not in the Rakefile.** Defining an
  `ExtensionTask` there makes rake-compiler warn about the objects `make ext`
  leaves in `ext/` on every `rake` run, `rake spec` included. The image also has
  no bundle, so the Rakefile's RSpec tasks cannot load there. They live in
  `tools/cross_compile.rake`, run as `rake -f tools/cross_compile.rake sdl2
  compile:x86_64-linux-gnu`. A cross build stages its binaries under `tmp/` and
  never writes `lib/rgame/`, so it does not collide with `make ext`. Step 3a
  still has to decide how a *native* `rake compile` and `make ext` share
  `lib/rgame/`.
- **The pin lives in `rakelib/sdl2_build.rb`, not `sdl2.rake`.** Rake loads
  `rakelib/*.rake` in name order, and the cross-compile rakefile needs
  `SDL2_PREFIX`. A plain Ruby file both can require removes the ordering.
- **rbenv in the image read `.ruby-version`.** Written as `ruby 4.0.5`, it is a
  form rbenv cannot parse, and rake refused to start. The job sets
  `RBENV_VERSION` to the image's global Ruby, and takes `RUBY_CC_VERSION` from
  the image's own list by `.ruby-version`'s minor.
- **Switching SDLs has to rebuild the extension.** The system SDL2 and the
  pinned one have different headers, so `make ext` records the configure option
  in `build/ext-core.config` and cleans the extension when it changes.
- **`make clean` deletes `build/sdl2`.** It removes all of `build/`. The next
  static build then aborts with "Run: rake sdl2", which is loud, but costs a
  download and a 30-second build.

The image is pinned by digest, `sha256:2f7eabb0…`, like the actions are pinned
by commit.

### Step 3 — `platform_gem` builds and checks a platform gem

**Why here:** the static build from step 2 exists, and a platform gem is that
build plus packaging. Publishing waits until step 4 has proven the gem on a
clean machine, so this step produces an artifact and publishes nothing.

**Re-planned 2026-09-15**, after step 2 landed. The earlier sketch put
rake-compiler's tasks in the Rakefile. It left open how a native build and
`make ext` share `lib/rgame/`, and it expected rake-compiler to name a macOS gem
correctly. Step 2 moved the tasks out of the Rakefile, and the measurements
below settle the rest. The macOS deployment target is decision 7.

| Measured | Result |
|---|---|
| rake-compiler 1.3.1, native build (read from `extensiontask.rb`) | Writes `required_ruby_version` `>= 4.0, < 4.1.dev` from the building Ruby, as a cross build does. Names the gem after `RUBY_PLATFORM`, installs both binaries into `lib/rgame/`, and stages every file the gemspec lists, `ext/` included |
| A Darwin version in the platform name | `arm64-darwin-25` does not match a Mac reporting `arm64-darwin-24` (`Gem::Platform#===`); `arm64-darwin` matches both. Step 0's Mac reported `arm64-darwin-25`; setup-ruby's Ruby reports `arm64-darwin23` |
| `make ext`'s objects left in `ext/`, then a rake-compiler build of `util_ext` | make finds the objects through VPATH, compiles nothing, and the link fails with `cannot find color.o`. rake-compiler only prints a warning first |
| setup-ruby's macOS Ruby 4.0.5 (`ruby-4.0.5-darwin-arm64.tar.gz`) | `LIBRUBYARG` is `-lruby.4.0`, `DLDFLAGS` holds `-Wl,-undefined,dynamic_lookup`, `RPATHFLAG` is empty. `ruby` and `libruby.4.0.dylib` are built for macOS 14.0, SDK 14.5 |
| `$LIBRUBYARG` emptied and `$(libdir)` removed from `$DEFLIBPATH`, on this laptop | `util_ext` loses `NEEDED libruby.so.4.0` and its runpath, and still loads |
| Ruby 4.0.5's `configure.ac` on Darwin | Refuses a deployment target older than OS X 10.5, and sets no newer floor |
| Apple Silicon's first macOS | 11.0 |

#### 3a. `tools/platform_gem.rake` builds both extensions on all three platforms

`tools/cross_compile.rake` becomes `tools/platform_gem.rake`. It picks this
machine's platform and defines one task that builds its gem:

```ruby
# tools/platform_gem.rake
module PlatformGem
  EXTENSIONS = { 'rgame_util' => 'util_ext', 'rgame_core' => 'core_ext' }.freeze

  PLATFORM = case RbConfig::CONFIG['host_os']
             when /linux/ then 'x86_64-linux-gnu'
             when /darwin/ then "#{Gem::Platform.local.cpu}-darwin"
             else Gem::Platform.local.to_s
             end
end

Rake::ExtensionTask.new(name, gemspec) do |ext|
  ext.ext_dir = "ext/#{dir}"
  ext.lib_dir = 'lib/rgame'
  ext.config_options << '--disable-libruby-link'
  ext.config_options << "--with-sdl2-static=#{SDL2_PREFIX}" if name == 'core_ext'
  # Linux cross-compiles in the rake-compiler-dock image; macOS and Windows build natively.
end
```

```
rake -f tools/platform_gem.rake platform_gem    # pkg/rgame-<version>-<platform>.gem
```

- **Linux cross-compiles, macOS and Windows build natively.** A native build
  names its platform without the Darwin version, so the gem installs on every
  Apple Silicon Mac. An Intel Mac would get `x86_64-darwin`, which the checker
  refuses.
- **`make ext` stays the developer's command.** `platform_gem` refuses to start
  while `ext/` holds compiled objects, and names `make ext-clean`. That also
  makes a native build's copy into `lib/rgame/` harmless: `ext-clean` deleted
  the old binaries, so the next `make ext` builds and copies its own.
- **`--disable-libruby-link`** empties `$LIBRUBYARG` and removes `$(libdir)`
  from `$DEFLIBPATH`, in both `extconf.rb` files and after mkmf's checks.
  Windows ignores it, because a Windows extension must import the Ruby DLL.
- **macOS targets 11.0.** `rakelib/sdl2_build.rb` holds
  `MACOS_DEPLOYMENT_TARGET`. `rake sdl2` passes it to CMake on macOS, and the
  rakefile exports `MACOSX_DEPLOYMENT_TARGET` for the extensions.
- The Linux job keeps setting `RBENV_VERSION` and `RUBY_CC_VERSION` in `ci.yml`,
  because both must be set before rake starts.

#### 3b. The platform gem's specification

rake-compiler's `native:<platform>` task derives the specification from the
gemspec it is given. The rakefile gives it a copy of `rgame.gemspec` with other
files:

- **Files:** the source gem's files minus `ext/**`, plus
  `licenses/SDL2/LICENSE.txt`. The licence comes from the checksummed release
  `rake sdl2` installed, copied straight into the staging directory.
- **`extensions`:** rake-compiler clears them.
- **`required_ruby_version`:** rake-compiler writes `>= 4.0, < 4.1.dev`, from
  `RUBY_CC_VERSION` in the image and from the running Ruby elsewhere.
- **`required_rubygems_version`:** on Linux rake-compiler adds `>= 3.3.22`, the
  first RubyGems that tells a `-gnu` gem from a `-musl` one.

`gem build rgame.gemspec` never loads the rakefile, so the source gem does not
change (constraint 1).

#### 3c. `tools/check_platform_gem.rb`, run by `platform_gem`

`platform_gem` runs the checker on the `.gem` it just wrote and fails when a
rule breaks, so no one can build a platform gem without checking it. The checker
opens the `.gem` archive itself rather than asking a specification object. The
packaging spec's `.dSYM` example explains why: a check that shares the
derivation it guards shares its blind spots.

**Rules the checker pins:**

1. The platform is one of the three in decision 2.
2. It contains exactly one `core_ext` and one `util_ext` in `lib/rgame/`, with
   this platform's extension (`bundle` on macOS, `so` elsewhere).
3. It contains no `.c`, no `.h`, no `extconf.rb` and no `Makefile`, and
   declares no extensions.
4. `required_ruby_version` admits `.ruby-version`'s Ruby and excludes the next
   minor, prereleases included.
5. It contains SDL2's licence.
6. Its files are exactly the source gem's files outside `ext/`, plus rules 2
   and 5.
7. `tools/check_linkage.rb`'s rules hold for the extensions inside it.
8. On Linux and macOS, neither extension names libruby among its dependencies
   or carries an rpath or runpath (finding B).
9. Neither extension needs a newer OS than the gem claims: on macOS a minimum
   version no newer than `MACOS_DEPLOYMENT_TARGET`, and on Linux no symbol
   version newer than `GLIBC_2.29`.

`CheckLinkage::Listing` gains the runpaths and the minimum OS version. They come
from the tools step 2 already runs per platform, plus `otool -l` and `objdump
-T`, so rules 8 and 9 reuse its readers.

#### 3d. A `build-gem` job

`static-sdl2` becomes `build-gem`, and runs `platform_gem` where it ran
`rake sdl2` and `make ext`: inside the image on Linux, on the runner elsewhere.
Every leg then unpacks the gem's two binaries into `lib/rgame/` and runs
`rake spec:core` against them, so the Core suite tests the files that ship. The
job uploads the gem as an artifact. A `source-gem` job on Linux builds
`rgame.gemspec` and uploads that.

**Tests:**

- `spec/tools/check_platform_gem_spec.rb`: the checker, run on the source gem
  built into a temporary directory, reports rules 1, 2, 3 and 5 broken. This
  proves it can fail, and it runs in `rake spec`.
- `build-gem`, all three platforms: `platform_gem` passes, and `rake spec:core`
  reports step 2's example and skip counts.
- On this laptop, `platform_gem` with `make ext`'s objects in `ext/` stops before
  it compiles anything.
- `rake spec`, unchanged: `spec/packaging_spec.rb` still passes against
  `rgame.gemspec`, which is constraint 1.

**Verify:** a push produces four artifacts, three platform gems and the source
gem. Each platform gem passed the checker in the job that built it, and its
binaries passed `rake spec:core` there.

### Step 4 — A clean-machine smoke test

**Why here:** a gem that passes every check on the machine that built it can
still fail on a machine that did not. The checker proves what is in the file.
This step proves the file works where it lands.

#### 4a. The drive harness runs against an installed gem

`tools/drive_test_project.rb:514` prepends the checkout's `lib/`. It gains an
`--installed` switch that leaves the load path alone, and the report states
which `rgame` it loaded and from where — `$LOADED_FEATURES` for
`rgame/core_ext` — so a run cannot quietly test the checkout.

#### 4b. A `smoke` job per platform

It needs `build-gem`, runs on a fresh runner of the same OS, and does not run
the toolchain action:

```
download the platform gem
assert no SDL2 is installed (Linux: no libSDL2 known to ldconfig; macOS: no sdl2 in brew list)
gem install --local rgame-<version>-<platform>.gem
assert the install compiled nothing (no gem_make.out under the installed gem)
ruby tools/drive_test_project.rb --installed <the installed gem>/examples/collision/main.rb --ticks 120
```

The runner still gets a display and OpenGL: Xvfb and Mesa on Linux, Mesa next
to `ruby.exe` on Windows. A user's desktop has both. A runner does not, and
that is a property of CI, not of the gem.

**Rules the smoke test pins:**

1. The platform gem installs with no compiler step.
2. `rgame/core_ext` loads from the installed gem's directory.
3. A driven example draws: the report shows at least one draw call and exits 0.
4. The installed `rgame` command works: `rgame new` generates a project.

**Tests:** the `smoke` job itself, on all three platforms.

**Verify:** `smoke` is green on all three platforms, and a deliberately broken
gem fails it — for example, one built with step 2b's static branch removed,
installed on the Linux runner with no SDL2.

### Step 5 — The release job publishes every gem *(rough)*

- The job stops building and collects the four artifacts.
- "Is this version published?" becomes a set difference over
  `(version, platform)`, so a release that failed halfway picks up the missing
  gems on the next push.
- Platform gems push before the source gem. A user on a covered platform should
  never see the version as source-only.
- Tag and GitHub release happen once, after the last push.
- `needs:` gains `smoke`.
- Worth considering: publish a prerelease first, to see Bundler and RubyGems
  resolve the platforms for real (open question 1).
- `CHANGELOG.md` gets its entry here, because this is the step whose release
  users see.

### Step 6 — Install documentation *(rough)*

- `README.md`'s install section: on the three platforms, Ruby 4.0 and
  `gem install rgame` are enough. Everywhere else the requirements list stays.
- The release skill: what the job now publishes, and how to read a partial
  release.

### Step 7 — Fold the plan back and delete it *(rough)*

- CLAUDE.md's "Packaging" section: the two kinds of gem, why SDL2 is static,
  the checker and the smoke test, and that the source gem remains tested by the
  `test` job.
- The "binary gems" rows in CLAUDE.md's structure list, if the new `tools/` and
  `rakelib/` files earn one.
- Delete this file.

**Verify:** `CHANGELOG.md` names everything steps 1–6 shipped, per
[update-changelog](../../.claude/skills/update-changelog/SKILL.md), and
`docs/plans/precompiled-binary-gems.md` no longer exists.

## Open questions

1. **Bundler lockfiles across platforms.** A game's `Gemfile.lock` written on
   Linux lists only Linux under `PLATFORMS`. Recent Bundler adds the running
   platform on `bundle install`, but whether that picks the platform gem or the
   source gem on a teammate's Mac is untested. *Waits on step 5; blocks
   nothing.*
2. **Ruby 4.1** is due in December 2026. The platform gems' upper bound makes a
   4.1 user fall back to the source gem, which works. Adding 4.1 binaries means
   either one gem per ABI or one gem with a directory per ABI and a loader that
   picks. *Waits on Ruby 4.1; blocks nothing.*
3. **More platforms.** Intel Mac, ARM Linux and Windows on ARM each add a build
   and a smoke leg. Add one when someone asks for it. *Blocks nothing.*
4. **Should the source gem also use the pinned SDL2?** It would make every
   install run the same SDL, but would need CMake and a network fetch during
   `gem install`. The recommendation is no. *Blocks nothing.*
5. ~~**The Linux build environment.**~~ **Settled — the rake-compiler-dock
   `x86_64-linux-gnu` image.** Its binary needs GLIBC_2.29 and links no libruby;
   `ubuntu-latest`'s needs 2.38 and does not load on Ubuntu 22.04. See
   [Linux build environments](#linux-build-environments).
6. **Native Wayland decorations.** The image cannot build SDL with libdecor, so
   under `SDL_VIDEODRIVER=wayland` on GNOME a window has no title bar (finding
   E). *Blocks nothing; X11 through XWayland is SDL2's default.*
7. ~~**Does the macOS static bundle export SDL's symbols?**~~ **Settled — yes,
   837 of them**, measured by `tools/check_linkage.rb` in step 2's CI job. The
   step 0 count of zero was wrong. The static branch now links with
   `-Wl,-exported_symbol,_Init_core_ext` on macOS, which leaves one exported
   symbol.
