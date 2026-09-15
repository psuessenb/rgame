# Precompiled binary gems

**Status: planned, nothing implemented.** Steps 0–3 are detailed. Steps 4–6
are rough and get re-planned once step 3 has landed.

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
  Step 3 has to change that.

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
  the list must match another file. That is a remembered rule, and step 1
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
frameworks. **For Linux it may still be the right answer**, because of the
glibc floor; step 0 decides.

## Roadmap

```
0 measure static SDL2 ─→ 1 static SDL2 build path ─→ 2 platform gem ─→ 3 clean-machine smoke test ─→ 4 release publishes them ─→ 5 install docs ─→ 6 fold back, delete plan
                               │
                               └── independently useful: one pinned SDL2 on every CI leg
```

> **A platform gem installs and draws on a machine with no compiler and no
> SDL2, and its `core_ext` names no SDL library among its dynamic
> dependencies.**

Step 1 establishes the second half with a linkage check. Step 3 establishes
the first half with a smoke test. Every later step keeps both green.

### Step 0 — Measurements: static SDL2 on each platform *(measurement only)*

**Why first:** three facts decide the shape of steps 1 and 2, and none can be
settled by reading. This step changes no code. It lands as an update to this
plan, filling in a table like the one above.

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

**Status: Windows leg measured** *(this session, x64-mingw-ucrt)*. macOS and
Linux are outstanding.

