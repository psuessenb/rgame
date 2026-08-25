# Precompiled binary gems

**Status: sketch. Nothing here has been executed.** Written 2026-08-25, from a
read of `rgame.gemspec`, both `extconf.rb` files, the `Rakefile`, `ci.yml` and
the linkage of a built extension on macOS. It replaces the "C1" open question
from the cross-platform-support plan, which is finished and deleted — the three
CI legs it built are green, and this is the next decision that plan deferred.

The question: **`gem install rgame` compiles on the user's machine today. What
would it take to ship prebuilt binaries for Linux, macOS and Windows, and can
CI build them?**

Per CLAUDE.md this is a working document. When the work lands, whatever is still
true gets folded into `README.md` and CLAUDE.md's "Packaging" section, and this
file is deleted.

## Verdict

**The compiling is the easy part. The blocker is SDL2.**

Building the extension on three platforms is solved — CI already does it on
every push. What a binary gem has to solve *additionally* is that the compiled
object has a **dynamic dependency on a library the user may not have**, and on
macOS that dependency is recorded as an absolute path:

```
$ otool -L lib/rgame/core_ext.bundle
  /opt/homebrew/opt/sdl2-compat/lib/libSDL2-2.0.0.dylib
  /System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL
```

Ship that binary and it breaks on an Intel Mac (Homebrew's prefix is
`/usr/local` there) and on any machine without Homebrew at all. OpenGL is fine
everywhere — it is an OS component on all three platforms, which is exactly why
`extconf.rb` links it three different ways and installs nothing. **SDL2 is the
whole problem.**

So precompiling does not remove the native dependency by itself. It moves *when*
the user hits it: from "you need a compiler and SDL2 headers" to "you need
SDL2". That is a real improvement and it is not the improvement people expect
from a binary gem.

## The three shapes this can take

| | What ships | What the user still needs | Cost |
|---|---|---|---|
| **A. Binaries only** | compiled `.so`/`.bundle` per platform | SDL2 installed system-wide | small |
| **B. Binaries + bundled SDL2** | the above plus `libSDL2` inside the gem | nothing | medium–large |
| **C. Binaries, SDL2 linked statically** | one self-contained object | nothing | large |

**A** is roughly mechanical (see "What changes in this repo"). It removes the
*compiler* requirement, which is the harshest part on Windows, where it means
RubyInstaller's DevKit plus an MSYS2 pacman invocation before `gem install`
works at all. It does not remove the SDL2 hunt, and on Windows that still means
finding an `SDL2.dll`.

**B** ships SDL2 beside the extension and makes the loader find it there.
Per-platform work, all of it well-trodden: `install_name_tool` /
`@loader_path` on macOS, an `$ORIGIN` rpath on Linux, and on Windows simply
placing `SDL2.dll` next to the `.so` (Windows searches the loading module's own
directory first — the same rule that makes `ci.yml` install Mesa next to
`ruby.exe` rather than anywhere on `PATH`).

**C** avoids the loader question entirely. It is viable rather than exotic
because of two facts about SDL2: it is **zlib-licensed**, so static linking
carries no copyleft obligation, and it **dlopens** X11, Wayland, ALSA and
PulseAudio at runtime rather than linking them, so a static SDL2 does not drag a
Linux display stack into the build. It is still the largest of the three.

**Only B and C give a `gem install rgame` that works for someone who is not
already a games developer.** That is the decision to make deliberately, and it
is a bigger question than the mechanics below.

## Can CI build them?

Yes, but **not from a single job**, and the reason is worth knowing before
designing the pipeline.

`rake-compiler-dock` is the standard tool and cross-compiles from one Linux
container for **Linux (gnu and musl) and Windows**, against a deliberately old
glibc so the result runs on older distributions. It has **no macOS image** —
Apple's SDK cannot be redistributed that way — so macOS binaries must be built
on macOS runners.

The realistic shape is therefore a hybrid:

- one container job cross-compiling `x86_64-linux-gnu`, `aarch64-linux-gnu`,
  `x86_64-linux-musl` and `x64-mingw-ucrt`
