# 01 — Inventory: what `lib/platform/` is today

Eleven files, ~840 lines of Ruby. This is a read of the code as it stands, so
the rewrite has a checklist rather than a vibe. Every entry answers: what does
this class do, what does it need from the layer below, and where should it end
up.

Whole-repo Gosu usage, for scale — every one of these must be replaced:

| Gosu surface | Used by |
|---|---|
| `Gosu::Window` (subclass, `update`/`draw`/`needs_redraw?`/`button_down`, `width`/`height`/`caption=`/`close`) | `GameWindow` |
| `Gosu.milliseconds` | `Clock`, `TileMapRenderer` |
| `Gosu.fps` | `GameWindow` |
| `Gosu.button_down?`, `Gosu::KB_*` / `Gosu::MS_LEFT` | `GosuInput`, `GameWindow` |
| `Gosu::Image.new(path, retro:)`, `#draw`, `#draw_rot`, `#subimage`, `#width`/`#height`, `.load_tiles` | `SpriteSheet`, `NineSlice`, `TileMapRenderer`, `AssetManager`, `GosuRenderer` |
| `Gosu::Font.new(size)`, `#draw_text`, `#text_width`, `#height` | `GosuRenderer` |
| `Gosu::Color`, `Gosu::Color.rgba`, `Gosu::Color::WHITE` | `GosuRenderer`, `NineSlice` |
| `Gosu.draw_rect`, `.draw_quad`, `.draw_triangle` | `GosuRenderer` |
| `Gosu.rotate`, `.translate`, `.clip_to` | `GosuRenderer`, `NineSlice` |
| `Gosu.record`, `Gosu.render` | `TileMapRenderer`, `GosuRenderer` |
| `Gosu::Sample`, `Gosu::Song`, `Song.current_song`, `#play`, `#playing?`, `#stop` | `GosuAudio`, `AssetManager` |
| `Gosu::Window#protected_*` (monkey-patched) | `gosu_patches.rb` |

---

## The classes

### `Platform::GameWindow` → `RGame::Core::App`

A `Gosu::Window` subclass owning the fixed-timestep loop.

```ruby
GameWindow.new(width:, height:, caption:, root:, renderer:, mapper:)
#update            # accumulator; polls mapper once, runs 0..5 root steps
#needs_redraw?     # @dirty || @overlay.visible?
#draw              # root.draw(renderer); overlay.draw(renderer, w, h, Gosu.fps)
#button_down(id)   # Esc → close, F1 → overlay.toggle
attr_accessor :root
```

Needs from below: window creation with a caption, a monotonic clock, an FPS
readout, discrete key-down events, `#close`, `#width`/`#height`, and a
`needs_redraw?` hook.

Three details that must survive the port:

- **Input is polled once per rendered frame**, not once per simulation step, and
  the resulting `actions` object is reused across all catch-up steps
  (`game_window.rb:31`). This is deliberate: a key held for one frame must not
  register differently depending on how many catch-up steps ran.
- **`@dirty` is set only when at least one simulation step ran**
  (`game_window.rb:47`). "Nothing simulated → nothing new to show."
- **The overlay forces a redraw while visible** (`game_window.rb:56`), so its
  live FPS/allocation readouts keep ticking even when the sim is idle.

Status of the current `RGame::Platform::App`: it has the loop and the FPS/ticks
readouts but exposes the wrong shape (procs, not overrides) and is missing
`close`, `width`, `height`, `caption=` and button events. It also **hardcodes
Escape-quits inside C** (`core.c:87`), which is a game-policy decision that
belongs in Ruby — `GameWindow#button_down` is where it lives today.

### `Platform::Clock` → deleted

19 lines wrapping `Gosu.milliseconds` into a seconds delta. The C loop already
computes elapsed time itself (`core.c:106-108`) and feeds `frame_loop.c`. Once
the accumulator stays in C, nothing calls this. Its one other consumer — the
"what time is it for animation phase" question — is served by `App#ticks_ms`.

### `Platform::GosuInput` → `RGame::Core::Input`

34 lines. A symbol → key-constant table plus three queries:

```ruby
#down?(physical_id)   # :left, :right, :up, :down, :confirm, :fire, :pointer
#pointer_x / #pointer_y
```

Note the `BINDINGS` hash is *configuration*, not mechanism — it names which
physical key means `:fire` for this game. The mechanism is
`Gosu.button_down?(constant)` and `window.mouse_x/y`.

The comment at `gosu_input.rb:21-25` is worth reading: it explains why the
module method is used instead of `Window#button_down?`, because the compat
shim's `|*args|` splat allocates per polled key per frame. Same category of
problem as `gosu_patches.rb`, same structural fix in C.

