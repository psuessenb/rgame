# Vendored third-party code

Third-party sources that are **compiled into the engine** live here. Note what
is *not* here: the default font, which is data read at runtime and therefore
lives where a gem installs data — see "The default font" at the bottom.

## `stb_image.h` — v2.30

Single-header image decoder by Sean Barrett, <http://nothings.org/stb>.
Dual-licensed **MIT or public domain (Unlicense)** — the full text is at the
bottom of the header itself. Nothing needs to be done to comply with either;
it is recorded here so the choice is visible without reading 8000 lines.

**Why vendored rather than a system package.** It is not packaged on any
mainstream distro, and the alternative is a `libpng` (plus `zlib`) build
dependency that every `gem install rgame` would then have to satisfy. A
public-domain header in the repo is the smaller obligation, and it is the only
dependency the gem does not have to ask for.

Only PNG decoding is enabled (`STBI_ONLY_PNG`); the other formats are compiled
out, which keeps the object small and shrinks the parsing surface exposed to
whatever files a game happens to load.

## `stb_truetype.h` — v1.26

Single-header TrueType rasteriser from the same author and under the same
dual licence. It turns the shipped `.ttf` into the coverage bitmaps that fill
the glyph atlas.

Same reasoning as above, with more force: the alternative is FreeType, which is
a real system dependency, and Gosu — which this engine replaces — vendors this
very header for this very job.

No feature macros are set. The defaults are what a glyph atlas wants, and
`STBTT_STATIC` is deliberately *not* defined so that `font.c` can call into it
from another translation unit.

## How they are built

Each header becomes code in exactly one file, `stb_<name>_impl.c`, which
contains the `#define STB_..._IMPLEMENTATION` and nothing else.

**Those files are the only ones in the project compiled without `-Wall
-Wextra`.** Third-party code rarely survives them, and everything we wrote is
meant to stay warning-clean. Both build systems carve out the same set from one
list rather than one rule per library — `VENDOR_OBJS` and the `stb_%_impl.o`
pattern rule in the root `Makefile`, and `VENDORED_STB` in `extconf.rb`, which
appends an explicit rule per entry (mkmf Makefiles have to work with whatever
`make` the platform has, and pattern rules are a GNU extension).

Adding a third stb library is therefore: drop the header here, add
`stb_<name>_impl.c`, and add the name to those two lists.

### Updating them

```
curl -sSL -o ext/rgame_core/vendor/stb_image.h \
  https://raw.githubusercontent.com/nothings/stb/master/stb_image.h
curl -sSL -o ext/rgame_core/vendor/stb_truetype.h \
  https://raw.githubusercontent.com/nothings/stb/master/stb_truetype.h
```

Then run `make test` and `rake spec:core` — `spec_core/rgame/core/image_spec.rb`
decodes a real PNG and checks its pixels, and the font specs measure and render
real glyphs, which is what would notice a regression. Bump the versions in the
headings above.

## The default font

`lib/rgame/fonts/LiberationSans-Regular.ttf` — **Liberation Sans 2.1.5**, from
the upstream release at <https://github.com/liberationfonts/liberation-fonts>,
licensed **SIL Open Font License 1.1** (`lib/rgame/fonts/OFL.txt`).

It is not in this directory because it is not compiled — it is a data file the
engine reads at runtime, so it belongs where the gem installs data. `Font.new`
without a path uses it.

**Take 2.x, not 1.x.** Liberation 1.x is GPL-2-with-a-font-exception rather than
OFL, and lacks capital `ẞ`. The 2.x file is 410 KB and covers 2327 codepoints:
Latin-1 Supplement and Latin Extended-A complete (so English, German, French,
Italian, Spanish, Portuguese, Nordic and Polish in full, plus `« »`, curly
quotes and `€`), and Greek and Cyrillic besides. Not CJK, Arabic, Hebrew or
Devanagari — a game needing those passes its own font path.

Why a shipped font at all, rather than asking the system for one the way Gosu
does, is recorded in
[docs/plans/gosu-replacement/README.md](../../../docs/plans/gosu-replacement/README.md#the-default-font-is-vendored-not-looked-up).
