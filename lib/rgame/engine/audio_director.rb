# frozen_string_literal: true

module RGame
  module Engine
    # The registered handler that turns audio *events* into audio *playback*.
    # Gameplay emits facts — `:play_sound`/`:play_music`/`:stop_music` with the asset
    # id as payload — through the EventDispatcher, never touching the backend; this
    # observer forwards each to an injected audio server (anything responding to
    # #play_sound/#play_music/#stop_music: `RGame::Core::Audio` in a game, a recording
    # fake in specs). Pure logic — it names no audio class, and the 'an audio server'
    # contract in spec/support/shared_examples/ is the interface it calls, so a
    # stand-in is checked against what the real device does.
    class AudioDirector
      def initialize(audio)
        @audio = audio
      end

      # Subscribe to the audio events on a hub (the global AudioBus by default, but
      # any object exposing the same three signals). Returns self, so a caller can
      # build and subscribe in one expression.
      #
      # **The handles are kept, so `unsubscribe` can take them back off.** AudioBus
      # is a module — one hub for the whole process — and it holds its listeners
      # until something removes them. A connected director is therefore reachable
      # from a global, and it keeps the audio device alive, along with the asset
      # manager that device resolves paths through and the App that manager loads
      # images for, down to the window.
      #
      # A game never notices, because its App lives as long as the process does.
      # Anywhere an App is created and discarded — a spec, a tool,
      # `tools/drive_test_project.rb` — it is the difference between a window
      # closing and a window leaking. RGame::Game subscribes a director when it
      # starts and releases it when the loop ends, which is why a game calls
      # neither method itself.
      def subscribe(audio_bus = Engine::AudioBus)
        @bus = audio_bus
        @handles = [
          audio_bus.on_play_sound.connect { @audio.play_sound(it) },
          audio_bus.on_play_music.connect { @audio.play_music(it) },
          audio_bus.on_stop_music.connect { @audio.stop_music }
        ]
        self
      end

      # Takes this director's listeners back off the hub. Safe to call twice, and
      # safe on a director that was never subscribed — releasing something is not
      # a good place to be strict about how many times it happens.
      def unsubscribe
        return self if @handles.nil?

        @bus.on_play_sound.disconnect(@handles[0])
        @bus.on_play_music.disconnect(@handles[1])
        @bus.on_stop_music.disconnect(@handles[2])
        @handles = nil
        self
      end
    end
  end
end