| Measured (Windows) | Result |
|---|---|
| Toolchain | MSYS2 UCRT64: gcc 16.2.0, cmake 4.4.2, ninja 1.13, mingw32-make 4.4.1. `ci.yml`'s current `pacman --sync` line has none of cmake/ninja/make — only `SDL2`, `check`, `pkgconf`, `gcc`, `gdb` — so step 1's job has to add at least `cmake` and one make tool. |
| SDL2 2.32.10 source tarball sha256 | `5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165`, for step 1a's `SDL2_RELEASE`. |
| The CMake generator (item 6) | With `ninja.exe` on `PATH`, CMake **defaults to Ninja with no `-G` flag** — it is not the "Unix Makefiles" default the sketch worried about, because `sh.exe` on `PATH` only rules that one out. `-G "MinGW Makefiles"` with `mingw32-make` also configures and builds cleanly despite `sh.exe` being present — the classic "sh.exe found, mingw32-make will not work" refusal did not trigger on this CMake version. Recommend pinning `-G Ninja` explicitly rather than relying on autodetection, and adding `mingw-w64-ucrt-x86_64-ninja` alongside `mingw-w64-ucrt-x86_64-cmake` to the toolchain action. |
| `sdl2.pc`'s `Libs` / `Libs.private` split | A pure-static build (`SDL_SHARED=OFF`) puts **everything** into `Libs` — `Libs.private` comes back empty, because there is no shared alternative for it to hold back. A plain `pkg_config('sdl2')` (no `'static'` argument) already returns the exact same full link line as `pkg_config('sdl2', 'static')` would. This differs from Linux, where a distro keeps shared and static side by side and the split matters; step 1b's `with_config('sdl2-static')` branch does not need the `'static'` pkg-config argument on Windows, only a `PKG_CONFIG_PATH` pointed at the static prefix. |
| `core_ext`'s dynamic dependencies, static SDL2 (item 1) | `ADVAPI32`, `GDI32`, `IMM32`, `KERNEL32`, nine `api-ms-win-crt-*` forwarders, `ole32`, `OLEAUT32`, `OPENGL32`, `SETUPAPI`, `SHELL32`, `USER32`, `VERSION`, `WINMM`, and `x64-ucrt-ruby400.dll`. **No SDL library.** The dynamic build's own list is just `KERNEL32`, the same `api-ms-win-crt-*` set, `OPENGL32`, `SDL2.dll` and the ruby DLL — the extra names appear because they were previously satisfied *through* `SDL2.dll`'s own import table and now have to be satisfied directly. Every one of them ships with Windows itself. |
| `core_ext.so` size | 849 KB dynamic → 3.14 MB static, same source tree. |
| SDL symbols exported (item 3) | None, in either build. The PE export table has exactly one entry (the extension's `Init_core_ext`) whether SDL is static or dynamic — mkmf generates a `.def` file per platform (`core_ext-x64-mingw-ucrt.def`) that names only the init function, so nothing exports by default the way it does on Linux. Rule 2 of step 1's linkage check is free on Windows; no `-fvisibility`-equivalent flag is needed. |
| `rake spec:core`, static vs dynamic (item 2) | Dynamic (rebuilt fresh, matching the current source tree): **398 examples, 1 failure** — a pre-existing `docs/api` reference-checker failure unrelated to SDL2. Static: **396 examples, 4 failures** — the same doc failure plus 3 gamepad/hot-plug failures. Each build's result reproduced identically twice; not flaky. See the finding below — the 3 extra failures are a test-harness gap, not an engine regression. |
| `Gem::Platform.local` (item 7) | `x64-mingw-ucrt` — matches decision 2's name exactly. |

**Finding: the virtual-gamepad harness assumes a shared SDL2 and fails silently
without one.** `spec_core/support/virtual_gamepad.rb` reaches the engine's own
SDL by `Fiddle.dlopen`ing a hardcoded library name — `'SDL2.dll'` on Windows,
`'libSDL2-2.0.so.0'` on Linux — on the stated assumption that this resolves to
the exact copy `core_ext.so` linked, so driving it drives the engine's own SDL
state. A statically-linked `core_ext.so` has no `SDL2.dll` to resolve to at
all, but on this machine `Fiddle.dlopen('SDL2.dll')` **still succeeds**: this
Ruby is a RubyInstaller build, and RubyInstaller Rubies keep their own MSYS2
devkit reachable through Ruby's built-in DLL-directory mechanism independent of
`PATH` — confirmed with `GetModuleFileNameW`, which named
`C:\msys64\ucrt64\bin\SDL2.dll` even from a shell with no `msys64` anywhere on
`PATH`. The harness ends up attaching its virtual pad to a second, unrelated
SDL2 instance that the statically-linked engine never sees, so hot-plug
callbacks never fire — not a crash, not a load error a developer would notice,
just a quietly wrong `expected 1, got 0`. macOS's branch
(`Fiddle::Handle::DEFAULT`, which searches images already loaded into the
process rather than a named file) has no such gap, because it needs no shared
library to exist. Generalizing Windows and Linux to the same
already-loaded-image lookup — rather than a hardcoded filename — is real work
for whichever of steps 1–3 first runs `spec:core` against a static build in CI;
it is a fix to the test harness, not to the engine.

**Verify:** this plan's step 0 section holds a table with one column per
platform and a row per item above, and step 1's link flags and step 2's Linux
build environment are rewritten to match it.

### Step 1 — A static SDL2 build path for `core_ext`

**Why here:** everything after it packages this build, so it must be proven
first — and it is worth landing on its own. It gives CI one pinned SDL2 on all
three platforms, where today each runs a different one.

#### 1a. `rake sdl2` builds the pinned release

```ruby
# rakelib/sdl2.rake
SDL2_RELEASE = {
  version: '2.32.10',
  sha256: '5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165' # step 0, Windows leg
}.freeze

SDL2_PREFIX = File.expand_path('build/sdl2', __dir__)

desc 'Build the pinned SDL2 as a static, position-independent library'
task sdl2: "#{SDL2_PREFIX}/lib/pkgconfig/sdl2.pc"
```

It downloads the release tarball, refuses it on a checksum mismatch, and runs
the CMake invocation step 0 settled. The prefix sits under `build/`, which is
already ignored and already outside the gem.

#### 1b. `extconf.rb` links a static SDL2 when given one

```ruby
static_sdl2 = with_config('sdl2-static') # a prefix built by `rake sdl2`

if static_sdl2
  ENV['PKG_CONFIG_PATH'] = File.join(static_sdl2, 'lib/pkgconfig')
  abort "No static SDL2 under #{static_sdl2}. Run: rake sdl2" unless pkg_config('sdl2', 'static')
else
  abort 'SDL2 not found (pkg-config --exists sdl2 failed). Install libsdl2-dev.' unless pkg_config('sdl2')
end
```

The link flags come from SDL's own `sdl2.pc` (`Libs.private`), not from a list
in `extconf.rb`. On macOS that is the framework list Ruby2D keeps by hand. The
exact `pkg_config` call is step 0's to confirm. On Linux, add
`-Wl,--exclude-libs,ALL` or the equivalent step 0 found, so SDL's symbols stay
private to `core_ext`.

#### 1c. The toolchain setup moves into a composite action

`.github/actions/toolchain/action.yml` takes the per-OS install, `ridk`, `PATH`
and Mesa steps out of the test job. The test job calls it unchanged. The new
job in 1d calls it too, so the Windows `PATH` fix exists once.

#### 1d. A `static-sdl2` CI job

A matrix over the three runners, beside the existing `test` job:

```
rake sdl2 → make ext with --with-sdl2-static → rake spec:core → ruby tools/check_linkage.rb
```

`tools/check_linkage.rb` reads the platform's own dependency and export
listings for both `.so` files, and exits non-zero on a rule below. On Linux the
job runs wherever step 0 settled.

**Rules the checks pin:**

1. `core_ext`'s dynamic dependencies name no SDL library.
2. `core_ext` exports no `SDL_` symbol.
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

### Step 2 — `rake native gem` builds and checks a platform gem

**Why here:** the static build from step 1 exists, and a platform gem is that
build plus packaging. Publishing waits until step 3 has proven the gem on a
clean machine, so this step produces an artifact and publishes nothing.

#### 2a. rake-compiler builds both extensions

```ruby
# Rakefile
require 'rake/extensiontask'

GEMSPEC = Gem::Specification.load('rgame.gemspec')

{ 'rgame_util' => 'util_ext', 'rgame_core' => 'core_ext' }.each do |dir, name|
  Rake::ExtensionTask.new(name, GEMSPEC) do |ext|
    ext.ext_dir = "ext/#{dir}"
    ext.lib_dir = 'lib/rgame'
    ext.config_options << "--with-sdl2-static=#{SDL2_PREFIX}" if dir == 'rgame_core'
  end
end
```

`rake compile` and `make ext` must not fight over `lib/rgame/*.so`. Either one
drives the other, or `make ext` stays the developer's command and rake-compiler
only runs for gems; the sub-step decides and says which.

#### 2b. The platform gem's specification

rake-compiler's native task derives it from `rgame.gemspec`. On top of that
derivation:

- **Files:** the source gem's files, minus `ext/**`, plus the two compiled
  extensions and SDL2's `LICENSE.txt` from the release tarball.
- **`extensions`:** empty.
- **`required_ruby_version`:** `>= 4.0`, `< 4.1.dev`, derived from the ABI of
  the Ruby doing the build rather than written out.

#### 2c. `tools/check_platform_gem.rb`, run by the task that builds the gem

The `native gem` task calls it on the `.gem` it just wrote, so no one can build
a platform gem without checking it. It opens the `.gem` archive itself and
does not ask the specification object. The packaging spec's `.dSYM` example
explains why: a check that shares the derivation it guards shares its blind
spots.

**Rules the checker pins:**

1. The platform is one of the three in decision 2.
2. It contains exactly one `core_ext` and one `util_ext`, with this platform's
   `DLEXT`.
3. It contains no `.c`, no `.h`, no `extconf.rb` and no `Makefile`, and
   declares no extensions.
4. `required_ruby_version` excludes the next Ruby minor.
5. It contains SDL2's licence.
6. Every file of the source gem outside `ext/` is in it — the packaging spec's
   rules for `lib/`, `examples/`, `docs/api/` and `exe/` hold here too.
7. `tools/check_linkage.rb` passes on the extensions inside it.

**Tests:**

- The `static-sdl2` job becomes `build-gem`: it runs `rake native gem`, and
  uploads the platform gem as an artifact. A second job on Linux uploads the
  source gem.
- The checker run on the **source** gem fails rules 1, 2 and 3, proving it can
  fail.
- `rake spec`, unchanged: `spec/packaging_spec.rb` still passes against
  `rgame.gemspec`, which is constraint 1.

**Verify:** a push produces four artifacts — three platform gems and the source
gem — and each platform gem passed the checker in the job that built it.

### Step 3 — A clean-machine smoke test

**Why here:** a gem that passes every check on the machine that built it can
still fail on a machine that did not. The checker proves what is in the file.
This step proves the file works where it lands.

#### 3a. The drive harness runs against an installed gem

`tools/drive_test_project.rb:514` prepends the checkout's `lib/`. It gains an
`--installed` switch that leaves the load path alone, and the report states
which `rgame` it loaded and from where — `$LOADED_FEATURES` for
`rgame/core_ext` — so a run cannot quietly test the checkout.

#### 3b. A `smoke` job per platform

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
gem fails it — for example, one built with step 1b's static branch removed,
installed on the Linux runner with no SDL2.

### Step 4 — The release job publishes every gem *(rough)*

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

### Step 5 — Install documentation *(rough)*

- `README.md`'s install section: on the three platforms, Ruby 4.0 and
  `gem install rgame` are enough. Everywhere else the requirements list stays.
- The release skill: what the job now publishes, and how to read a partial
  release.

### Step 6 — Fold the plan back and delete it *(rough)*

- CLAUDE.md's "Packaging" section: the two kinds of gem, why SDL2 is static,
  the checker and the smoke test, and that the source gem remains tested by the
  `test` job.
- The "binary gems" rows in CLAUDE.md's structure list, if the new `tools/` and
  `rakelib/` files earn one.
- Delete this file.

**Verify:** `CHANGELOG.md` names everything steps 1–5 shipped, per
[update-changelog](../../.claude/skills/update-changelog/SKILL.md), and
`docs/plans/precompiled-binary-gems.md` no longer exists.

## Open questions

1. **Bundler lockfiles across platforms.** A game's `Gemfile.lock` written on
   Linux lists only Linux under `PLATFORMS`. Recent Bundler adds the running
   platform on `bundle install`, but whether that picks the platform gem or the
   source gem on a teammate's Mac is untested. *Waits on step 4; blocks
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
5. **The Linux build environment** — `ubuntu-latest`, an older Ubuntu
   container, or rake-compiler-dock's image. *Settled by step 0.*
