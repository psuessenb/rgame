# frozen_string_literal: true

require_relative 'core'
require_relative '../engine'

module RGame
  # The entry point of a game, and the one class that knows both halves.
  #
  #   class HelloScene < Engine::Node2D
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

    attr_reader :root, :renderer, :action_mapper

    def initialize(root:, width: WIDTH, height: HEIGHT, caption: 'RGame',
                   media_root: 'media', action_map: {})
      super(width: width, height: height, caption: caption, media_root: media_root)

      @root = root
      @renderer = RGame::Core::Renderer.new(self)
      @input = RGame::Core::Input.new(self)
      @action_mapper = Engine::ActionMapper.new(action_map)
      @overlay = Engine::DebugOverlay.new # always wired up; F1 reveals it
      @dirty = true # draw the first frame

      install_asset_loaders
    end

    # Brings the tree live and runs until the window closes.
    #
    # The root gets this object as its `context`, which is how a node deep in
    # the tree reaches the asset manager (`node.root.context.assets`) without
    # anything being threaded through its constructor.
    def start
      @root.context = self
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
      @root.control(@action_mapper.poll(@input))
      @root.update(dt)
      @root.sweep_freed # flush queue_free'd nodes outside the update traversal
      @dirty = true
    end

    # Only the simulation advancing makes the frame stale. While the overlay is
    # up, redraw anyway, so its numbers stay live even when nothing is moving.
    def needs_redraw? = @dirty || @overlay.visible?

    def draw
      @root.draw(@renderer)
      @overlay.draw(@renderer, width, height, fps) # last, so it layers on top
      @dirty = false
    end

    def button_down(id)
      close if id == Controls::KEY_ESCAPE
      @overlay.toggle if id == Controls::KEY_F1
    end

    private

    # Teaches the asset manager the types Core cannot build for itself.
    #
    # `:tilemap` is the only one so far, and it is the reason this method
    # exists: `Engine::TileMap` reads the `.tmx`, `Image#tiles` slices the
    # tileset through the cache — so two maps sharing a tileset share one
    # upload — and `Core::TileMapRenderer` draws the result. Three objects, and
    # neither of the outer two may name the other.
    def install_asset_loaders
      game = self
      assets.add_loader(:tilemap) do |path|
        map, image_path = Engine::TileMap.load(path)
        tiles = game.assets.image(image_path)
                    .tiles(map.tileset.tile_width, map.tileset.tile_height)
        RGame::Core::TileMapRenderer.new(map, tiles)
      end
    end
  end
end
