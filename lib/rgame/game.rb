# frozen_string_literal: true

require_relative 'boot'
require_relative 'core'
require_relative 'engine'

module RGame
  # The entry point of a game, and the one class that knows both halves.
  #
  #   class HelloScene < RGame::Engine::Node2D
  #     def on_draw(renderer) = renderer.text('Hello world!', 250, 200)
  #   end
  #
  #   RGame::Game.new(root: HelloScene.new, caption: 'Hello').start
  #
  # A complete game is a root node plus that. `Game` assembles the pieces
  # around it — the window and its loop, the renderer, the asset manager, the
  # sound device, the input mapper, the debug overlay — and drives the root
  # node once per tick.
  #
  # ## Why this class is allowed to name both layers
  #
  # `RGame::Engine` holds game concepts and may not name `RGame::Core`;
  # `RGame::Core` owns handles and may not know Engine exists. Two RuboCop cops
  # say so. Something still has to introduce them, and **this is that
  # something** — see CLAUDE.md, "The rule points both ways". Keeping the
  # introduction to one file is what makes the rule checkable everywhere else,
  # so wiring belongs here and only here.
  #
  # The tile-map loader is the clearest case. Parsing a `.tmx` is Engine's job
  # and drawing one is Core's, and neither may call the other, so `Game`
  # installs the loader that joins them.
  #
  # ## The loop
  #
  # `Game` is an `App`, so it inherits the fixed-timestep loop rather than
  # running one. Its hooks do three things: sample input once per frame, drive
  # the root once per tick, and draw. Nothing here counts steps or measures
  # time — `frame_loop.c` does that, and `update` is called once per whole tick.
  class Game < RGame::Core::App
    Controls = RGame::Util::Controls

    WIDTH = 640
    HEIGHT = 480

    attr_reader :root, :renderer

    # `input_map:` is what physical inputs mean — one entry per action, naming
    # ids from RGame::Util::Controls. It is merged over the universal UI set, so
    # `ui_confirm` and friends work whether or not a game declares them, and it
    # defaults to RGame::Engine::InputMap::DEFAULT_ACTIONS, so a game wanting
    # eight-way movement and a fire button declares nothing.
    #
    # `device:` is which device drives it — the keyboard, or
    # `Controls.gamepad(slot)` for a controller.
    #
    # `input:` overrides the input backend. It exists so a harness can drive a
    # game from a script instead of from hardware — see tools/drive_example.rb,
    # and CLAUDE.md's "The examples are the acceptance test for wiring", which
    # is why driving one has to be possible at all. A game passes nothing and
    # gets the real thing.
    def initialize(root:, width: WIDTH, height: HEIGHT, caption: 'RGame',
                   media_root: 'media', input_map: nil, device: Controls::KEYBOARD,
                   input: nil)
      super(width: width, height: height, caption: caption, media_root: media_root)

      @root = root
      @renderer = RGame::Core::Renderer.new(self)
      @input = input || RGame::Core::Input.new(self)
      @players = RGame::Engine::Players.new(
        [RGame::Engine::Player.new(id: 0, device: device, input_map: input_map)]
      )
      @viewports = RGame::Engine::Viewports.new(@players, width: width, height: height)
      @debug = RGame::Engine::DebugOverlay.new # always wired up; F1 reveals it
      @dirty = true # draw the first frame

      install_asset_loaders
    end

    # The player registry, also reachable from any node as
    # `node.system(RGame::Engine::Players)` — which is how a scene gets at a
    # camera to follow, without anything being threaded into its constructor.
    #
    # One player exists from the start, so a single-player game never mentions
    # players at all: it is `players.primary` that an unowned node reads from,
    # and `players.primary.camera` that a scene points at its hero.
    attr_reader :players

    # How the screen is divided. Reachable as `node.system(RGame::Engine::Viewports)`,
    # which is how a cutscene deep in a scene collapses the split without
    # anything being handed to it.
    attr_reader :viewports

    # Brings the tree live and runs until the window closes.
    #
    # The root gets this object as its `context`, which is how a node deep in
    # the tree reaches the asset manager (`node.root.context.assets`) without
    # anything being threaded through its constructor.
    def start
      @root.context = self
      # Root-scoped systems, mounted before the tree comes alive so that an
      # on_add anywhere in it can already resolve node.system(...) for either.
      @root.add_component(@players)
      @root.add_component(@viewports)
      @root.enter_tree # components attach, then on_add
      run
    end

    # One fixed simulation tick. `dt` is always the engine's fixed step, so the
    # tree never sees variable frame time.
    #
    # **Input is polled here, per tick, not in `frame_begin` per frame.** That
    # is not where it started, and the reason is edge detection: `pressed?` is
    # "held now, not held at the previous poll", so whatever polls decides what
    # a press *is*. `frame_begin` runs once per rendered frame, and a loop that
    # renders faster than it simulates runs it many times between two ticks —
    # each one shifting the previous state, so the press is consumed by a poll
    # no tick ever reads. Menus stop responding, and only on fast machines.
    #
    # Polling per tick costs nothing extra and loses nothing: the C layer
    # snapshots the keyboard once per frame, so several ticks inside one frame
    # read identical state, and the edge lands on the first of them — one press,
    # one `pressed?`, which is what a caller means.
    def update(dt)
      @players.poll(@input)
      # The registry, not one player's snapshot: each node resolves the actions
      # of whoever owns it, and a node that claims nobody gets the primary.
      @root.control(@players)
      @root.update(dt)
      @root.sweep_freed # flush queue_free'd nodes outside the update traversal
      @dirty = true
    end

    # Only the simulation advancing makes the frame stale. While the overlay is
    # up, redraw anyway, so its numbers stay live even when nothing is moving.
    def needs_redraw? = @dirty || @debug.visible?

    # The tree is drawn once, with the whole window as its view. Screen-space
    # content — a HUD, a menu, a title card — lands there and is drawn exactly
    # once, as it always was.
    #
    # **World content multiplies inside the tree, not here.** An
    # RGame::Engine::WorldView draws its subtree once per viewport, clipping and
    # translating for each, so where the world begins is the game's choice
    # rather than a shape the platform imposes. That is also what keeps
    # `node.root` meaning the game's own root: nothing is inserted above it.
    def draw
      @viewports.refresh # rects from the layout, then reclamp every camera
      @root.draw(@renderer, @viewports.screen)
      @debug.draw(@renderer, @viewports.screen, fps) # last, so it layers on top
      @dirty = false
    end

    # The window changed size, so every rect and every camera clamp does too.
    def resize(width, height) = @viewports.resize(width, height)

    # A controller arriving fills the first seat waiting for one, and leaving
    # empties whichever seat it was in — the player themselves, with their
    # camera and bindings, stays put. A game whose player already has the
    # keyboard is untouched by either.
    def gamepad_connected(slot) = @players.claim_gamepad(slot)
    def gamepad_disconnected(slot) = @players.release_gamepad(slot)

    # The two development keys, both function keys on purpose: **Escape is
    # deliberately not bound here**, because it is the natural `cancel`/`back`
    # button for a game's own menus, and a debug shortcut has no business taking
    # the one key every player expects to close a dialog. F1 shows the overlay,
    # F2 quits.
    def button_down(id)
      close if id == Controls::KEY_F2
      @debug.toggle if id == Controls::KEY_F1
    end

    private

    # Teaches the asset manager the types Core cannot build for itself.
    #
    # `:tilemap` is the only one so far, and it is the reason this method
    # exists: `RGame::Engine::TileMap` reads the `.tmx`, `Image#tiles` slices the
    # tileset through the cache — so two maps sharing a tileset share one
    # upload — and `Core::TileMapRenderer` draws the result. Three objects, and
    # neither of the outer two may name the other.
    def install_asset_loaders
      game = self
      assets.add_loader(:tilemap) do |path|
        map, image_path = RGame::Engine::TileMap.load(path)
        tiles = game.assets.image(image_path)
                    .tiles(map.tileset.tile_width, map.tileset.tile_height)
        RGame::Core::TileMapRenderer.new(map, tiles)
      end
    end
  end
end
