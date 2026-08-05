# Asset manager

`Platform::AssetManager` (`platform/asset_manager`) is the single place that loads and caches
file-backed assets — images, sounds, songs, sprite sheets, UI atlases, tilemaps, and raw files.
It exists so that loading is no longer scattered across each game's `main.rb` (building paths
ad-hoc and constructing Gosu objects inline): one object owns *what is loaded*, resolves every
path against one root, and guarantees each file is loaded **once** and shared.

It lives in the platform layer, not the engine, because it produces Gosu objects. Engine code only
reaches it through the `node.root.context` seam (duck-typed — a component asks
`node.root.context.assets` for a sheet by path), so the core takes no hard dependency on it.

## API

Construct it with a media root, then ask for assets by relative path:

```ruby
assets = Platform::AssetManager.new(root: MEDIA)

assets.image('space.png')                 # => Gosu::Image (retro:)
assets.sound('example 09/boom.ogg')       # => Gosu::Sample
assets.song('example 09/heartbeat.ogg')   # => Gosu::Song
assets.sheet('player.json')               # => Platform::SpriteSheet
assets.ui_atlas('ui/ui_atlas.json')       # => Platform::UiAtlas
assets.tilemap('map/island.tmx')          # => Platform::TileMapRenderer
assets.read('some/data.txt')              # => String (raw file contents)
```

Every accessor resolves its argument against `root` and memoises the result keyed by
`[type, relative_path]`. Asking for the same asset twice returns the **same instance** (loaded
once); the same path under two types (e.g. `image('x')` and `read('x')`) are distinct entries.
Plain (ungrouped) loads are kept for the process lifetime; assets loaded under a group can be
released as a set (see *Preload and scoped disposal* below).

`SonGosuGame` builds the manager from its `media_root:` and exposes it as `game.assets`, so a scene
or component names an asset by its root-relative path and resolves it itself (see
[SonGosuGame](son_gosu_game.md)) — no central loading or registration step.

## Renderer resolves through the manager; audio still registers

The asset manager is the *only* loader. `Platform::GosuRenderer` is given the manager and
**resolves a draw id through it** — `renderer.sprite('player.json', …)` resolves the path to its
`SpriteSheet`, caching the object so repeated draws don't re-resolve (or allocate a lookup key per
frame). So draw assets need no registration: name a relative path and draw with it. The
`register_*` methods remain as an optional override that pre-binds an id to a specific object
(used by the older examples and the UI atlas, whose nine-slice ids are atlas-element names, not
file paths).

```ruby
# new: nothing to register — the renderer resolves the path through the manager
renderer.sprite('player.json', row, col, x, y)

# still available: pre-bind an id to a chosen object
renderer.register_image(:space, assets.image('space.png'))
```

`Platform::GosuAudio` stays a pure id→object registry (`register_sound`/`register_music` take an
already-loaded `assets.sound`/`assets.song`), since play-by-id has no per-frame draw path to
resolve through.

Fonts are the one exception — they are system fonts (not loaded from a file), so the renderer
still creates its own `Gosu::Font`. When per-locale fonts arrive they can move behind an
`assets.font(path, size)` accessor.

## Injectable loaders (and why)

Each asset type maps to a loader proc in `DEFAULT_LOADERS` (e.g. `image: ->(path) {
Gosu::Image.new(path, retro: true) }`). The loaders are injectable via the constructor's
`loaders:` argument. This is deliberate: the procs reference Gosu/Platform classes only *inside*
their bodies (never at load time), and the file does **not** `require 'gosu'` — so the
cache/path-resolution logic is unit-testable headlessly by injecting fakes, with no window or GL
context. See `spec/platform/asset_manager_spec.rb`, which requires the file directly and verifies
path resolution, load-once/shared-instance, per-type keying, the unknown-type error, the grouping
and reference-counted release, and that a composite shares (and releases) its backing image.

The default Gosu loaders themselves aren't unit-tested (like `GosuRenderer`/`GosuAudio`); they're
exercised by running the examples.

## Preload and scoped disposal

Each cached asset records the **set of groups** that loaded it. Ungrouped accessor calls are owned
by a `PERMANENT` sentinel and survive every release; grouped loads are reference counted.

```ruby
assets.preload(:level1, image: ['lvl1/bg.png'], sound: ['lvl1/hit.ogg'], sheet: ['lvl1/foes.json'])
assets.image('ui/buttons.png')        # ungrouped → PERMANENT

assets.release(:level1)   # drops lvl1/* unless another group (or PERMANENT) still holds it
assets.clear              # drops everything, including PERMANENT
```

`preload(group, **manifest)` batch-loads under a group (the accessors also take an optional group
directly, e.g. `assets.image('x.png', :level1)`). `release(group)` removes the group from every
asset's owner set and drops any asset no group still holds — releasing the Ruby reference so GC
(and Gosu) free the underlying GPU resource. An asset two groups loaded survives until both
release it; a globally-loaded (ungrouped) asset is never released by `release`, only by `clear`.

## Sub-asset sharing

Composite assets load their backing image **through the cache**, so a sheet's PNG is shared with a
standalone `assets.image` of the same file (and is released with the composite's group). The split
mirrors `Platform::TileMapRenderer.load`: `SpriteSheet`/`UiAtlas` now take a ready image +
descriptor (`new(image, data)`), with a `self.load(path)` convenience for standalone use. The
AssetManager assembles them — it reads the descriptor (via the cached `read`), resolves the image
path *next to* the descriptor (root-relative, so it lands on the same `[:image, path]` cache key),
and constructs the composite with that shared image.

## Future refinements

* **Tilemap tileset image.** `TileMapRenderer` loads its tileset via `Gosu::Image.load_tiles` (an
  array of tile images, not a single `Gosu::Image`), so it doesn't fit the shared image cache and
  is left as-is.
* **Cross-group composites.** A composite tags its sub-assets with the group that first built it;
  if a *second* group later requests the same already-cached composite, only the composite's own
  key is re-tagged, not its sub-assets. Fine for the usual "each level owns its assets" pattern;
  full sub-key tracking would close the gap if a composite is ever shared across overlapping groups.
