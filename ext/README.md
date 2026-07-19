# ext/

Reserved for the future Ruby C extension.

When that phase starts, this will follow Ruby's standard extension layout:

```
ext/ctest/
  extconf.rb
  ctest_ext.c   # Ruby-facing glue: VALUE wrappers around the ctest_app API
```

`extconf.rb` generates a Makefile via `mkmf` and compiles `ctest_ext.c`
together with the core sources (`src/core.c`) into a loadable `ctest.so`,
linked against SDL2 and OpenGL the same way `Makefile` at the project root
does today. The extension code should only ever call the public API in
[include/ctest/core.h](../include/ctest/core.h) — it must not reach into
`ctest_app`'s internals, since those stay opaque on purpose.
