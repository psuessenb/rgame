# Vendored third-party code

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

**Why it is not compiled directly.** `stb_image.h` is a header that becomes an
implementation when one translation unit defines `STB_IMAGE_IMPLEMENTATION`.
That translation unit is [`../stb_image_impl.c`](../stb_image_impl.c), which
exists for one reason: the project compiles with `-Wall -Wextra` and expects to
stay warning-clean, and third-party code rarely survives that. Isolating the
implementation in one file lets `extconf.rb` and the root `Makefile` relax
warnings for exactly that file and nothing else.

Only PNG decoding is enabled (`STBI_ONLY_PNG`); the other formats are compiled
out, which keeps the object small and shrinks the parsing surface exposed to
whatever files a game happens to load.

### Updating it

```
curl -sSL -o ext/rgame_core/vendor/stb_image.h \
  https://raw.githubusercontent.com/nothings/stb/master/stb_image.h
```

Then run `make test` and `rake spec:core` — `spec_core/rgame/core/image_spec.rb`
decodes a real PNG and checks its pixels, which is what would notice a
regression. Bump the version in the heading above.