### `Platform::GosuRenderer` → `RGame::Core::Renderer`

214 lines, the biggest piece and the one the whole engine draws against. Two
distinct responsibilities tangled together:

**(a) An asset-id registry.** `register_sheet` / `register_tilemap` /
`register_image` / `register_nine_slice` / `register_ui_atlas`, plus lazy
resolution through an `AssetManager` (`sheet_for` / `image_for` /
`tilemap_for`, `gosu_renderer.rb:191-198`). Load-time-ish bookkeeping, memoised so
the per-draw cost is one hash lookup.

**(b) Draw primitives.** The actual interface scenes call:

| Method | Backed by |
|---|---|
| `sprite(id, row, col, x, y, flip_x:, z:)` | `SpriteSheet#draw` |
| `tilemap(id, cx, cy, vw, vh)` / `tilemap_overlay(..., z:)` | `TileMapRenderer` |
| `rotated(angle, pivot_x, pivot_y) { }` | `Gosu.rotate` |
| `translated(dx, dy) { }` | `Gosu.translate` |
| `image(id, cx, cy, angle:, scale:, z:)` | `Image#draw_rot` |
| `background(id, z:)` | `Image#draw` |
| `nine_slice(id, x, y, w, h, z:, tint:)` | `NineSlice#draw` |
| `text(string, x, y, z:, color:)` | `Font#draw_text` |
| `text_width(s)` / `text_height` | `Font` metrics |
| `rect(x, y, w, h, z:, color:)` | `Gosu.draw_rect` |
| `circle(cx, cy, r, z:, color:)` | cached unit-circle texture + `draw_rot` |
| `line(x1, y1, x2, y2, thickness:, z:, color:)` | `Gosu.draw_quad` |
| `debug_box(x, y, w, h)` | `rect` |

Three implementation notes that encode real knowledge and should be carried
over as *requirements*, not reproduced as *code*:

- **`rotated`/`translated` have a zero fast path** (`gosu_renderer.rb:77`, `:91`) that
  skips both the Gosu call and the block allocation. In C the equivalent is
  "pushing an identity transform is free", which it naturally is — but the
  Ruby-side `yield`-without-block-capture trick (`# rubocop:disable
  Style/ExplicitBlockArgument`) must be preserved in whatever Ruby wrapper
  remains, for the same allocation reason.
- **`circle` is one cached texture, not a per-frame triangle fan**
  (`gosu_renderer.rb:172-185`). It needs `Gosu.render` (render-to-texture) and
  `draw_triangle`. Alternatively, once a real batching renderer exists, a
  triangle fan is cheap enough to not need the texture at all — a
  simplification the rewrite unlocks.
- **`line` deliberately avoids forming a negated intermediate**
  (`gosu_renderer.rb:149-157`) because a computed `-0.0` is heap-allocated by CRuby.
  If this method moves to C the comment becomes irrelevant; if it stays in
  Ruby it must stay exactly as written.

`resolve_color` accepts `nil` (→ white), `[r,g,b]`/`[r,g,b,a]`, or a native
colour, and caches array→colour conversions. That tri-modal contract is part of
the preserved public API.

### `Platform::SpriteSheet`

57 lines. Parses an atlas descriptor and cuts an image into a `rows × columns`
grid of subimages, supporting a drawn frame smaller than and offset within its
cell (`frame_width`/`origin_x` vs `cell_width`). `#draw(row, col, x, y, flip_x:,
z:)` indexes the grid and draws, using a negative x-scale plus an x-offset for
the flip.

Needs: `Image#subimage`, `Image#draw` with scale, `Image#width`/`#height`.
Exposes `animations` raw so the engine can build a Gosu-free animation set.

### `Platform::NineSlice`

81 lines, and the single most C-shaped thing in the Ruby layer. Cuts nine
subimages once at construction, then `#draw(dx, dy, dw, dh, z:, color:)` fills
an arbitrary rect by drawing four corners and **tiling** (not stretching) the
four edges and the centre, each band clipped so the trailing tile is cropped.

`tile_band` (`nine_slice.rb:62-79`) is a nested `while` loop issuing one draw
per tile, inside a `clip_to`, and it runs **five times per `nine_slice` call**.
Every UI panel and button chrome goes through this every frame. It is pure
geometry driving a flat list of quads — exactly the shape that wants to be a C
loop feeding a batch.

### `Platform::UiAtlas`

50 lines. JSON descriptor → `{ id => NineSlice }`. Handles a uniform-integer or
per-side border spec and a per-entry scale override. Pure config parsing, runs
at load time.

### `Platform::TileMapRenderer`