- native macOS jobs for `arm64-darwin` **and** `x86_64-darwin` (two gems; a
  single runner does not produce both without extra setup)
- the plain source gem as well, as the fallback for any platform not covered

That is five or six `.gem` files per release. Each job uploads its artifact; a
release job collects and publishes them.

The matrix in `ci.yml` already proves the three toolchains work, which is most
of the groundwork. What it does *not* currently do is produce artifacts.

## What changes in this repo

1. **`rake-compiler` as a development dependency**, with a
   `Rake::ExtensionTask` per extension. Note there are **two** —
   `ext/rgame_util` and `ext/rgame_core` — and both must end up in the gem.

2. **The gemspec becomes platform-aware.** A binary gem sets `spec.platform`,
   empties `spec.extensions`, and ships the compiled object under a per-ABI
   directory (`lib/rgame/4.0/core_ext.so`). `required_ruby_version >= 4.0` means
   one ABI today; supporting a second Ruby multiplies the gem count by two.

3. **`spec.files` has to reverse itself, and that is the sharp edge.** The
   gemspec's `artifacts` regex strips `.so`/`.bundle`/`.dylib`, and
   `spec/packaging_spec.rb` asserts it:

   > `it 'excludes compiled extensions and object files'` — "lib/rgame/*.so is
   > this machine's binary. Shipping it would shadow the one `gem install`
   > compiles for the machine the gem lands on."

   That reasoning is exactly right for a source gem and exactly inverted for a
   binary one. The guard has to become conditional on which kind of gem is being
   built — source excludes every binary, a platform gem includes exactly one set
   and no `.c` — rather than simply being relaxed. It is currently the best
   defence this project has against packaging mistakes, and the failure mode it
   protects against (a wrong or missing file, invisible locally, breaking on
   someone else's machine) is precisely the failure mode binary gems multiply.

4. **A smoke-test job.** The step that gets skipped: install the built `.gem` on
   a *clean* runner — not the one that built it — and require it. This project
   is unusually well placed for that, because `tools/drive_example.rb` boots all
   three layers and drives them, and `examples/16_hello_world` needs no assets
   beyond the shipped font.

## Release automation

Not automated today. `Rakefile` pulls in `bundler/gem_tasks`, so `rake release`
exists and does the single-gem thing: tag, build, push. Multi-platform means
pushing N gems from N artifacts, which is a different task.

Two gotchas specific to this project:

- **`rubygems_mfa_required` is `true`** in the gemspec metadata. That blocks an
  unattended API-key push. The way to publish from Actions is RubyGems'
  **trusted publishing** (OIDC), which needs configuring on the RubyGems side
  and no long-lived secret in the repo. Worth knowing before wiring up a token
  that cannot work.
- **The version has exactly one home**, `lib/rgame/version.rb`, and the gemspec
  loads it directly. A release flow must not introduce a second.

## Recommendation

Shape **A** is a day of mechanical work and buys less than it sounds like.
Shape **C** is what makes `gem install rgame` work for a *user* rather than a
developer, and is comparable in size to the whole cross-platform port that
preceded this document.

Either way, this is worth deferring until there is a reason to publish at all —
nothing is on RubyGems yet. When it is picked up, do **A first and measure it**:
it is a strict prerequisite for B and C (the build, artifact and release
pipeline is the same), and shipping it alone answers whether "no compiler, but
still install SDL2" is good enough in practice.

## Open questions

- **Which platforms are actually worth shipping?** `aarch64-linux` and
  `x86_64-linux-musl` each add a build and a test surface. Not shipping them
  means those users fall back to the source gem, which still works.
- **Does the source gem stay the default?** RubyGems serves the platform gem
  when one matches and falls back to source otherwise, so both can coexist —
  but the source gem must keep being tested, or it rots into a fallback that
  does not work.
- **Where does SDL2 come from in shape B/C?** Vendoring its source into `ext/`
  and building it, versus fetching a release during the build. The former fits
  this project's existing `vendor/` convention; the latter keeps the repo small
  but makes builds depend on a network fetch.
