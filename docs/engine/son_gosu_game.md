# SonGosuGame

`SonGosuGame` (`lib/son_gosu_game.rb`) is the **entry point of a game**: a thin
facade that assembles the engine and platform pieces a running game needs, so a
game script doesn't have to wire them by hand. It is the only top-level class
that pulls in Gosu territory — it lives outside `lib/engine` precisely because it
reaches into the platform layer.

## Minimal game

A complete game is a root node plus three lines:

```ruby
require_relative '../lib/son_gosu_game'

class HelloScene < Engine::Node2D
  def on_draw(renderer)
    renderer.text('Hello world!', 250, 200)
  end
end

game = SonGosuGame.new(root: HelloScene.new, caption: 'Hello World')
game.start
```

See `examples/11_components/main.rb`. For a full game with scenes, assets and audio
wired by hand around the same facade, see `examples/14_asteroids` and
`examples/15_tiled_world`.

## What it assembles

`SonGosuGame.new(root:, width: 640, height: 480, caption: 'SonGosu Game', media_root: 'media',
action_map: {})` builds the object graph in one place:

- **`Engine::ActionMapper`** — turns physical input into a per-frame `Actions`
  snapshot, configured from `action_map` (see [Configuring input](#configuring-input)).
- **`Platform::AssetManager`** — the single loader/cache, rooted at `media_root` (see
  [Assets](#assets)). Exposed as the `assets` reader.
- **`Platform::GosuRenderer`** — the draw interface scenes render through, resolving draw
  assets through the asset manager. Exposed as the `renderer` reader.
- **`Platform::GameWindow`** — the Gosu shell that owns the fixed-timestep loop and
  drives the root node each tick.

It exposes `width`, `height`, `action_mapper`, `renderer` and `assets` as readers.

## The root and scenes

A game is a single tree under the `root:` node you pass in. There is **no separate
scene-manager facade** — scene navigation is just a node behaviour: a root carries an
`Engine::Scene::SceneStack` component and `push`/`replace`s scene nodes on it (the
stack marks each pushed node as a scene boundary, so [scene-scoped systems](systems.md)
resolve). `examples/14_asteroids` and `examples/15_tiled_world` both do this — a small
`Root < Engine::Node2D` that owns the stack and swaps scenes.

## `start`

`start` brings the game to life and blocks until the window closes:

1. assigns the game as the root's `context` (`root.context = self`), so a node can
   reach the platform through it (below);
2. enters the root subtree (`root.enter_tree`) — components attach, then `on_add`
   fires, depth-first (see [Lifecycle](scene_graph.md#lifecycle-constructing-vs-entering-the-tree));
3. opens the Gosu window and runs the loop.

It is idempotent (a second call is a no-op).

## Configuring input

Pass the binding map as `action_map:` at construction; the map is
`{ action => { axis: %i[neg pos] } | { button: %i[ids] } }` (see
[`ActionMapper`](../../lib/engine/input/action_mapper.rb)):

```ruby
game = SonGosuGame.new(
  root: Root.new,
  caption: 'My Game',
  action_map: {
    move_x:  { axis: %i[left right] },
    confirm: { button: %i[confirm] }
  }
)
```

`action_mapper.map` stays reassignable for remapping at runtime.

## Assets

The game owns the `AssetManager`, rooted at `media_root`, so nothing is loaded or registered
by hand:

```ruby
SonGosuGame.new(
  root: Root.new,
  media_root: MEDIA,
  action_map: { ... }
).start
```

A scene or component then names an asset by its **root-relative path** and resolves it itself
from the manager (the renderer resolves the same path when drawing). The manager loads each
file once, lazily, and caches it. See [AssetManager](asset_manager.md).

## Reaching the platform from a node

Some things a node needs only exist in the platform layer (the asset manager, the
renderer, audio). `start` sets `root.context = self` and this context never changes (the top `root` node is not swappable). Therefore `context` is lazily cached on its node and can be reached via `context` or `node.contet` on a component — `node.context.assets` for the manager,
`node.context.renderer` for the renderer. A component resolving its own asset looks
like:

```ruby
def on_attach
  sheet = node.context.assets.sheet(@sheet) # @sheet is a root-relative path
  # … build animation state, size the node, etc.
end
```

`register_sheet`/`register_image`/`register_tilemap` on the renderer remain as an optional
override (pre-binding an id to a specific object), but are unnecessary when assets are named by
path. See `examples/15_tiled_world` for a scene that resolves its map and actors this way.

## The loop

`SonGosuGame` only assembles; it does not run the loop itself. `Platform::GameWindow`
owns the fixed-timestep update/draw cycle (60 Hz simulation steps with a catch-up cap),
polls input once per tick, and drives `control`/`update`/`draw` (and the deferred-free
sweep) on the root each step. `SonGosuGame` hands it the root, renderer and mapper and
calls `show`.

## Debug overlay (F1)

Every game gets a development stats overlay for free — `Platform::GameWindow` always
wires up an `Engine::DebugOverlay` and draws it on top of the scene. It starts hidden;
press **F1** to toggle it (independent of the game's `action_map`). In the bottom-right
corner it shows three lines:

- **FPS** — frame rate, to catch performance drops.
- **OBJ** — the process' cumulative allocated-object count.
- **Δ/f** — objects allocated since the previous frame. This is the one to watch: a clean
  per-frame hot path holds it at ~0, code that allocates every frame shows a steady
  nonzero number.

The overlay obeys the engine's own no-per-frame-allocation rule. Its numbers change every
frame, so it can't cache a string and rebuild it on change (that rebuild would itself be a
per-frame allocation); instead it draws numbers digit-by-digit from a fixed set of cached
single-character strings, which `Gosu::Font` caches per glyph.
