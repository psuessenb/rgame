# frozen_string_literal: true

require_relative 'boot'
require_relative 'core'
require_relative 'engine'

module RGame
  # The entry point of a game, and the one class that knows both halves.
  #
  #   class HelloScene < RGame::Engine::Node2D
  #     def _draw(renderer) = renderer.text('Hello world!', 250, 200)
  #   end
  #
  #   RGame::Game.new(root: HelloScene.new, caption: 'Hello').start
  #
  # A complete game is a root node plus that. `Game` assembles the pieces
  # around it — the window and its loop, the renderer, the asset manager, the
  # sound device, the input mapper, the debug layer — and drives the root
  # node once per tick.
  #
  # ## Why this class is allowed to name both layers
  #
  # `RGame::Engine` holds game concepts and may not name `RGame::Core`;
  # `RGame::Core` owns handles and may not know Engine exists. Two RuboCop cops
  # say so. Something still has to introduce them, and **this is that
  # something** — see "The rule points both ways". Keeping the
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
    # game from a script instead of from hardware — see
    # tools/drive_test_project.rb, and "The test projects are the acceptance test
    # for wiring", which is why driving one has to be possible at all. A game passes nothing and gets the real thing.
    # `audio:` overrides the sound device the same way, for the same harness,
    # which wraps the real one to record what plays. It is handed this game's
    # asset manager with `assets=`, as the device `App` builds is, so a path id
    # resolves and the manager decodes samples through it.
    # `players:` is how many seats the game has, and therefore the most people
    # who can play it. Player 0 starts on `device:`; the rest start empty and
    # are filled when someone uses a controller — see RGame::Engine::Players for
    # why that is a press rather than a plug.
    # `fullscreen:` opens the window fullscreen rather than switching after it is
    # already up, so a game that always runs fullscreen never flashes a windowed
    # frame at startup. `width` and `height` still matter: they are the size the
    # window takes when it leaves fullscreen, whether or not this game offers a
    # way to do that.
    #
    # `scale_mode:` decides what `width` and `height` *mean*, and the default
    # answer is "the resolution the game is designed in". Under `:letterbox` the
    # view a node draws into is always that size, whatever the window is doing,
    # so a layout written against fixed numbers keeps working at any window size
    # and in fullscreen — which is what almost every game wants and what nothing
    # in the engine can supply for it afterwards.
    #
    # `:disabled` is the opt-out, and it is the right answer for something that
    # should genuinely use whatever space it is given: a tool, a HUD-shaped
    # program, an editor. It hands the window straight through as the view, and
    # skips the clip, translate and scale that every other mode pushes. See
    # RGame::Engine::Presentation.
    #
    # `locales:` is the directory the translation tables are in, relative to
    # `media_root` unless absolute. Every `.yml` under it is loaded through the
    # asset manager here, in sorted order, and the language is chosen from the
    # player's OS preferences — so a game writes no i18n setup, and a language
    # the player saved is set after `new` and before `start`. A directory that
    # does not exist loads nothing, and every key shows as itself.
    #
    # `seed:` seeds the game's random source, so a run with nothing saved plays
    # the same each time. `RGAME_SEED` wins when it is set, which is how
    # `tools/drive_test_project.rb --seed N` repeats a run. With neither, the
    # game picks a fresh seed, and `random_source.seed` reads it back.
    def initialize(root:, width: WIDTH, height: HEIGHT, caption: 'RGame',
                   media_root: 'media', input_map: nil, device: Controls::KEYBOARD,
                   players: 1, input: nil, audio: nil, fullscreen: false, scale_mode: :letterbox,
                   locales: 'locales', seed: nil)
      super(width: width, height: height, caption: caption, media_root: media_root,
            fullscreen: fullscreen)

      @root = root
      @renderer = RGame::Core::Renderer.new(self)
      @input = input || RGame::Core::Input.new(self)
      @audio_device = audio
      audio&.assets = assets
      @players = RGame::Engine::Players.new(
        Array.new(players) do |id|
          RGame::Engine::Player.new(id: id, device: id.zero? ? device : nil,
                                    input_map: input_map)
        end
      )
      @presentation = RGame::Engine::Presentation.new(width: width, height: height,
                                                      mode: scale_mode)
      @presentation.fit(self.width, self.height)
      @viewports = RGame::Engine::Viewports.new(@players, width: @presentation.width,
                                                          height: @presentation.height)
      @facts = RGame::Engine::Components::Facts.new
      @random_source = RGame::Engine::Components::RandomSource.new(seed: chosen_seed(seed))
      @debug = RGame::Engine::Debug.new
      @debug_keys = true
      @dirty = true

      install_asset_loaders
      load_locales(locales)
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

    # The flags and named state machines a game saves as one entry. Reachable
    # as `node.system(RGame::Engine::Components::Facts)`, so a quest built deep
    # in a scene registers with the same store the save code writes.
    attr_reader :facts

    # The seeded random numbers every node draws from. Reachable as
    # `node.system!(RGame::Engine::Components::RandomSource)`, so a walker deep in
    # a scene rolls from the same sequence as everything else.
    attr_reader :random_source

    # The development layer: the channels F1 and F3 switch, and the ones a game
    # defines. Reachable as `node.system(RGame::Engine::Debug)` from anywhere in
    # the tree, which is how a scene turns its own channel on.
    attr_reader :debug

    # Whether F1, F2 and F3 do anything. `false` is a build a player runs: the
    # overlay, the shapes and the quit key all stop answering, and a game that
    # still wants a channel switches it itself.
    attr_accessor :debug_keys

    # The sound device: the one passed as `audio:`, or the one `App` builds on
    # first use. Nodes reach it through the RGame::Engine::AudioOut system on
    # the root, which `start` mounts.
    def audio = @audio_device || super

    # Brings the tree live and runs until the window closes.
    #
    # The root gets this object as its `context`, which is how a node deep in
    # the tree reaches the asset manager (`node.root.context.assets`) without
    # anything being threaded through its constructor.
    def start
      @root.context = self
      @root.add_component(@players)
      @root.add_component(@viewports)
      @root.add_component(@facts)
      @root.add_component(@random_source)
      @root.add_component(@debug)
      @root.add_component(RGame::Engine::AudioOut.new(audio))
      @root.enter_tree
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
      @players.poll(@input, dt)
      @root.control(@players)
      @root.update(dt)
      @root.sweep_freed
      @dirty = true
    end

    # Only the simulation advancing makes the frame stale. While the overlay is
    # up, redraw anyway, so its numbers stay live even when nothing is moving.
    def needs_redraw? = @dirty || @debug.shows?(:stats)

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
      @viewports.refresh
      if @presentation.scaled?
        presented { draw_tree }
      else
        draw_tree
      end
      @dirty = false
    end

    # How `width` and `height` are mapped onto the window: `:disabled`,
    # `:stretch`, `:letterbox` or `:integer`. See RGame::Engine::Presentation.
    def scale_mode = @presentation.mode

    # Switchable while the game runs, for a settings screen.
    #
    # The viewports are resized as well as the presentation refitted, because
    # the two modes disagree about what the logical size *is*: leaving `:integer`
    # for `:disabled` turns a fixed 640x480 back into the window's own size, and
    # a viewport still holding the old one would lay out into a corner.
    def scale_mode=(mode)
      @presentation.mode = mode
      @viewports.resize(@presentation.width, @presentation.height)
    end

    # The window changed size, so the presentation is refitted and every rect and
    # camera clamp follows. Under a scaling mode the logical size does not move,
    # so the viewports are handed the same numbers again and only the transform
    # in `draw` changes — which is the whole point of the mode.
    def resize(width, height)
      @presentation.fit(width, height)
      @viewports.resize(@presentation.width, @presentation.height)
    end

    # Hot-plug is bookkeeping, not seating: a controller arriving becomes a
    # device the registry watches, and it is someone *using* it that gives it to
    # a player. Leaving takes it back off whoever had it.
    def gamepad_connected(slot) = @players.device_connected(slot)
    def gamepad_disconnected(slot) = @players.device_disconnected(slot)

    # The three development keys, all function keys on purpose: **Escape is
    # deliberately not bound here**, because it is the natural `cancel`/`back`
    # button for a game's own menus, and a debug shortcut has no business taking
    # the one key every player expects to close a dialog. F1 shows the stats
    # overlay, F2 quits, and F3 shows the collision shapes. `debug_keys = false`
    # turns all three off.
    #
    # These come from the window's own events rather than from a polled action,
    # so a game driven by a scripted input backend never reaches them — see
    # RGame::Engine::Debug.
    def button_down(id)
      return unless @debug_keys

      close if id == Controls::KEY_F2
      @debug.toggle(:stats) if id == Controls::KEY_F1
      @debug.toggle(:shapes) if id == Controls::KEY_F3
    end

    private

    def chosen_seed(seed)
      from_env = ENV.fetch('RGAME_SEED', nil)
      return Integer(from_env) if from_env

      seed || Random.new_seed
    end

    def draw_tree
      @debug.fps = fps
      @root.draw(@renderer, @viewports.screen)
    end

    def presented(&)
      @renderer.clipped(@presentation.offset_x, @presentation.offset_y,
                        (@presentation.width * @presentation.scale_x).round,
                        (@presentation.height * @presentation.scale_y).round) do
        @renderer.translated(@presentation.offset_x, @presentation.offset_y) do
          @renderer.scaled(@presentation.scale_x, @presentation.scale_y, &)
        end
      end
    end

    def load_locales(directory)
      assets.glob(File.join(directory, '**', '*.yml')).each { |path| assets.locale(path) }
      RGame::Engine::I18n.locale = RGame::Engine::I18n.choose(RGame::Core.preferred_locales)
    end

    def install_asset_loaders
      assets.add_loader(:locale) do |path|
        RGame::Engine::I18n.load(File.read(path), source: path)
      end

      assets.add_loader(:tilemap) do |path|
        tiled = RGame::Engine::Tiled::Map.load(path)
        map = RGame::Engine::TileMap.from_tiled(tiled)
        RGame::Core::TileMapRenderer.new(map, tile_images(tiled, map), layer_images: layer_images(map))
      end
    end

    def layer_images(map)
      Array.new(map.layer_count) do |index|
        layer = map.layer(index)
        assets.image(layer.image) if layer.kind == :image && layer.image
      end
    end

    def tile_images(tiled, map)
      sheets = tiled.tilesets.map { sliced(it.tileset) }
      map.tile_table.map { it && sheets[it.tileset][it.local_id] }
    end

    def sliced(tileset)
      return tileset.tiles.transform_values { assets.image(it.image.source) } if tileset.collection?

      assets.image(tileset.image.source).tiles(tileset.tile_width, tileset.tile_height,
                                               margin: tileset.margin, spacing: tileset.spacing,
                                               count: tileset.tile_count, columns: tileset.columns)
    end
  end
end
