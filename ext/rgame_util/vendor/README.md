# Vendored third-party code in Util

Third-party sources compiled into **both** extensions. They live in Util because
`RGame::Util::Typeface` measures text with them in a process that has no
graphics library. Core's font atlas rasterises with them too, so
`ext/rgame_core/extconf.rb` compiles its own copy from here. The other vendored
libraries, and how the warning carve-out works, are in
[`ext/rgame_core/vendor/README.md`](../../rgame_core/vendor/README.md).

## `stb_truetype.h` — v1.26

A single-header TrueType rasteriser by Sean Barrett, <http://nothings.org/stb>.
It is dual-licensed **MIT or public domain (Unlicense)**, and the full text is
at the bottom of the header. It measures glyphs, and it turns the shipped `.ttf`
into the coverage bitmaps that fill the glyph atlas.

The alternative is FreeType, which is a real system dependency. Gosu, which
this engine replaces, vendors this same header for the same job.

No feature macros are set. The defaults are what a glyph atlas wants.
`STBTT_STATIC` is deliberately *not* defined, so that `typeface.c` can call into
it from another translation unit.

`stb_truetype_impl.c` instantiates it, and is built without `-Wall -Wextra` by a
rule in each `extconf.rb` and by the `%_impl.o` rule in the root `Makefile`.

### Updating it

```
curl -sSL -o ext/rgame_util/vendor/stb_truetype.h https://raw.githubusercontent.com/nothings/stb/master/stb_truetype.h
```

Then run `make test`, `rake spec` and `rake spec:core`, which measure and render
real glyphs from the shipped font. Bump the version in the heading above.
