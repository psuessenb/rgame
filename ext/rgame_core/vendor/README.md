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

## `miniaudio.h` — v0.11.25

Single-header audio playback library by David Reid,
<https://miniaud.io>. Dual-licensed **public domain or MIT-0**, stated at the
bottom of the header.

It provides the device, the mixer and voice management. On Linux it finds ALSA
or PulseAudio **at runtime** with `dlopen`, so nothing has to be linked or
installed; on Windows and macOS it needs nothing at all. That is the property
that makes audio cost this project no new system dependency, and it is the whole
reason it is here instead of SDL_mixer — which would need `libsdl2-mixer-dev` to
build and pulls ~8 MB on Debian, six of them a MIDI soundfont. raylib and SFML 3
made the same choice; the survey and measurements are in
[docs/plans/gosu-replacement/README.md](../../../docs/plans/gosu-replacement/README.md#audio-is-vendored-too-and-it-is-not-sdl_mixer).

It is ~4 MB of source, an order of magnitude more than everything else here.
That is known and accepted; if it ever stops being worth it, MojoAL is the
fallback and is a tenth the size.

Which formats and backends are compiled in is decided in
[`miniaudio_impl.c`](miniaudio_impl.c) rather than in build flags, so the
standalone binary and the gem cannot end up supporting different things.

## `stb_vorbis.c` — v1.22

Ogg Vorbis decoder, same author and licence as the other stb files. miniaudio
**cannot read Ogg Vorbis** — it does wav, mp3 and flac — and its own reference
vorbis backend uses *system* libvorbis, which would hand back the dependency all
of the above avoids. `../audio/vorbis_decoder.c` is a miniaudio decoding backend over
this instead.

Note it ships as a `.c`, not a `.h`: it is always an implementation, with no
declarations-only mode.

## How they are built

Each library becomes code in exactly one file, `<name>_impl.c`, which sits here
beside the library it instantiates and contains the implementation macro and the
feature choices, and nothing else. **The `_impl.c` suffix is reserved for
vendored code** — it is what selects the warning carve-out below.

**Those files are the only ones in the project compiled without `-Wall
-Wextra`.** Third-party code rarely survives them, and everything we wrote is
meant to stay warning-clean. Both build systems carve out the same set from one
list rather than one rule per library — `VENDOR_OBJS` and the `%_impl.o`
pattern rule in the root `Makefile`, and `VENDORED` in `extconf.rb`, which
appends an explicit rule per entry (mkmf Makefiles have to work with whatever
`make` the platform has, and pattern rules are a GNU extension).

Adding another library is therefore: drop the source here, add `<name>_impl.c`,
and add the name to those two lists.

### Updating them

```
V=ext/rgame_core/vendor
curl -sSL -o $V/stb_image.h    https://raw.githubusercontent.com/nothings/stb/master/stb_image.h
curl -sSL -o $V/stb_truetype.h https://raw.githubusercontent.com/nothings/stb/master/stb_truetype.h
curl -sSL -o $V/stb_vorbis.c   https://raw.githubusercontent.com/nothings/stb/master/stb_vorbis.c
curl -sSL -o $V/miniaudio.h    https://raw.githubusercontent.com/mackron/miniaudio/master/miniaudio.h
```

Then run `make test` and `rake spec:core`. Those suites decode a real PNG and
check its pixels, measure and render real glyphs, and decode a real `.ogg` — so
a regression in any of the four shows up as a failure rather than as something
noticed months later. Bump the versions in the headings above.

### The audio test fixture

`spec_core/fixtures/tone.ogg` is generated by
[`tools/make_ogg_fixture.c`](../../../tools/make_ogg_fixture.c) and committed.
The other suites build their own fixtures — PNGs from Ruby's zlib, glyphs from
the shipped font — but there is no Ogg Vorbis encoder in Ruby's standard library
and stb_vorbis only decodes, so this one is made once with `libvorbisenc` and
checked in. That library is needed to *regenerate* the fixture and by nothing
else; the engine links no vorbis library at all.

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
