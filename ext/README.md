# ext/

Reserved for the future Ruby C extension.

When that phase starts, this will follow Ruby's standard extension layout:

```
ext/rgame/
  extconf.rb
  rgame_ext.c   # Ruby-facing glue: VALUE wrappers around the rgame_app API
```

`extconf.rb` generates a Makefile via `mkmf` and compiles `rgame_ext.c`
together with the core sources (`src/core.c`) into a loadable `rgame.so`,
linked against SDL2 and OpenGL the same way `Makefile` at the project root
does today. The extension code should only ever call the public API in
[include/rgame/core.h](../include/rgame/core.h) — it must not reach into
`rgame_app`'s internals, since those stay opaque on purpose.
