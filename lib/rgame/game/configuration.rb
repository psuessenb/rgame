# frozen_string_literal: true

module RGame
  class Game < RGame::Core::App
    # Everything a game sets once, when it starts, except its root node and its
    # caption.
    #
    #   RGame::Game.new(root: Scene.new, caption: 'Hello',
    #                   configuration: RGame::Game::Configuration.new(width: 320, height: 180))
    #
    # A frozen value with a default for every member, so a game names only what
    # it changes. `with` derives one from another. A misspelt member raises
    # `ArgumentError`, naming it.
    #
    # `width` and `height` are the logical size: the resolution the game is
    # designed in. `scale_mode` decides what they mean. Under `:letterbox`, the
    # default, a node always draws into a view of that size, whatever the window
    # does. `:integer` and `:stretch` scale too, and `:disabled` hands the window
    # straight through as the view. See RGame::Engine::Presentation.
    #
    # `fullscreen` opens the window fullscreen, so a game that always runs
    # fullscreen never shows a windowed frame at startup. `width` and `height`
    # still give the size the window returns to.
    #
    # `media_root` is the directory asset paths are relative to. `locales` is
    # the directory of translation tables, relative to `media_root` unless
    # absolute. `Game.new` loads every `.yml` under it and picks the player's
    # language from the OS.
    #
    # `players` is how many seats the game has. Player 0 starts on `device`,
    # the keyboard unless `Controls.gamepad(slot)` names a controller. The other
    # seats fill when someone presses confirm on a controller; see
    # RGame::Engine::Players. `input_map` binds every player's actions, and
    # defaults to RGame::Engine::InputMap.default.
    #
    # `seed` seeds the game's random source, so a run with nothing saved plays
    # the same each time. `RGAME_SEED` wins when it is set. With neither, the
    # game picks a fresh seed.
    #
    # `input` replaces the input backend, and `audio` the sound device. A game
    # leaves both nil. tools/drive_test_project.rb passes a scripted backend and
    # a recording device through `with`, to drive a game with no hardware.
    # `Game` hands `audio` its asset manager with `assets=`, as `App` does its
    # own device, so a path id resolves through it.
    Configuration = Data.define(:width, :height, :scale_mode, :fullscreen, :media_root,
                                :locales, :players, :device, :input_map, :seed,
                                :input, :audio) do
      def initialize(width: 640, height: 480, scale_mode: :letterbox, fullscreen: false,
                     media_root: 'media', locales: 'locales', players: 1,
                     device: RGame::Util::Controls::KEYBOARD, input_map: nil, seed: nil,
                     input: nil, audio: nil)
        super
      end
    end
  end
end