111 lines, and the other genuinely hot one. Splits map layers into a *below*
and an *above* band by `map.above_layer?`, then for each band:

- **Static tiles** are baked once into a `Gosu.record` macro and redrawn as one
  call, scrolled by drawing at `(-camera_x, -camera_y)`. Baking is lazy because
  it needs a live GL context (`tile_map_renderer.rb:40`).
- **Animated tiles** are collected once into `[col, row, local_id]` triples, then
  each frame culled to the viewport and drawn one at a time, with the current
  frame chosen from `Gosu.milliseconds`.

The per-frame animated-tile loop (`:103-108`) is the exact sore point the
feature spec §4 names: O(visible animated tiles) native-call crossings per
frame. It also carries a Gosu limitation in a comment — "recorded images draw
only in white (no tint)" — which the rewrite has no reason to reproduce.

`.load` reaches into `Engine::TileMap` / `Engine::Tileset` for TMX/TSX parsing.
That parsing is XML, is load-time, and stays in Ruby.

### `Platform::AssetManager`

121 lines. One root path, typed loaders, memoisation, and reference counting by
"group" so `release(:level1)` frees what only level 1 held. Composites
(`sheet`, `ui_atlas`) pull their descriptor and backing image through the same
cache, so a sheet's PNG is shared with a standalone `image` of that file.

Zero hot-path concerns — everything here happens at load/unload. The loaders
are injectable specifically so the cache logic is testable without Gosu
(`asset_manager.rb:22-24`), and `DEFAULT_LOADERS` references Gosu only inside
the procs so requiring the file pulls in no window.

**This class does not change at all except for the contents of
`DEFAULT_LOADERS`.** It is the clearest "stays in Ruby" in the whole layer.

### `Platform::GosuAudio` → `RGame::Core::Audio`

40 lines. A play-by-id registry over samples (one-shot) and songs (looping).
`play_music` is idempotent — it checks `song.playing?` so a scene re-emitting
`:play_music` never restarts a loop mid-play. `stop_music` reaches for
`Gosu::Song.current_song`, i.e. Gosu tracks a single global current song.

Needs from below: load-sample, load-song, play-one-shot, play-looping,
`playing?`, stop. The "current song" global is a Gosu design choice; the C layer
can either mirror it or let `Audio` track the handle itself (simpler, and keeps
`stop_music` from needing a global).

### `lib/platform/gosu_patches.rb` → deleted

Covered in [the brief](README.md#gosu_patchesrb-disappears-entirely).

---

## Things noticed along the way

Small, real, and easy to lose otherwise.

- **`core.c` hardcodes Escape-quits.** `rgame_app_poll_events` sets
  `running = 0` on `SDLK_ESCAPE` (`core.c:87`). That is game policy living in
  the engine; it must move out to a Ruby `button_down` override once key events
  are delivered. Same for the fact that the window-resize handler calls
  `glViewport` directly with no way for Ruby to hear about the resize.
- **`glEnable(GL_DEPTH_TEST)` is not z-ordering.** `core.c:58` enables the depth
  buffer, but Gosu's `z` semantics are "sort all draw calls by z, stable within
  a z, then draw in order" — which is what alpha blending requires (blending and
  depth-testing do not mix; a depth-tested translucent quad rejects fragments
  behind it instead of blending with them). The new renderer needs a real
  sorted draw queue. This is the largest single piece of hidden work in the
  rewrite and it is discussed in [02](02-architecture.md#the-draw-queue).
- **`SDL_Init` / `SDL_Quit` are per-app.** `rgame_app_create` calls `SDL_Init`
  and `rgame_app_destroy` calls `SDL_Quit` (`core.c:22`, `:77`). That is fine
  for exactly one app per process and breaks the moment there are two, or when
  an audio subsystem wants initialising independently. Worth fixing when audio
  lands, not before.
- **The known exception-safety gap in `platform_ext.c`** (documented at
  `platform_ext.c:100-106`): a raising Ruby callback longjmps straight through
  the C loop frame. Deferred "until the callbacks actually do real work" — which
  is precisely what phase 1 does, so it stops being deferrable then.
- **`spec/spec_helper.rb:3-5` has a stale comment** ("Requiring only lib/engine
  here"; it requires `lib/rgame`) and globs a `spec/support/` directory that
  does not exist. Harmless, worth a drive-by fix.
- **`.rubocop.yml` excludes reference `examples/01–08`** and `lib/engine/` paths
  that do not exist in this repo — leftovers from the source engine.
- **`gosu` in the `Gemfile`** is kept deliberately as the reference point and is
  required by nothing. It can be dropped once `lib/platform/` is gone.
