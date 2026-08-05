# frozen_string_literal: true

module Engine
  # The registered handler that turns audio *events* into audio *playback*.
  # Gameplay emits facts — `:play_sound`/`:play_music`/`:stop_music` with the asset
  # id as payload — through the EventDispatcher, never touching the backend; this
  # observer forwards each to an injected audio server (anything responding to
  # #play_sound/#play_music/#stop_music: Platform::GosuAudio in the app, a recording
  # fake in tests). Pure logic; no Gosu — the Gosu dependency stays in the server.
  class AudioDirector
    def initialize(audio)
      @audio = audio
    end

    # Subscribe to the audio events on a hub (the global EventDispatcher by default,
    # but any object with #on). Returns self so callers can build-and-subscribe in one
    # line. The director lives for the whole app, so nothing unsubscribes it.
    def subscribe(audio_bus = Engine::AudioBus)
      audio_bus.on_play_sound.connect { @audio.play_sound(it) }
      audio_bus.on_play_music.connect { @audio.play_music(it) }
      audio_bus.on_stop_music.connect { @audio.stop_music }
      self
    end
  end
end
